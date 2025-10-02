{
  config,
  lib,
  inputs,
  ...
}:
let
  topLevelConfig = config;
  cfg = config.skarabox;

  inherit (lib) concatMapAttrs concatStringsSep mapAttrsToList mkOption optionalAttrs types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;

  beacon-module = { config, lib, modulesPath, ... }: {
    imports = [
      ../modules/beacon.nix
      (modulesPath + "/profiles/minimal.nix")
    ];
  };

  skaraboxLib = import ../lib/functions.nix;
in
{
  options.skarabox = {
    sopsKeyPath = mkOption {
      description = "Path from the top of the repo to the main sops key.";
      # Using string here so the sops key does not end up in the nix store.
      type = types.str;
      default = "sops.key";
    };

    hosts = mkOption {
      description = "Hosts managed by Skarabox.";
      default = {};
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          nixpkgs = mkOption {
            type = types.anything;
            defaultText = "inputs.nixpkgs";
            default = inputs.nixpkgs;
            description = ''
              If given, overrides nixpkgs in the nixosConfiguration, including `lib` and `nixos/modules/`.

              By default, uses the default nixpkgs input.

              This option allows to patch nixpkgs following https://wiki.nixos.org/wiki/Nixpkgs/Patching_Nixpkgs
            '';
          };
          hostKeyPath = mkOption {
            description = "Path from the top of the repo to the ssh private file used as the host key.";
            type = types.str;
            default = "${name}/host_key";
          };
          hostKeyPub = mkOption {
            description = "SSH public file used as the host key.";
            type = with types; oneOf [ str path ];
            apply = readAsStr;
            example = lib.literalExpression "./${name}/host_key.pub";
          };
          ip = mkOption {
            description = ''
              IP or hostname used to ssh into the server.

              Can be the IP or hostname directly or a file containing the value.
            '';
            type = with types; oneOf [ str path ];
            default = "127.0.0.1";
            apply = readAsStr;
          };
          sshPrivateKeyPath = mkOption {
            description = "Path from the top of the repo to the ssh private file used to ssh into the host. Set to null if you use an ssh agent.";
            type = types.nullOr types.str;
            default = "${name}/ssh";
          };
          sshAuthorizedKey = mkOption {
            description = "SSH public file used to ssh into the host.";
            type = with types; oneOf [ str path ];
            apply = readAsStr;
          };
          secretsFilePath = mkOption {
            description = ''
              Path from the top of the repo to the SOPS secrets file.

              By default Skarabox assumes one secret file per host to avoid
              sharing secrets across them but having only one file by specifying
              "./secrets.yaml" is possible too.
            '';
            type = types.str;
            default = "${name}/secrets.yaml";
          };
          secretsRootPassphrasePath = mkOption {
            description = "Path in python dictionary format to the passphrase of the root ZFS pool as it is stored in the SOPS secrets file.";
            type = types.str;
            default = "['${name}']['disks']['rootPassphrase']";
          };
          secretsDataPassphrasePath = mkOption {
            description = "Path in python dictionary format to the passphrase of the data ZFS pool as it is stored in the SOPS secrets file.";
            type = types.str;
            default = "['${name}']['disks']['dataPassphrase']";
          };
          extraSecretsPassphrasesPath = mkOption {
            description = "Paths in python dictionary format to other passphrases for extra ZFS pools as they is stored in the SOPS secrets file.";
            type = with types; attrsOf str;
            default = {};
            example = lib.literalExpression ''
              {
                backup_passphrase = "['${name}']['disks']['backupPassphrase']";
              }
            '';
          };
          knownHostsPath = mkOption {
            description = "Path from the top of the repo to known hosts file.";
            type = types.str;
            default = "${name}/known_hosts";
          };
          knownHosts = mkOption {
            description = "Known hosts file.";
            type = types.path;
          };
          system = mkOption {
            description = ''
              System of the host.

              Can be the systm directly or a file containing the value.
            '';
            type = with types; oneOf [ str path ];
            apply = readAsStr;
          };

          modules = mkOption {
            description = "Modules to add to the host nixosConfiguration. Add here all your own configuration.";
            type = types.listOf types.anything;
            default = [];
          };
          extraBeaconModules = mkOption {
            description = "Modules to add to the beacon configuration. Use this to add static network config, for example.";
            type = types.listOf types.anything;
            default = [];
            example = ''
              extraBeaconModules = [
                {
                  environment.systemPackages = [ pkgs.tmux ];
                }
              ];
            '';
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
          SOPS_AGE_KEY_FILE=${cfg.sopsKeyPath} sops "$@"
        '';
      };

      mkHostPackages = name: cfg': let
        hostCfg = topLevelConfig.flake.nixosConfigurations.${name}.config;

        # nix run .#boot-ssh [<command> ...]
        # nix run .#boot-ssh
        # nix run .#boot-ssh echo hello
        boot-ssh = pkgs.writeShellApplication {
          name = "boot-ssh";

          runtimeInputs = [
            (import ../lib/ssh.nix {
              inherit pkgs;
            })
          ];

          text = ''
            ssh \
              "${cfg'.ip}" \
              "${toString hostCfg.skarabox.boot.sshPort}" \
              root \
              -o UserKnownHostsFile=${cfg'.knownHosts} \
              -o ConnectTimeout=10 \
              ${if cfg'.sshPrivateKeyPath != null then "-i ${cfg'.sshPrivateKeyPath}" else ""} \
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

          modules = cfg'.extraBeaconModules ++ [
            beacon-module
            {
              skarabox.username = hostCfg.skarabox.username;
              skarabox.hostname = "${hostCfg.skarabox.hostname}-beacon";
              skarabox.sshAuthorizedKey = cfg'.sshAuthorizedKey;
              skarabox.ip = cfg'.ip;
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
          # About bootindex. On first boot, the nvme* drives cannot boot
          # so we will instead boot on the cdrom. After a successful installation,
          # we will be able to boot on the nvme* drives instead.
          script = targetSystem: (let
            targetPkgs = import inputs.nixpkgs { system = targetSystem; };

            iso = inputs.nixos-generators.nixosGenerate {
              system = targetSystem;
              format = "install-iso";

              modules = [
                beacon-module
                {
                  skarabox.sshAuthorizedKey = cfg'.sshAuthorizedKey;
                  skarabox.ip = "127.0.0.1";
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
            nixos-qemu = targetPkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
            qemu = nixos-qemu.qemuBinary pkgs.qemu;
          in pkgs.writeShellScriptBin "beacon-vm" ''
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
            hostport=${toString hostCfg.skarabox.sshPort}
            guestbootport=2223
            hostbootport=${toString hostCfg.skarabox.boot.sshPort}

            ${qemu} \
              -m 2048M \
              -device virtio-rng-pci \
              -net nic -net user,hostfwd=tcp::''${hostport}-:''${guestport},hostfwd=tcp::''${hostbootport}-:''${guestbootport} \
              --virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store \
              --drive if=pflash,format=raw,unit=0,readonly=on,file=${targetPkgs.OVMF.firmware} \
              --drive media=cdrom,format=raw,readonly=on,file=${iso}/iso/beacon.iso \
              --drive format=qcow2,file=$diskRoot1,if=none,id=diskRoot1 \
              --device nvme,drive=diskRoot1,serial=nvme0,bootindex=1 \
              --drive format=qcow2,file=$diskRoot2,if=none,id=diskRoot2 \
              --device nvme,drive=diskRoot2,serial=nvme1,bootindex=2 \
              --drive id=diskData1,format=qcow2,if=none,file=$diskData1 \
              --device ide-hd,drive=diskData1,serial=sda \
              --drive id=diskData2,format=qcow2,if=none,file=$diskData2 \
              --device ide-hd,drive=diskData2,serial=sdb \
              $@
            '');
          in
            script (if system == "x86_64-darwin" then "x86_64-linux"
                    else if system == "aarch64-darwin" then "aarch64-linux"
                    else system);

          # Generate knownhosts file.
          #
          # gen-knownhosts-file <pub_key> <ip> <port> [<port>...]
          #
          # One line will be generated per port given.
          gen-knownhosts-file = pkgs.writeShellApplication {
            name = "gen-knownhosts-file";

            runtimeInputs = [
              (import ../lib/gen-knownhosts-file.nix {
                inherit pkgs;
              })
            ];

            text = ''
              ip=${cfg'.ip}
              ssh_port=${toString hostCfg.skarabox.sshPort}
              ssh_boot_port=${toString hostCfg.skarabox.boot.sshPort}
              host_key_pub="${cfg'.hostKeyPub}"

              gen-knownhosts-file \
                "$host_key_pub" "$ip" $ssh_port $ssh_boot_port \
                > ${cfg'.knownHostsPath}
            '';
          };

          # Install a nixosConfigurations instance (<flake>) on a server.
          #
          # This command is intended to be run against a server which
          # was booted on the beacon. Although, the server could be booted
          # on any OS supported by nixos-anywhere. The latter has not been
          # tested in the context of Skarabox.
          #
          #   nix run .#install-on-beacon [<command> ...]
          #   nix run .#install-on-beacon
          #   nix run .#install-on-beacon -v
          install-on-beacon = pkgs.writeShellApplication {
            name = "install-on-beacon";
            runtimeInputs = [
              (import ../lib/install-on-beacon.nix {
                inherit pkgs;
                inherit (inputs.nixos-anywhere.packages.${system}) nixos-anywhere;
              })
              pkgs.sops
            ];
            text = let
              secrets =
                {
                  "root_passphrase" = cfg'.secretsRootPassphrasePath;
                }
                // (optionalAttrs hostCfg.skarabox.disks.dataPool.enable {
                  "data_passphrase" = cfg'.secretsDataPassphrasePath;
                })
                // cfg'.extraSecretsPassphrasesPath;

              diskEncryptionOptions = let
                mkOption = name: path: ''--disk-encryption-keys /tmp/${name} "<(echo "''$${name}")" '';
              in
                mapAttrsToList mkOption secrets;

              diskEncryptionVars = let
                mkVar = name: path: ''${name}="$(sops decrypt --extract "${path}" "${cfg'.secretsFilePath}")"'';

              in
                mapAttrsToList mkVar secrets;
            in ''
              ip=${toString cfg'.ip}
              ssh_port=${toString hostCfg.skarabox.sshPort}
              flake=".#${toString name}"

              export SOPS_AGE_KEY_FILE="${cfg.sopsKeyPath}"

              ''
            + concatStringsSep "\n" diskEncryptionVars
            + ''

              install-on-beacon \
                -i $ip \
                -u ${hostCfg.skarabox.username} \
                -p $ssh_port \
                -f "$flake" \
                -k ${cfg'.hostKeyPath} \
                -a "--ssh-option ConnectTimeout=10 ${if cfg'.sshPrivateKeyPath != null then "-i ${cfg'.sshPrivateKeyPath}" else ""} ${concatStringsSep " " diskEncryptionOptions} $*"
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
              (import ../lib/ssh.nix {
                inherit pkgs;
              })
            ];

            text = ''
              ssh \
                "${cfg'.ip}" \
                "${toString hostCfg.skarabox.sshPort}" \
                ${topLevelConfig.flake.nixosConfigurations.${name}.config.skarabox.username} \
                -o UserKnownHostsFile=${cfg'.knownHosts} \
                -o ConnectTimeout=10 \
                ${if cfg'.sshPrivateKeyPath != null then "-i ${cfg'.sshPrivateKeyPath}" else ""} \
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
              root_passphrase="$(sops decrypt --extract "${cfg'.secretsRootPassphrasePath}" "${cfg'.secretsFilePath}")"
              printf '%s' "$root_passphrase" | boot-ssh -T "$@"
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
      packages = {
        beacon-usbimager = pkgs.usbimager;
        inherit sops;
        inherit (pkgs) age;
        inherit (inputs'.skarabox.packages) gen-hostId gen-new-host manualHtml add-sops-cfg sops-add-main-key sops-create-main-key;
      } // (concatMapAttrs mkHostPackages cfg.hosts);
    };

    flake = flakeInputs: let
      mkFlake = name: cfg': {
        nixosConfigurations.${name} = skaraboxLib.nixosSystem cfg'.nixpkgs {
          inherit (cfg') system;
          modules = cfg'.modules ++ [
            inputs.skarabox.nixosModules.skarabox
            {
              nixpkgs.hostPlatform = cfg'.system;
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
      };

      common = {
        nixosModules.beacon = beacon-module;
      };
    in
      common // (concatMapAttrs mkFlake cfg.hosts);
  };
}
