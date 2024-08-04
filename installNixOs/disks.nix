{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox.disks;

  rootPool = "root";
  dataPool = "zdata";
in
{
  options.skarabox.disks = {
    rootDisk = lib.mkOption {
      type = lib.types.str;
      description = "SSD disk on which to install.";
      example = "/dev/nvme0n1";
    };

    rootReservation = lib.mkOption {
      type = lib.types.str;
      description = ''
        Disk size to reserve for ZFS internals. Should be between 10% and 15% of available size as recorded by zpool.

        To get available size on zpool:

           zfs get -Hpo value available ${rootPool}

        Then to set manually, if needed:

           sudo zfs set reservation=100G ${rootPool}
      '';
      example = "100G";
    };

    dataDisk1 = lib.mkOption {
      type = lib.types.str;
      description = "First disk on which to install the data pool.";
      example = "/dev/sda";
    };

    dataDisk2 = lib.mkOption {
      type = lib.types.str;
      description = "Second disk on which to install the data pool.";
      example = "/dev/sdb";
    };

    dataReservation = lib.mkOption {
      type = lib.types.str;
      description = ''
        Disk size to reserve for ZFS internals. Should be between 5% and 10% of available size as recorded by zpool.

        To get available size on zpool:

           zfs get -Hpo value available ${dataPool}

        Then to set manually, if needed:

           sudo zfs set reservation=100G ${dataPool}
      '';
      example = "1T";
    };
  };

  config = {
    disko.devices = {
      disk = {
        root = {
          type = "disk";
          device = cfg.rootDisk;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "128M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  # Otherwise you get https://discourse.nixos.org/t/security-warning-when-installing-nixos-23-11/37636/2
                  mountOptions = [ "umask=0077" ];
                  # Copy the host_key needed for initrd in a location accessible on boot.
                  # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
                  postMountHook = ''
                    cp /etc/ssh/ssh_host_ed25519_key /mnt/boot/host_key
                  '';
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = rootPool;
                };
              };
            };
          };
        };
        data1 = {
          type = "disk";
          device = cfg.dataDisk1;
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = dataPool;
                };
              };
            };
          };
        };
        data2 = {
          type = "disk";
          device = cfg.dataDisk2;
          content = {
            type = "gpt";
            partitions = {
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = dataPool;
                };
              };
            };
          };
        };
      };
      zpool = {
        ${rootPool} = {
          type = "zpool";
          # Only one disk
          mode = "";
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
          # Needed to get back a prompt on next boot.
          # See https://github.com/nix-community/nixos-anywhere/issues/161#issuecomment-1642158475
          postCreateHook = ''
            zfs set keylocation="prompt" $name
          '';

          # Follows https://grahamc.com/blog/erase-your-darlings/
          datasets = {
            # TODO: compute percentage automatically in postCreateHook
            "reserved" = {
              options = {
                canmount = "off";
                mountpoint = "none";
                # TODO: compute this value using percentage
                reservation = cfg.rootReservation;
              };
              type = "zfs_fs";
            };

            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^${rootPool}/local/root@blank$' || zfs snapshot ${rootPool}/local/root@blank";
            };

            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
            };

            "safe/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
            };

            "safe/persist" = {
              type = "zfs_fs";
              mountpoint = "/persist";
              # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
              postMountHook = ''
                cp /tmp/data_passphrase /mnt/persist/data_passphrase
              '';
            };
          };
        };

        ${dataPool} = {
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
          };
          postCreateHook = ''
            zfs set keylocation="file:///persist/data_passphrase" $name;
          '';
          datasets = {
            # TODO: create reserved dataset automatically in postCreateHook
            "reserved" = {
              options = {
                canmount = "off";
                mountpoint = "none";
                # TODO: compute this value using percentage
                reservation = cfg.dataReservation;
              };
              type = "zfs_fs";
            };
            "backup" = {
              type = "zfs_fs";
              mountpoint = "/srv/backup";
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

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    # Otherwise the zpool needs to be imported manually.
    boot.zfs.extraPools = [ dataPool ];

    # Follows https://grahamc.com/blog/erase-your-darlings/
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      zfs rollback -r ${rootPool}/local/root@blank
    '';

    # From https://nixos.wiki/wiki/ZFS#Remote_unlock
    boot.initrd.network = {
      # This will use udhcp to get an ip address. Make sure you have added the kernel module for your
      # network driver to `boot.initrd.availableKernelModules`, so your initrd can load it! Static ip
      # addresses might be configured using the ip argument in kernel command line:
      # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
      enable = true;
      ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used, a different
        # port for ssh is used.
        port = lib.mkDefault 2222;
        hostKeys = [ "/boot/host_key" ];
        # public ssh key used for login
        authorizedKeys = [ (builtins.readFile config.skarabox.sshAuthorizedKeyFile) ];
      };

      postCommands = ''
      zpool import -a
      echo "zfs load-key ${rootPool}; killall zfs; exit" >> /root/.profile
      '';
    };

    services.zfs.autoScrub.enable = true;
  };
}
