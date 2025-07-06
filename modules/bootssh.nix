{ config, lib, ... }:
let
  cfg = config.skarabox.boot;

  inherit (lib) mkOption optionals toInt types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if lib.isString vStr then toInt vStr else vStr;
in
{
  options.skarabox.boot = {
    sshPort = mkOption {
      type = with types; oneOf [ int str path ];
      description = "Port the SSH daemon used to decrypt the root partition listens to.";
      default = 2222;
      apply = readAsInt;
    };
  };

  config = {
    # Enables DHCP in stage-1 even if networking.useDHCP is false.
    boot.initrd.network.udhcpc.enable = lib.mkDefault (config.skarabox.staticNetwork == null);
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
        port = lib.mkDefault cfg.sshPort;
        hostKeys = lib.mkForce ([ "/boot/host_key" ] ++ (optionals (config.skarabox.disks.rootPool.disk2 != null) [ "/boot-backup/host_key" ]));
        # Public ssh key used for login.
        # This should contain just one line and removing the trailing
        # newline could be fixed with a removeSuffix call but treating
        # it as a file containing multiple lines makes this forward compatible.
        authorizedKeys = [
          config.skarabox.sshAuthorizedKey
        ];
      };

      postCommands = ''
      zpool import -a
      echo "zfs load-key ${config.skarabox.disks.rootPool.name}; killall zfs; exit" >> /root/.profile
      '';
    };

    boot.kernelParams = lib.optionals (config.skarabox.staticNetwork != null && config.facter.report != {}) (let
      cfg' = config.skarabox.staticNetwork;
    in [
      # https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
      # ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
      "ip=${cfg'.ip}::${cfg'.gateway}:255.255.255.0:${config.skarabox.hostname}-initrd:${cfg'.deviceName}:off:::"
    ]);
  };
}
