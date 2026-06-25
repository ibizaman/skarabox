{ config, lib, ... }:
let
  cfg = config.skarabox.boot;

  inherit (lib) mkOption optionals types;
in
{
  options.skarabox.boot = {
    sshPort = mkOption {
      type = types.int;
      description = "Port the SSH daemon used to decrypt the root partition listens to.";
      default = 2223;
    };
  };

  config = {
    # Keep this in sync with the stage-2 networkd config in ./network.nix.
    boot.initrd.systemd.network = {
      enable = true;
    } // (if config.skarabox.staticNetwork == null then {
      networks."10-lan" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
        linkConfig.RequiredForOnline = true;
      };
    } else {
      networks."10-lan" = {
        matchConfig.Name = "en*";
        address = [
          "${config.skarabox.staticNetwork.ip}/24"
        ];
        routes = [
          { Gateway = config.skarabox.staticNetwork.gateway; }
        ];
        linkConfig.RequiredForOnline = true;
      };
    });

    boot.initrd.network = {
      enable = true;
      ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used,
        # a different port for ssh is used.
        port = lib.mkDefault cfg.sshPort;
        hostKeys = lib.mkForce ([ "/boot/host_key" ] ++ (optionals (config.skarabox.disks.rootPool.disk2 != null) [ "/boot-backup/host_key" ]));
        # Only allow remote unlocks, not arbitrary initrd commands.
        authorizedKeys = map (key: ''command="/bin/systemctl default" ${key}'') config.skarabox.sshAuthorizedKeys;
      };
    };
  };
}
