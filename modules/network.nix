{ config, lib, ... }:
let
  cfg = config.skarabox;

  inherit (lib) isString mkOption types;
in
{
  options.skarabox = {
    staticNetwork = mkOption {
      description = "Use static IP configuration. If unset, use DHCP.";
      default = null;
      example = lib.literalExpression ''
      {
        ip = "192.168.1.30";
        gateway = "192.168.1.1";
      }
      '';
      type = types.nullOr (types.submodule {
        options = {
          enable = lib.mkEnableOption "Skarabox static IP configuration";
          ip = mkOption {
            type = types.str;
            description = "Static IP to use.";
          };
          gateway = mkOption {
            type = types.str;
            description = "IP Gateway, often same beginning as `ip` and finishing by a `1`: `XXX.YYY.ZZZ.1`.";
          };
          device = mkOption {
            description = ''
            Device for which to configure the IP address for.

            Either pass the device name directly if you know it, like "ens3".
            Or configure the `deviceName` option to get the first device name
            matching that prefix from the facter.json report.
            '';
            default = { namePrefix = "en"; };
            type = with types; oneOf [
              str
              (submodule {
                options = {
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
          deviceName = mkOption {
            description = ''
            Result of applying match pattern from `.device` option
            or the string defined in `.device` option.
            '';
            readOnly = true;
            internal = true;
            default = let
              cfg' = cfg.staticNetwork;

              network_interfaces = config.facter.report.hardware.network_interface;

              firstMatchingDevice = builtins.head (builtins.filter (lib.hasPrefix "en") (lib.flatten (map (x: x.unix_device_names) network_interfaces)));
            in
              if isString cfg'.device then cfg'.device else firstMatchingDevice;
          };
        };
      });
    };

    disableNetworkSetup = mkOption {
      description = ''
        If set to false, completely disable network setup by Skarabox.

        Make sure you can still ssh to the server.
      '';
      type = types.bool;
      default = false;
    };
  };

  config = lib.mkIf (!cfg.disableNetworkSetup) {
    assertions = [
      {
        assertion = cfg.staticNetwork == null -> config.boot.initrd.network.udhcpc.enable;
        message = ''
          If DHCP is disabled and an IP is not set, the box will not be reachable through the network on boot and you will not be able to enter the passphrase through SSH.

          To fix this error, either set config.boot.initrd.network.udhcpc.enable = true or give an IP to skarabox.staticNetwork.ip.
        '';
      }
    ];

    # Removing this line shows a warning that the current configuration
    # leads to network interfaces managed by both systemd and a custom NixOS script.
    networking.useNetworkd = true;
    systemd.network = (
      {
        enable = true;
      }
      // (if cfg.staticNetwork == null then {
        networks."10-lan" = {
          matchConfig.Name = "en*";
          networkConfig.DHCP = "ipv4";
          linkConfig.RequiredForOnline = true;
        };
      } else {
        networks."10-lan" = {
          matchConfig.Name = "en*";
          address = [
            "${cfg.staticNetwork.ip}/24"
          ];
          routes = [
            { Gateway = cfg.staticNetwork.gateway; }
          ];
          linkConfig.RequiredForOnline = true;
        };
      }));

  };
}
