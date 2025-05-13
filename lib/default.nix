# The returned attrset is directly used by the user.
# Any non-backwards compatible change must be considered
# a breaking change.
inputs@{
  deploy-rs,
  nixpkgs,
  nixos-anywhere,
  nixos-generators,
  sops-nix,
  self,
}:
{
  hostKeyPub,
  ip,
  sopsKeyName,
  knownHostsName,
  knownHosts,
  sshBootPort,
  sshPort,
  sshPrivateKeyName,
  sshPublicKey,
  nixosConfiguration,

  patches ? fetchPatch: [],
  overlays ? [],
}:
let
  readFile = path: nixpkgs.lib.trim (builtins.readFile path);

  patchedNixpkgs = system: nixpkgs.legacyPackages.${system}.applyPatches {
    name = "nixpkgs-patched";
    src = nixpkgs;
    patches = patches {
      inherit (nixpkgs.lib) fetchPatch;
    };
  };
in
{
  inherit readFile;

  withSystem = { system }: let
    pkgs = import (patchedNixpkgs system) {
      inherit system;
      inherit overlays;
    };
  in {
    packages = let
      sops = pkgs.writeShellApplication {
        name = "sops";

        runtimeInputs = [
          pkgs.sops
        ];

        text = ''
          SOPS_AGE_KEY_FILE=${sopsKeyName} sops "$@"
        '';
      };

      # nix run .#boot-ssh [<command> ...]
      # nix run .#boot-ssh
      # nix run .#boot-ssh echo hello
      boot-ssh = pkgs.writeShellApplication {
        name = "boot-ssh";

        runtimeInputs = [
          (import ./ssh.nix {
            inherit pkgs;
          })
        ];

        text = ''
          ssh \
            "${readFile ip}" \
            "${readFile sshBootPort}" \
            root \
            -o UserKnownHostsFile=${knownHosts} \
            -o ConnectTimeout=10 \
            -i ssh_skarabox \
            "$*"
        '';
      };
    in {
      inherit boot-ssh sops;

      # Create an ISO file with the beacon.
      #
      # This ISO file will need to be burned on a USB stick.
      # This can be done for example with usbimager that's
      # included in the template.
      #
      #   nix build .#beacon
      #
      beacon = nixos-generators.nixosGenerate {
        inherit system;
        format = "install-iso";

        modules = [
          self.nixosModules.beacon
          {
            skarabox.sshPublicKey = sshPublicKey;
          }
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
      beacon-vm = let
        iso = nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";

          modules = [
            self.nixosModules.beacon
            {
              skarabox.sshPublicKey = sshPublicKey;
            }
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
      in (pkgs.writeShellScriptBin "beacon-vm" ''
        disk1=.skarabox-tmp/disk1.qcow2
        disk2=.skarabox-tmp/disk2.qcow2
        disk3=.skarabox-tmp/disk3.qcow2

        mkdir -p .skarabox-tmp
        for d in $disk1 $disk2 $disk3; do
          [ ! -f $d ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 $d 20G
        done

        guestport=2222
        hostport=${readFile sshPort}
        guestbootport=2223
        hostbootport=${readFile sshBootPort}

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

      # Generate knownhosts file.
      #
      # gen-knownhosts-file <pub_key> <ip> <port> [<port>...]
      #
      # One line will be generated per port given.
      gen-knownhosts-file = pkgs.writeShellApplication {
        name = "gen-knownhosts-file";

        runtimeInputs = [
          (import ./genknownhostsfile.nix {
            inherit pkgs;
          })
        ];

        text = ''
          ip=${readFile ip}
          ssh_port=${readFile sshPort}
          ssh_boot_port=${readFile sshBootPort}
          host_key_pub=${hostKeyPub}

          gen-knownhosts-file \
            $host_key_pub $ip $ssh_port $ssh_boot_port \
            > ${knownHostsName}
        '';
      };

      # Install a nixosConfigurations instance (<flake>) on a server.
      #
      # This command is intended to be run against a server which
      # was booted on the beacon. Although, the server could be booted
      # on any OS supported by nixos-anywhere. The latter was not tested.
      # nix run .#install-on-beacon FLAKE [<command> ...]
      # nix run .#install-on-beacon
      # nix run .#install-on-beacon .#skarabox
      # nix run .#install-on-beacon .#skarabox -v
      install-on-beacon = pkgs.writeShellApplication {
        name = "install-on-beacon";
        runtimeInputs = [
          (import ./installonbeacon.nix {
            inherit pkgs;
            inherit (nixos-anywhere.packages.${system}) nixos-anywhere;
          })
        ];
        text = ''
          ip=${readFile ip}
          ssh_port=${readFile sshPort}
          flake="$1"
          shift

          install-on-beacon \
            -i $ip \
            -p $ssh_port \
            -f "$flake" \
            -k host_key \
            -s sops.key \
            -r .skarabox.disks.rootPassphrase \
            -d .skarabox.disks.dataPassphrase \
            -a "--ssh-option ConnectTimeout=10 -i ssh_skarabox $*"
        '';
      };

      # nix run .#ssh [<command> ...]
      # nix run .#ssh
      # nix run .#ssh echo hello
      #
      # Note: the private SSH key is not read into the nix store on purpose.
      ssh = pkgs.writeShellApplication {
        name = "ssh";

        runtimeInputs = [
          (import ./ssh.nix {
            inherit pkgs;
          })
        ];

        text = ''
          ssh \
            "${readFile ip}" \
            "${readFile sshPort}" \
            ${nixosConfiguration.config.skarabox.username} \
            -o UserKnownHostsFile=${knownHosts} \
            -o ConnectTimeout=10 \
            -i ssh_skarabox \
            "$@"
        '';
      };

      unlock = pkgs.writeShellApplication {
        name = "unlock";

        runtimeInputs = [
          sops
          pkgs.yq-go
          boot-ssh
        ];

        text = ''
          root_passphrase="$(sops exec-file secrets.yaml "cat {} | yq -r .skarabox.disks.rootPassphrase")"
          printf '%s' "$root_passphrase" | boot-ssh "$@"
        '';
      };
    };

    # Can't use .deploy as the name here
    # otherwise it overrides the .#deploy flake output
    # that deploy-rs needs.
    #
    # For info, deploy-rs runs `nix eval --json .#deploy`
    # https://github.com/serokell/deploy-rs/blob/aa07eb05537d4cd025e2310397a6adcedfe72c76/src/cli.rs#L202
    deploy-rs.packages.activate = inputs.deploy-rs.packages.${system}.deploy-rs;

    deploy-rs.node = let
      # Taken from https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
      deployPkgs = import nixpkgs {
        inherit system;
        overlays = [
          inputs.deploy-rs.overlay
          (self: super: {
            deploy-rs = {
              inherit (pkgs) deploy-rs;
              lib = super.deploy-rs.lib;
            };
          })
        ];
      };
    in {
      hostname = readFile ip;
      sshUser = nixosConfiguration.config.skarabox.username;
      sshOpts = [
        "-o" "IdentitiesOnly=yes"
        "-o" "UserKnownHostsFile=${knownHosts}"
        "-o" "ConnectTimeout=10"
        "-i" sshPrivateKeyName
        "-p" (readFile sshPort)
      ];
      profiles = {
        system = {
          user = "root";
          path = deployPkgs.deploy-rs.lib.activate.nixos nixosConfiguration;
        };
      };
    };
  };

  # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
  deploy-rs = {
    checks = nodesRoot: builtins.mapAttrs (system: deployLib: deployLib.deployChecks nodesRoot) inputs.deploy-rs.lib;
  };
}
