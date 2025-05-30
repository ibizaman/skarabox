{
  config,
  lib,
  inputs,
  ...
}:
let
  topLevelConfig = config;
  cfg = config.skarabox;

  inherit (lib) concatMapAttrs mkOption types toInt;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if lib.isString vStr then toInt vStr else vStr;

  beacon-module = { config, lib, modulesPath, ... }: {
    imports = [
      ./modules/beacon.nix
      (modulesPath + "/profiles/minimal.nix")
    ];
  };
in
{
  options.skarabox = {
    sopsKeyName = mkOption {
      # Using string here so the sops key does not end up in the nix store.
      type = types.str;
      default = "sops.key";
    };

    hosts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          hostKeyName = mkOption {
            type = types.str;
            default = "host_key";
          };
          hostKeyPub = mkOption {
            type = types.path;
          };

          ip = mkOption {
            type = with types; oneOf [ str path ];
            default = "127.0.0.1";
            apply = readAsStr;
          };
          sshPrivateKeyName = mkOption {
            # Using string here so the sops key does not end up in the nix store.
            type = types.str;
            default = "ssh";
          };
          secretsFileName = mkOption {
            type = types.str;
            default = "secrets.yaml";
          };
          secretsRootPassphrasePath = mkOption {
            type = types.str;
            default = "['${name}']['disks']['rootPassphrase']";
          };
          secretsDataPassphrasePath = mkOption {
            type = types.str;
            default = "['${name}']['disks']['dataPassphrase']";
          };
          sshPublicKey = mkOption {
            type = types.path;
          };
          knownHostsName = mkOption {
            type = types.str;
            default = "known_hosts";
          };
          knownHosts = mkOption {
            type = types.path;
          };
          sshPort = mkOption {
            type = with types; oneOf [ int str path ];
            default = 22;
            apply = readAsInt;
          };
          sshBootPort = mkOption {
            type = with types; oneOf [ int str path ];
            default = 2222;
            apply = readAsInt;
          };
          system = mkOption {
            type = with types; oneOf [ str path ];
            apply = readAsStr;
          };

          modules = mkOption {
            type = types.listOf types.anything;
            default = [];
          };
        };
      }));
    };
  };

  config = {
    perSystem = { self', inputs', config, pkgs, system, ... }: let
      sops = pkgs.writeShellApplication {
        name = "sops";

        runtimeInputs = [
          pkgs.sops
        ];

        text = ''
          SOPS_AGE_KEY_FILE=${cfg.sopsKeyName} sops "$@"
        '';
      };

      mkHostPackages = name: cfg': let
        # nix run .#boot-ssh [<command> ...]
        # nix run .#boot-ssh
        # nix run .#boot-ssh echo hello
        boot-ssh = pkgs.writeShellApplication {
          name = "boot-ssh";

          runtimeInputs = [
            (import ./lib/ssh.nix {
              inherit pkgs;
            })
          ];

          text = ''
            ssh \
              "${cfg'.ip}" \
              "${toString cfg'.sshBootPort}" \
              root \
              -o UserKnownHostsFile=${cfg'.knownHosts} \
              -o ConnectTimeout=10 \
              -i ${name}/${cfg'.sshPrivateKeyName} \
              "$*"
          '';
        };

        # Create an ISO file with the beacon.
        #
        # This ISO file will need to be burned on a USB stick.
        # This can be done for example with usbimager that's
        # included in the template.
        beacon = inputs.nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";

          modules = [
            beacon-module
            {
              skarabox.sshPublicKey = cfg'.sshPublicKey;
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
          iso = inputs.nixos-generators.nixosGenerate {
            inherit system;
            format = "install-iso";

            modules = [
              beacon-module
              {
                skarabox.sshPublicKey = cfg'.sshPublicKey;
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
          diskRoot1=.skarabox-tmp/diskRoot1.qcow2
          diskRoot2=.skarabox-tmp/diskRoot2.qcow2
          diskData1=.skarabox-tmp/diskData1.qcow2
          diskData2=.skarabox-tmp/diskData2.qcow2

          mkdir -p .skarabox-tmp
          for d in $diskRoot1 $diskRoot2 $diskData1 $diskData2; do
            [ ! -f $d ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 $d 20G
          done

          set -x

          guestport=2222
          hostport=${toString cfg'.sshPort}
          guestbootport=2223
          hostbootport=${toString cfg'.sshBootPort}

          ${qemu} \
            -m 2048M \
            -device virtio-rng-pci \
            -net nic -net user,hostfwd=tcp::''${hostport}-:''${guestport},hostfwd=tcp::''${hostbootport}-:''${guestbootport} \
            --virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store \
            --drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware} \
            --drive media=cdrom,format=raw,readonly=on,file=${iso}/iso/beacon.iso \
            --drive format=qcow2,file=$diskRoot1,if=none,id=diskRoot1 \
            --device nvme,drive=diskRoot1,serial=nvme0 \
            --drive format=qcow2,file=$diskRoot2,if=none,id=diskRoot2 \
            --device nvme,drive=diskRoot2,serial=nvme1 \
            --drive id=diskData1,format=qcow2,if=none,file=$diskData1 \
            --device ide-hd,drive=diskData1,serial=sda \
            --drive id=diskData2,format=qcow2,if=none,file=$diskData2 \
            --device ide-hd,drive=diskData2,serial=sdb \
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
              (import ./lib/gen-knownhosts-file.nix {
                inherit pkgs;
              })
            ];

            text = ''
              ip=${cfg'.ip}
              ssh_port=${toString cfg'.sshPort}
              ssh_boot_port=${toString cfg'.sshBootPort}
              host_key_pub=${cfg'.hostKeyPub}

              gen-knownhosts-file \
                $host_key_pub "$ip" $ssh_port $ssh_boot_port \
                > ${name}/${cfg'.knownHostsName}
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
              (import ./lib/install-on-beacon.nix {
                inherit pkgs;
                inherit (inputs.nixos-anywhere.packages.${system}) nixos-anywhere;
              })
            ];
            text = ''
              ip=${toString cfg'.ip}
              ssh_port=${toString cfg'.sshPort}
              flake="$1"
              shift

              install-on-beacon \
                -i $ip \
                -p $ssh_port \
                -f "$flake" \
                -k ${name}/${cfg'.hostKeyName} \
                -s ${cfg.sopsKeyName} \
                -e ${name}/${cfg'.secretsFileName} \
                -r "${cfg'.secretsRootPassphrasePath}" \
                -d "${cfg'.secretsDataPassphrasePath}" \
                -a "--ssh-option ConnectTimeout=10 -i ${name}/${cfg'.sshPrivateKeyName} $*"
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
              (import ./lib/ssh.nix {
                inherit pkgs;
              })
            ];

            text = ''
              ssh \
                "${cfg'.ip}" \
                "${toString cfg'.sshPort}" \
                ${topLevelConfig.flake.nixosConfigurations.${name}.config.skarabox.username} \
                -o UserKnownHostsFile=${cfg'.knownHosts} \
                -o ConnectTimeout=10 \
                -i ${name}/${cfg'.sshPrivateKeyName} \
                "$@"
            '';
          };

          get-facter = pkgs.writeShellApplication {
            name = "get-facter";

            runtimeInputs = [
              ssh
            ];

            text = ''
              ssh -o StrictHostKeyChecking=no sudo nixos-facter
            '';
          };

          unlock = pkgs.writeShellApplication {
            name = "unlock";

            runtimeInputs = [
              sops
              boot-ssh
            ];

            text = ''
              root_passphrase="$(sops decrypt --extract "${cfg'.secretsRootPassphrasePath}" "${name}/${cfg'.secretsFileName}")"
              printf '%s' "$root_passphrase" | boot-ssh "$@"
            '';
          };
        in {
          "${name}-boot-ssh" = boot-ssh;
          "${name}-sops" = sops;
          "${name}-beacon" = beacon;
          "${name}-beacon-vm" = beacon-vm;
          "${name}-gen-knownhosts-file" = gen-knownhosts-file;
          "${name}-install-on-beacon" = install-on-beacon;
          "${name}-ssh" = ssh;
          "${name}-get-facter" = get-facter;
          "${name}-unlock" = unlock;
        };
    in {
      packages = let
        beacon-usbimager = pkgs.usbimager;

        add-sops-cfg = import ./lib/add-sops-cfg.nix {
          inherit pkgs;
        };

        sops-create-main-key = import ./lib/sops-create-main-key.nix {
          inherit pkgs;
        };

        sops-add-main-key = import ./lib/sops-add-main-key.nix {
          inherit pkgs add-sops-cfg;
        };

        gen-new-host = import ./lib/gen-new-host.nix {
          inherit add-sops-cfg pkgs;
        };
      in {
        inherit beacon-usbimager gen-new-host;
        inherit add-sops-cfg sops sops-add-main-key sops-create-main-key;
        inherit (pkgs) age;
      } // (concatMapAttrs mkHostPackages cfg.hosts);

      apps = {
        deploy-rs = inputs'.deploy-rs.apps.deploy-rs;
      };
    };

    flake = { pkgs, ... }: let
      mkFlake = name: cfg': {
        nixosConfigurations.${name} = inputs.nixpkgs.lib.nixosSystem {
          inherit (cfg') system;
          modules = cfg'.modules ++ [
            inputs.skarabox.nixosModules.skarabox
            {
              skarabox.system = cfg'.system;
            }
          ];
        };

        packages.${cfg'.system} = let
          nixosConfigurationConfig = topLevelConfig.flake.nixosConfigurations.${name}.config;
        in {
          ${name} = nixosConfigurationConfig.system.build.toplevel;
          "${name}-debug-facter-nvd" = nixosConfigurationConfig.facter.debug.nvd;
          "${name}-debug-facter-nix-diff" = nixosConfigurationConfig.facter.debug.nix-diff;
        };

        # Debug eval errors with `nix eval --json .#deploy --show-trace`
        deploy.nodes = let
          pkgs' = import inputs.nixpkgs {
            inherit (cfg') system;
          };
          # Use deploy-rs from nixpkgs to take advantage of the binary cache.
          # https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
          deployPkgs = import inputs.nixpkgs {
            inherit (cfg') system;
            overlays = [
              inputs.deploy-rs.overlay
              (self: super: {
                deploy-rs = {
                  inherit (pkgs') deploy-rs;
                  lib = super.deploy-rs.lib;
                };
              })
            ];
          };

          mkNode = name: cfg': {
            ${name} = {
              hostname = cfg'.ip;
              sshUser = topLevelConfig.flake.nixosConfigurations.${name}.config.skarabox.username;
              # What out, adding --ssh-opts on the command line will override these args.
              # For example, running `nix run .#deploy-rs -- -s --ssh-opts -v` will result in only the -v flag.
              sshOpts = [
                "-o" "IdentitiesOnly=yes"
                "-o" "UserKnownHostsFile=${cfg'.knownHosts}"
                "-o" "ConnectTimeout=10"
                "-i" "${name}/${cfg'.sshPrivateKeyName}"
                "-p" (toString cfg'.sshPort)
              ];
              profiles = {
                system = {
                  user = "root";
                  path = deployPkgs.deploy-rs.lib.activate.nixos topLevelConfig.flake.nixosConfigurations.${name};
                };
              };
            };
          };
        in
          concatMapAttrs mkNode cfg.hosts;
      };

      common = {
        nixosModules.beacon = beacon-module;

        # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
        checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks topLevelConfig.flake.deploy) inputs.deploy-rs.lib;
      };
    in
      common // (concatMapAttrs mkFlake cfg.hosts);
  };
}
