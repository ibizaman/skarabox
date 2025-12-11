{ config, pkgs, lib, ... }:
let
  cfg = config.skarabox.hotspot;

  inherit (lib) mkOption types;

  hotspotService = "skarabox-hotspot-createap";
in
{
  options.skarabox.hotspot = {
    enable = lib.mkEnableOption "the Skarabox HotSpot" // {
      default = true;
    };

    ip = mkOption {
      description = "IP address of the beacon in the hotspot network.";
      type = types.str;
      default = "192.168.12.1";
    };

    ssid = mkOption {
      description = "SSID of the hotspot network.";
      type = types.str;
      default = "Skarabox";
    };
  };
  config = lib.mkIf cfg.enable {
    systemd.services."${hotspotService}@" = {
      description = "Create AP Service";
      after = [ "network.target" "network-pre.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.linux-wifi-hotspot}/bin/create_ap --redirect-to-localhost -n -g ${cfg.ip} %I ${cfg.ssid}";
        KillSignal = "SIGINT";
        Restart = "on-failure";
      };
    };

    systemd.services."skarabox-hotspot-force-udev" = {
      description = "Trigger udev for existing wlan interfaces";
      after = [ "systemd-udev-settle.service" "network-pre.target" ];
      before = [ "network.target" ];
      wantedBy = [ "network.target" ];

      unitConfig = {
        DefaultDependencies = false;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemdMinimal}/bin/udevadm trigger --subsystem-match=net --property-match=DEVTYPE=wlan";
      };
    };

    # 'change' is needed to be correctly triggered by the udevadm trigger command.
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan", TAG+="systemd", ENV{SYSTEMD_WANTS}="${hotspotService}@%k.service"
      ACTION=="remove",     SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan", RUN+="${pkgs.systemdMinimal}/bin/systemctl stop ${hotspotService}@%k.service"
    '';
  };
}
