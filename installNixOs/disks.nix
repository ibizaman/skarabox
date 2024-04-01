{ config, lib, ... }:
let
  cfg = config.skarabox.disks;
in
{
  options.skarabox.disks = {
    rootReservation = lib.mkOption {
      type = lib.types.str;
      description = "Disk size to reserve for ZFS internals. Should be between 10% and 20% of available size as recorded by zpool.";
      example = "100G";
    };
  };

  config = {
    disko.devices = {
      disk = {
        x = {
          type = "disk";
          device = "/dev/nvme0n1";
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
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
              };
            };
          };
        };
      };
      zpool = {
        zroot = {
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
            keylocation = "file:///tmp/disk.key";
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
            zfs set keylocation="prompt" $name;
          '';

          # Follows https://grahamc.com/blog/erase-your-darlings/
          datasets = {
            "reserved" = {
              options = {
                canmount = "off";
                mountpoint = "none";
                # TODO: compute this value using percentage
                # Example to get available on zpool:
                #   zfs get -Hpo value available zroot
                # Then to set:
                #   sudo zfs set reservation=100G zroot
                reservation = cfg.rootReservation;
              };
              type = "zfs_fs";
            };

            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/local/root@blank$' || zfs snapshot zroot/local/root@blank";
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
            };
          };
        };
      };
    };

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    # Follows https://grahamc.com/blog/erase-your-darlings/
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      zfs rollback -r zroot/local/root@blank
    '';

    services.zfs.autoScrub.enable = true;
  };
}
