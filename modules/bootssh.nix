{ config, lib, ... }:
let
  cfg = config.skarabox.disks;

  inherit (lib) isString mkOption optionals toInt types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if lib.isString vStr then toInt vStr else vStr;
in
{
  options.skarabox.disks.boot = {
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
                  namePrefix = mkOption {
                    type = str;
                    description = "Name prefix as it appears in the facter.json report. Used to distinguish between wifi and ethernet.";
                    default = "en";
                    example = "wl";
                  };
                };
              })
            ];
          };
        };
      });
    };
  };

  config = {
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
        cfg' = cfg.boot.staticNetwork;

        fn = n: n.sub_class.name == cfg'.device.subClass && lib.hasPrefix cfg'.device.namePrefix n.unix_device_name;

        firstMatchingDevice = (builtins.head (builtins.filter fn config.facter.report.hardware.network_interface)).unix_device_name;

        deviceName = if isString cfg'.device then cfg'.device else firstMatchingDevice;
      in [
        # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
        # ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
        "ip=${cfg'.ip}::${cfg'.gateway}:${cfg'.netmask}:${config.skarabox.hostname}-initrd:${deviceName}:off:::"
      ]);
  };
}
