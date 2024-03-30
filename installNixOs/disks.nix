{ lib, ... }:
{
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
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot@blank$' || zfs snapshot zroot@blank";
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

  # Follows https://grahamc.com/blog/erase-your-darlings/
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r zpool/local/root@blank
  '';
}
