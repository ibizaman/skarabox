{ config, options, lib, ... }:
let
  cfg = config.skarabox.disks;
  opt = options.skarabox.disks;

  inherit (lib) mkIf mkOption optionals optionalString toInt types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if lib.isString vStr then toInt vStr else vStr;
in
{
  options.skarabox.disks = {
    rootPool = mkOption {
      type = with types; submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name of the root pool";
            default = "root";
          };

          disk1 = mkOption {
            type = types.str;
            description = "SSD disk on which to install. Required";
            example = "/dev/nvme0n1";
          };

          disk2 = mkOption {
            type = types.nullOr types.str;
            description = "Second SSD disk on which to install. Optional.";
            example = "/dev/nvme0n2";
            default = null;
          };

          reservation = mkOption {
            type = types.str;
            description = ''
              Disk size to reserve for ZFS internals. Should be between 10% and 15% of available size as recorded by zpool.

              To get available size on zpool:

                 zfs get -Hpo value available ${opt.rootPool.name}

              Then to set manually, if needed:

                 sudo zfs set reservation=100G ${opt.rootPool.name}
            '';
            example = "100G";
          };
        };
      };
    };

    dataPool = mkOption {
      type = with types; submodule {
        options = {
          enable = lib.mkEnableOption "the data pool on other hard drives." // {
            default = true;
          };

          name = mkOption {
            type = types.str;
            description = "Name of the data pool";
            default = "zdata";
          };

          disk1 = mkOption {
            type = types.str;
            description = "First disk on which to install the data pool.";
            example = "/dev/sda";
          };

          disk2 = mkOption {
            type = types.str;
            description = "Second disk on which to install the data pool.";
            example = "/dev/sdb";
          };

          reservation = mkOption {
            type = types.str;
            description = ''
              Disk size to reserve for ZFS internals. Should be between 5% and 10% of available size as recorded by zpool.

              To get available size on zpool:

                 zfs get -Hpo value available ${opt.dataPool.name}

              Then to set manually, if needed:

                 sudo zfs set reservation=100G ${opt.dataPool.name}
            '';
            example = "1T";
          };
        };
      };
    };

    initialBackupDataset = mkOption {
      type = types.bool;
      description = "Create the backup dataset.";
      default = true;
    };

    bootSSHPort = mkOption {
      type = with types; oneOf [ int str path ];
      description = "Port the SSH daemon used to decrypt the root partition listens to.";
      default = 2222;
      apply = readAsInt;
    };
  };

  config = {
    disko.devices = {
      disk = let
        hasRaid = cfg.rootPool.disk2 != null;

        rootSoleContent = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          # Otherwise you get https://discourse.nixos.org/t/security-warning-when-installing-nixos-23-11/37636/2
          mountOptions = [ "umask=0077" ];
          # Copy the host_key needed for initrd in a location accessible on boot.
          # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
          # We're using the same host key because, well, it's the same host!
          postMountHook = ''
            cp /tmp/host_key /mnt/boot/host_key
          '';
        };
        rootRaidContent = {
          type = "mdraid";
          name = "boot";
        };
        mkRoot = rootDisk: {
          type = "disk";
          device = rootDisk;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "500M";
                type = "EF00";
                content = if hasRaid then rootRaidContent else rootSoleContent;
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = cfg.rootPool.name;
                };
              };
            };
          };
        };

        mkDataDisk = dataDisk: {
          type = "disk";
          device = dataDisk;
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = cfg.dataPool.name;
                };
              };
            };
          };
        };
      in {
        root = mkRoot cfg.rootPool.disk1;
        root1 = mkIf hasRaid (mkRoot cfg.rootPool.disk2);
        data1 = mkIf cfg.dataPool.enable (mkDataDisk cfg.dataPool.disk1);
        data2 = mkIf cfg.dataPool.enable (mkDataDisk cfg.dataPool.disk2);
      };
      mdadm = {
        boot = mkIf (cfg.rootPool.disk2 != null) {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
            # Copy the host_key needed for initrd in a location accessible on boot.
            # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
            postMountHook = ''
              cp /tmp/host_key /mnt/boot/host_key
            '';
          };
        };
      };
      zpool = {
        ${cfg.rootPool.name} = {
          type = "zpool";
          mode = if cfg.rootPool.disk2 != null then "mirror" else "";
          options = {
            ashift = "12";
            autotrim = "on";
          };
          rootFsOptions = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///tmp/root_passphrase";
            compression = "lz4";
            canmount = "off";
            xattr = "sa";
            atime = "off";
            acltype = "posixacl";
            recordsize = "1M";
            "com.sun:auto-snapshot" = "false";
          };
          # Need to use another variable name otherwise I get SC2030 and SC2031 errors.
          preCreateHook = ''
            pname=$name
          '';
          # Needed to get back a prompt on next boot.
          # See https://github.com/nix-community/nixos-anywhere/issues/161#issuecomment-1642158475
          postCreateHook = ''
            zfs set keylocation="prompt" $pname
          '';

          # Follows https://grahamc.com/blog/erase-your-darlings/
          datasets = {
            # TODO: compute percentage automatically in postCreateHook
            "reserved" = {
              options = {
                canmount = "off";
                mountpoint = "none";
                # TODO: compute this value using percentage
                reservation = cfg.rootPool.reservation;
              };
              type = "zfs_fs";
            };

            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options.mountpoint = "legacy";
              postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^${cfg.rootPool.name}/local/root@blank$' || zfs snapshot ${cfg.rootPool.name}/local/root@blank";
            };

            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options.mountpoint = "legacy";
            };

            "safe/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options.mountpoint = "legacy";
            };

            "safe/persist" = {
              type = "zfs_fs";
              mountpoint = "/persist";
              # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
              options.mountpoint = "legacy";
              postMountHook = optionalString cfg.dataPool.enable ''
                cp /tmp/data_passphrase /mnt/persist/data_passphrase
              '';
            };
          };
        };

        ${cfg.dataPool.name} = mkIf cfg.dataPool.enable {
          type = "zpool";
          mode = "mirror";
          options = {
            ashift = "12";
            autotrim = "on";
          };
          rootFsOptions = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///tmp/data_passphrase";
            compression = "lz4";
            canmount = "off";
            xattr = "sa";
            atime = "off";
            acltype = "posixacl";
            recordsize = "1M";
            "com.sun:auto-snapshot" = "false";
            mountpoint = "none";
          };
          # Need to use another variable name otherwise I get SC2030 and SC2031 errors.
          preCreateHook = ''
            pname=$name
          '';
          postCreateHook = ''
            zfs set keylocation="file:///persist/data_passphrase" $pname;
          '';
          datasets = {
            # TODO: create reserved dataset automatically in postCreateHook
            "reserved" = {
              options = {
                canmount = "off";
                mountpoint = "none";
                # TODO: compute this value using percentage
                reservation = cfg.dataPool.reservation;
              };
              type = "zfs_fs";
            };
          } // lib.optionalAttrs cfg.initialBackupDataset {
            "backup" = {
              type = "zfs_fs";
              mountpoint = "/srv/backup";
              options.mountpoint = "legacy";
            };
            # TODO: create datasets automatically upon service installation (e.g. Nextcloud, etc.)
            #"nextcloud" = {
            #  type = "zfs_fs";
            #  mountpoint = "/srv/nextcloud";
            #};
          };
        };
      };
    };
    fileSystems."/srv/backup" = mkIf (cfg.dataPool.enable && cfg.initialBackupDataset) {
      options = [ "nofail" ];
    };

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    # To import the zpool automatically
    boot.zfs.extraPools = optionals cfg.dataPool.enable [ cfg.dataPool.name ];

    # This is needed to make the /boot/host_key available early
    # enough to be able to decrypt the sops file on boot,
    # when the /etc/shadow file is first generated.
    fileSystems."/boot".neededForBoot = true;

    # Follows https://grahamc.com/blog/erase-your-darlings/
    # https://github.com/NixOS/nixpkgs/pull/346247/files
    boot.initrd.postResumeCommands = lib.mkAfter ''
      zfs rollback -r ${cfg.rootPool.name}/local/root@blank
    '';

    # Enables DHCP in stage-1 even if networking.useDHCP is false.
    boot.initrd.network.udhcpc.enable = lib.mkDefault true;
    # From https://wiki.nixos.org/wiki/ZFS#Remote_unlock
    boot.initrd.network = {
      # This will use udhcp to get an ip address. Nixos-facter should have found the correct drivers
      # to load but in case not, they need to be added to `boot.initrd.availableKernelModules`.
      # Static ip addresses might be configured using the ip argument in kernel command line:
      # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
      enable = true;
      ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used,
        # a different port for ssh is used.
        port = lib.mkDefault cfg.bootSSHPort;
        hostKeys = lib.mkForce [ "/boot/host_key" ];
        # Public ssh key used for login.
        # This should contain just one line and removing the trailing
        # newline could be fixed with a removeSuffix call but treating
        # it as a file containing multiple lines makes this forward compatible.
        authorizedKeyFiles = [
          config.skarabox.sshAuthorizedKeyFile
        ];
      };

      postCommands = ''
      zpool import -a
      echo "zfs load-key ${cfg.rootPool.name}; killall zfs; exit" >> /root/.profile
      '';
    };

    services.zfs.autoScrub.enable = true;
  };
}
