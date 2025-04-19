{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, nixos-generators, nixos-anywhere, ... }: flake-parts.lib.mkFlake { inherit inputs; } (
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
      };

      beaconSSHPriv = ./tests/one;
      beaconSSHPub = ./tests/one.pub;

      beaconHostKeyPriv = ./tests/two;
      beaconHostKeyPub = ./tests/two.pub;
      beaconKnownKeyFile = (pkgs.runCommand "knownhosts" {} ''
        mkdir -p $out/.ssh
        echo -n '* ' > $out/known_hosts
        cat ${beaconHostKeyPub} | ${pkgs.coreutils}/bin/cut -d' ' -f-2 >> $out/known_hosts
      '') + "/known_hosts";
    in {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    perSystem = { self', inputs', pkgs, system, ... }: {
      packages = {
        inherit (inputs'.nixpkgs.legacyPackages) age util-linux openssl openssh;

        init = import ./modules/initialgen.nix { inherit pkgs; };

        # nix build .#beacon
        # Intended to be run from the template.
        beacon = nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";

          modules = [
            ./modules/beacon.nix
            self.nixosModules.beacon
            ({ modulesPath, ... }: {
              imports = [
                (modulesPath + "/profiles/qemu-guest.nix")
              ];
            })
          ];
        };

        # nix run .#demo-beacon [<port> [<boot-port>]]
        # Intended to be run from the template.
        demo-beacon = let
          iso = "${self'.packages.beacon}/iso/beacon.iso";
          nixos-qemu = pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
          qemu = nixos-qemu.qemuBinary pkgs.qemu;
        in (pkgs.writeShellScriptBin "runner.sh" ''
          disk1=.skarabox-tmp/disk1.qcow2
          disk2=.skarabox-tmp/disk2.qcow2
          disk3=.skarabox-tmp/disk3.qcow2

          mkdir -p .skarabox-tmp
          for d in $disk1 $disk2 $disk3; do
            [ ! -f $d ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 $d 20G
          done

          port=$1
          shift
          bootport=$1
          shift

          ${qemu} \
            -m 2048M \
            -net nic -net user,hostfwd=tcp::''${port:-2222}-:22,hostfwd=tcp::''${bootport:-2223}-:2222 \
            --virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store \
            --drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware} \
            --drive media=cdrom,format=raw,readonly=on,file=${iso} \
            --drive format=qcow2,file=$disk1,if=none,id=nvm \
            --device nvme,serial=deadbeef,drive=nvm \
            --drive id=disk2,format=qcow2,if=none,file=$disk2 \
            --device ide-hd,drive=disk2 \
            --drive id=disk3,format=qcow2,if=none,file=$disk3 \
            --device ide-hd,drive=disk3 \
            $@
          '');

        # nix run .#install-on-beacon <ip> <port> <flake>
        # nix run .#install-on-beacon 192.168.1.10 22 .#skarabox
        # Intended to be run from the template.
        install-on-beacon = pkgs.writeShellScriptBin "runner.sh" ''
          mkdir -p .skarabox-tmp
          key=.skarabox-tmp/key
          cp ${beaconSSHPriv} "$key"
          chmod 600 "$key"

          if [ -f root_passphrase ]; then
            root_passphrase=root_passphrase
          else
            root_passphrase=.skarabox-tmp/root_passphrase
            echo rootpassphrase > $root_passphrase
          fi

          if [ -f data_passphrase ]; then
            data_passphrase=data_passphrase
          else
            data_passphrase=.skarabox-tmp/data_passphrase
            echo datapassphrase > $data_passphrase
          fi

          ${inputs'.nixos-anywhere.packages.nixos-anywhere}/bin/nixos-anywhere \
            --flake $3 \
            --disk-encryption-keys /tmp/root_passphrase $root_passphrase \
            --disk-encryption-keys /tmp/data_passphrase $data_passphrase \
            -i "$key" \
            --ssh-option "UserKnownHostsFile=${beaconKnownKeyFile}" \
            --ssh-port ''$2 \
            nixos@''$1
        '';

        # nix run .#ssh <ip> [<port> [<user> [<command> ...]]]
        # nix run .#ssh 192.168.1.10
        # nix run .#ssh 192.168.1.10 22
        # Intended to be run from the template.
        ssh = pkgs.writeShellScriptBin "ssh.sh" ''
          ip=$1
          shift
          port=$1
          shift
          user=$1
          shift

          ${pkgs.openssh}/bin/ssh \
            -p ''${port:-22} \
            ''${user:-skarabox}@''$ip \
            -o IdentitiesOnly=yes \
            -i ssh_skarabox \
            $@
        '';

        # nix run .#beacon-ssh <ip> [<port> [<user> [<command> ...]]]
        # nix run .#beacon-ssh
        # nix run .#beacon-ssh 127.0.0.1
        # nix run .#beacon-ssh 127.0.0.1 2222
        # nix run .#beacon-ssh 127.0.0.1 2222 nixos
        # nix run .#beacon-ssh 127.0.0.1 2222 echo "hello from inside"
        # Intended to be run from the template.
        beacon-ssh = pkgs.writeShellScriptBin "ssh.sh" ''
          ip=$1
          shift
          port=$1
          shift
          user=$1
          shift

          mkdir -p .skarabox-tmp
          key=.skarabox-tmp/key
          cp ${beaconSSHPriv} "$key"
          chmod 600 "$key"

          ${pkgs.openssh}/bin/ssh \
            -F none \
            -p ''${port:-2222} \
            ''${user:-skarabox}@''${ip:-127.0.0.1} \
            -o IdentitiesOnly=yes \
            -o ConnectTimeout=10 \
            -i "$key" \
            -o UserKnownHostsFile=${beaconKnownKeyFile} \
            $@
        '';
      };

      checks = import ./tests {
        inherit pkgs inputs system;
      };
    };

    flake = {
      templates = {
        skarabox = {
          path = ./template;
          description = "Skarabox template";
        };

        default = self.templates.skarabox;
      };

      nixosModules.beacon = {
        imports = [
          ./modules/beacon.nix
          ({ modulesPath, ... }: {
            imports = [
              (modulesPath + "/profiles/minimal.nix")
            ];

            boot.loader.systemd-boot.enable = true;
          })
          { # Set shared host key
            services.openssh.hostKeys = pkgs.lib.mkForce [];
            environment.etc."ssh/ssh_host_ed25519_key" = {
              source = beaconHostKeyPriv;
              mode = "0600";
            };
          }
          { # Set shared ssh key
            users.users."nixos" = {
              openssh.authorizedKeys.keyFiles = [ beaconSSHPub ];
            };
          }
        ];
      };

      nixosModules.skarabox = {
        imports = [
          nixos-anywhere.inputs.disko.nixosModules.disko
          ./modules/disks.nix
          ./modules/configuration.nix
        ];
      };

      # Module with some test preset that match the demo-beacon.
      nixosModules.demo-skarabox = {
        imports = [
          ({ modulesPath, ... }: {
            imports = [
              (modulesPath + "/profiles/qemu-guest.nix")
              (modulesPath + "/profiles/minimal.nix")
            ];
          })
          self.nixosModules.skarabox
        ];
        skarabox.hostname = "skarabox";
        skarabox.username = "skarabox";
        skarabox.sshAuthorizedKeyFile = beaconSSHPub;
        skarabox.disks.rootDisk = "/dev/nvme0n1";
        skarabox.disks.rootReservation = "500M";
        skarabox.disks.enableDataPool = true;
        skarabox.disks.dataDisk1 = "/dev/sda";
        skarabox.disks.dataDisk2 = "/dev/sdb";
        skarabox.disks.dataReservation = "10G";
        # e1000 found by running lspci -v | grep -iA8 'network\|ethernet' in the beacon VM
        skarabox.disks.networkCardKernelModules = [ "e1000" ];
        skarabox.hostId = "12345678";
      };

      nixosConfigurations.demo-skarabox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.demo-skarabox
        ];
      };
    };
  });
}
