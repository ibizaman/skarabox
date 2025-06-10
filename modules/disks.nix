{ config, lib, ... }:
let
  cfg = config.skarabox.disks;

  inherit (lib) isString mkIf mkOption optionals optionalString toInt types;

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
            description = "Mirror SSD disk on which to install. Optional. Boot partition will be mirrored too.";
            example = "/dev/nvme0n2";
            default = null;
          };

          reservation = mkOption {
            type = types.str;
            description = ''
              Disk size to reserve for ZFS internals. Should be between 10% and 15% of available size as recorded by zpool.

              To get available size on zpool:

                 zfs get -Hpo value available <pool name>

              Then to set manually, if needed:

                 sudo zfs set reservation=100G <pool name>
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

                 zfs get -Hpo value available <pool name>

              Then to set manually, if needed:

                 sudo zfs set reservation=100G <pool name>
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

    boot = mkOption {
      type = types.submodule {
        options = {
          sshPort = mkOption {
            type = with types; oneOf [ int str path ];
            description = "Port the SSH daemon used to decrypt the root partition listens to.";
            default = 2222;
            apply = readAsInt;
          };

          staticNetwork = mkOption {
            description = "Use static IP configuration. If unset, use DHCP.";
            default = null;
            type = types.nullOr (types.submodule {
              options = {
                ip = mkOption {
                  type = types.str;
                  description = "Static IP to use.";
                };
                gateway = mkOption {
                  type = types.str;
                  description = "IP Gateway, often `XXX.YYY.ZZZ.1`.";
                };
                netmask = mkOption {
                  type = types.str;
                  description = "Netmask of local network.";
                  default = "255.255.255.0";
                };
                device = mkOption {
                  description = ''
                  Device for which to configure the IP address for.

                  Either pass the device name directly if you know it, like "ens3".
                  Or configure the `subClass` option to get the first device name
                  matching that sub-class from the facter.json report.
                  '';
                  default = { subClass = "Ethernet"; };
                  type = with types; oneOf [
                    str
                    (submodule {
                      options = {
                        subClass = mkOption {
                          type = str;
                          description = "Sub-class as it appears in the facter.json report.";
                          default = "Ethernet";
                        };
                      };
                    })
                  ];
                };
              };
            });
          };
        };
     };
   };


 };

 config = {
    assertions = [
      {
        assertion = cfg.boot.staticNetwork == null -> config.boot.initrd.network.udhcpc.enable;
        message = ''
          If DHCP is disabled and an IP is not set, the box will not be reachable through the network on boot and you will not be able to enter the passphrase through SSH.

          To fix this error, either set config.boot.initrd.network.udhcpc.enable = true or give an IP to skarabox.disks.boot.staticNetwork.ip.
        '';
      }
    ];

    disko.devices = {
      disk = let
        hasRaid = cfg.rootPool.disk2 != null;

        mkRoot = { disk, id ? "" }: {
          type = "disk";
          device = disk;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot${id}";
                  # Otherwise you get https://discourse.nixos.org/t/security-warning-when-installing-nixos-23-11/37636/2
                  mountOptions = [ "umask=0077" ];
                  # Copy the host_key needed for initrd in a location accessible on boot.
                  # It's prefixed by /mnt because we're installing and everything is mounted under /mnt.
                  # We're using the same host key because, well, it's the same host!
                  postMountHook = ''
                    cp /tmp/host_key /mnt/boot${id}/host_key
                  '';
                };
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
        root = mkRoot { disk = cfg.rootPool.disk1; };
        # Second root must have id=-backup.
        root1 = mkIf hasRaid (mkRoot { disk = cfg.rootPool.disk2; id = "-backup"; });
        data1 = mkIf cfg.dataPool.enable (mkDataDisk cfg.dataPool.disk1);
        data2 = mkIf cfg.dataPool.enable (mkDataDisk cfg.dataPool.disk2);
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

    # This is needed to make the /boot*/host_key available early
    # enough to be able to decrypt the sops file on boot,
    # when the /etc/shadow file is first generated.
    # We assume mkRoot will always be called with at least id=1.
    fileSystems = {
      "/boot".neededForBoot = true;
      "/boot-backup" = mkIf (cfg.rootPool.disk2 != null) { neededForBoot = true; };
    };
    # Setup Grub to support UEFI.
    # nodev is for UEFI.
    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;

      mirroredBoots = lib.mkForce ([
        {
          path = "/boot";
          devices = [ "nodev" ];
        }
      ] ++ (optionals (cfg.rootPool.disk2 != null) [
        {
          path = "/boot-backup";
          devices = [ "nodev" ];
        }
      ]));
    };

    # Follows https://grahamc.com/blog/erase-your-darlings/
    # https://github.com/NixOS/nixpkgs/pull/346247/files
    boot.initrd.postResumeCommands = lib.mkAfter ''
      zfs rollback -r ${cfg.rootPool.name}/local/root@blank
    '';

    # Enables DHCP in stage-1 even if networking.useDHCP is false.
    boot.initrd.network.udhcpc.enable = lib.mkDefault (cfg.boot.staticNetwork == null);
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
        port = lib.mkDefault cfg.boot.sshPort;
        hostKeys = lib.mkForce ([ "/boot/host_key" ] ++ (optionals (cfg.rootPool.disk2 != null) [ "/boot-backup/host_key" ]));
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
    boot.kernelParams = lib.optionals (cfg.boot.staticNetwork != null && config.facter.report != {}) (let
        n = cfg.boot.staticNetwork;

        firstMatchingDevice = subClass: (builtins.head (builtins.filter (n: n.sub_class.name == subClass) config.facter.report.hardware.network_interface)).unix_device_name;

        deviceName = if isString n.device then n.device else firstMatchingDevice n.device.subClass;
      in [
        # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
        # ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
        "ip=${n.ip}::${n.gateway}:${n.netmask}:${config.skarabox.hostname}-initrd:${deviceName}:off:::"
      ]);

    services.zfs.autoScrub.enable = true;
  };
}
