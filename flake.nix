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

      # mkKnownHostsFile <pub_key> <ip> <port> [<port>...]
      mkKnownHostsFile = pkgs.writeShellScriptBin "mkKnownHostsFile.sh" ''
        pub=$(cat $1 | ${pkgs.coreutils}/bin/cut -d' ' -f-2)
        shift
        ip=$1
        shift

        for port in "$@"; do
          echo "[$ip]:$port $pub"
        done
      '';

    in {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    perSystem = { self', inputs', pkgs, system, ... }: {
      packages = {
        inherit (inputs'.nixpkgs.legacyPackages) age mkpasswd util-linux openssl openssh;

        inherit mkKnownHostsFile;

        init = import ./modules/initialgen.nix { inherit pkgs; };

        # Install a nixosConfigurations instance (<flake>) on a server.
        #
        # This command is intended to be run against a server which
        # was booted on the beacon. Although, the server could be booted
        # on any OS supported by nixos-anywhere. The latter was not tested.
        #
        # It is intended to run this command from the template.
        install-on-beacon = pkgs.writeShellScriptBin "install-on-beacon.sh" ''
         usage () {
           cat <<USAGE
Usage: $0 -i IP -p PORT -f FLAKE -k HOST_KEY -r ROOT_PASSPHRASE_FILE -d DATA_PASSPHRASE_FILE [-a EXTRA_OPTS]

  -h:                       Shows this usage
  -i IP:                    IP of the target host running the beacon.
  -p PORT:                  Port of the target host running the beacon.
  -f FLAKE:                 Flake to install on the target host.
  -k HOST_KEY_FILE:         SSH key to use as the host identification key.
  -r ROOT_PASSPHRASE_FILE:  File containing the root passphrase used to encrypt the root ZFS pool.
  -d DATA_PASSPHRASE_FILE:  File containing the data passphrase used to encrypt the data ZFS pool.
  -a EXTRA_OPTS:            Extra options to pass verbatim to nixos-anywhere.
USAGE
          }
          while getopts "hi:p:f:k:r:d:a:" o; do
            case "''${o}" in
              h)
                usage
                exit 0
                ;;
              i)
                ip=''${OPTARG}
                ;;
              p)
                port=''${OPTARG}
                ;;
              f)
                flake=''${OPTARG}
                ;;
              k)
                host_key_file=''${OPTARG}
                ;;
              r)
                root_passphrase_file=''${OPTARG}
                ;;
              d)
                data_passphrase_file=''${OPTARG}
                ;;
              a)
                extra_opts=''${OPTARG}
                ;;
              *)
                usage
                exit 1
                ;;
            esac
          done
          shift $((OPTIND-1))

          ${inputs'.nixos-anywhere.packages.nixos-anywhere}/bin/nixos-anywhere \
            --flake $flake \
            --disk-encryption-keys /tmp/host_key $host_key_file \
            --disk-encryption-keys /tmp/root_passphrase $root_passphrase_file \
            --disk-encryption-keys /tmp/data_passphrase $data_passphrase_file \
            --ssh-port $port \
            nixos@$ip \
            $extra_opts
        '';

        # SSH into a host installed
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
            $@
        '';
      };

      checks = import ./tests {
        inherit pkgs inputs system;
      };
    };

    flake = {
      lib = {
        # Create an ISO file with the beacon.
        #
        # This ISO file will need to be burned on a USB stick.
        # This can be done for example with usbimager that's
        # included in the template.
        #
        #   nix build .#beacon
        #
        beacon = system: skarabox-options: nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";

          modules = [
            self.nixosModules.beacon
            skarabox-options
          ];
        };

        # Create and Start a VM that boots the ISO file with the beacon.
        #
        # Useful for testing a full installation.
        # This VM comes with 3 disks, one under /dev/nvme0n1
        # and the two other under /dev/sda and /dev/sdb. This
        # setup imitates a real server with one SSD disk for
        # the OS and two HDDs in mirror for the data.
        #
        #   nix run .#beacon-vm [<host-port> [<host-boot-port>]]
        #
        #   host-port:        Host part of the port forwarding for the SSH server
        #                     when the VM is booted.
        #                     (default: 2222)
        #   host-boot-port:   Host port of the port forwarding for the SSH server
        #                     used to decrypt the root partition upon booting
        #                     or rebooting after the installation process is done.
        #                     (default: 2223)
        #
        beacon-vm = system: skarabox-options: let
          iso = nixos-generators.nixosGenerate {
            inherit system;
            format = "install-iso";

            modules = [
              self.nixosModules.beacon
              skarabox-options
              ({ lib, modulesPath, ... }: {
                imports = [
                  # This profile adds virtio drivers needed in the guest
                  # to be able to share the /nix/store folder.
                  (modulesPath + "/profiles/qemu-guest.nix")
                ];

                config.services.openssh.ports = lib.mkForce [ 2222 ];

                # Since this is the VM and we will mount the hosts' nix store,
                # we do not need to create a squashfs file.
                config.isoImage.storeContents = lib.mkForce [];

                # Share the host's nix store instead of the one created for the ISO.
                # config.lib.isoFileSystems is defined in nixos/modules/installer/cd-dvd/iso-image.nix
                config.lib.isoFileSystems = {
                  "/nix/.ro-store" = lib.mkForce {
                    device = "nix-store";
                    fsType = "9p";
                    neededForBoot = true;
                    options = [
                      "trans=virtio"
                      "version=9p2000.L"
                      "msize=16384"
                      "x-systemd.requires=modprobe@9pnet_virtio.service"
                      "cache=loose"
                    ];
                  };
                };
              })
            ];
          };
          nixos-qemu = pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
          qemu = nixos-qemu.qemuBinary pkgs.qemu;
        in (pkgs.writeShellScriptBin "beacon-vm.sh" ''
          disk1=.skarabox-tmp/disk1.qcow2
          disk2=.skarabox-tmp/disk2.qcow2
          disk3=.skarabox-tmp/disk3.qcow2

          mkdir -p .skarabox-tmp
          for d in $disk1 $disk2 $disk3; do
            [ ! -f $d ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 $d 20G
          done

          guestport=2222
          hostport=''${1:-2222}
          shift
          guestbootport=2223
          hostbootport=''${1:-2223}
          shift

          ${qemu} \
            -m 2048M \
            -device virtio-rng-pci \
            -net nic -net user,hostfwd=tcp::''${hostport}-:''${guestport},hostfwd=tcp::''${hostbootport}-:''${guestbootport} \
            --virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store \
            --drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware} \
            --drive media=cdrom,format=raw,readonly=on,file=${iso}/iso/beacon.iso \
            --drive format=qcow2,file=$disk1,if=none,id=nvm \
            --device nvme,serial=deadbeef,drive=nvm \
            --drive id=disk2,format=qcow2,if=none,file=$disk2 \
            --device ide-hd,drive=disk2 \
            --drive id=disk3,format=qcow2,if=none,file=$disk3 \
            --device ide-hd,drive=disk3 \
            $@
          '');
      };

      templates = {
        skarabox = {
          path = ./template;
          description = "Skarabox template";
        };

        default = self.templates.skarabox;
      };

      nixosModules.beacon = { config, lib, modulesPath, ... }: let
        cfg = config.skarabox;
      in {
        imports = [
          ./modules/beacon.nix
          (modulesPath + "/profiles/minimal.nix")
        ];

        options.skarabox = {
          sshPublicKey = lib.mkOption {
            type = lib.types.path;
            description = "Public key to connect to the beacon.";
          };
        };

        config = {
          boot.loader.systemd-boot.enable = true;

          # Do not let sshd generate host keys,
          # we will provide our own.
          # sshd will refuse to start if it finds no host key.
          # services.openssh.hostKeys = pkgs.lib.mkForce [];
          # environment.etc."ssh/ssh_host_ed25519_key" = {
          #   source = beaconHostKeyPriv;
          #   mode = "0600";
          # };

          # Set shared ssh key
          users.users."nixos" = {
            openssh.authorizedKeys.keyFiles = [ cfg.sshPublicKey ];
          };
        };
      };

      nixosModules.skarabox = {
        imports = [
          nixos-anywhere.inputs.disko.nixosModules.disko
          ./modules/disks.nix
          ./modules/configuration.nix
        ];
      };

      nix-ci = {
        cachix = {
          name = "selfhostblocks";
          public-key = "selfhostblocks.cachix.org-1:H5h6Uj188DObUJDbEbSAwc377uvcjSFOfpxyCFP7cVs=";
        };
      };
    };
  });
}
