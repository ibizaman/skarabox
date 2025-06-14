{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox;

  inherit (lib) isString mkOption toInt types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if isString vStr then toInt vStr else vStr;

in
{
  options.skarabox = {
    hostname = mkOption {
      description = "Hostname to give to the server.";
      type = types.str;
      default = "skarabox";
    };

    username = mkOption {
      description = "Name given to the admin user on the server.";
      type = types.str;
      default = "skarabox";
    };

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

              fn = n: n.sub_class.name == "Ethernet" && lib.hasPrefix cfg'.device.namePrefix n.unix_device_name;

              firstMatchingDevice = (builtins.head (builtins.filter fn config.facter.report.hardware.network_interface)).unix_device_name;
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

    hashedPasswordFile = mkOption {
      description = "Contains hashed password for the admin user.";
      type = types.str;
    };

    facter-config = lib.mkOption {
      description = ''
        nixos-facter config file.
      '';
      type = lib.types.path;
    };

    hostId = mkOption {
      type = with types; oneOf [ str path ];
      description = ''
        8 characters unique identifier for this server. Generate with `uuidgen | head -c 8`.
      '';
      apply = readAsStr;
    };

    sshPort = mkOption {
      type = with types; oneOf [ int str path ];
      default = 22;
      description = ''
        Port the SSH daemon listens to.
      '';
      apply = readAsInt;
    };

    sshAuthorizedKeyFile = mkOption {
      type = types.path;
      description = ''
        Public SSH key used to connect on boot to decrypt the root pool.
      '';
      example = "./ssh.pub";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.staticNetwork == null -> config.boot.initrd.network.udhcpc.enable;
        message = ''
          If DHCP is disabled and an IP is not set, the box will not be reachable through the network on boot and you will not be able to enter the passphrase through SSH.

          To fix this error, either set config.boot.initrd.network.udhcpc.enable = true or give an IP to skarabox.staticNetwork.ip.
        '';
      }
    ];

    facter.reportPath = lib.mkIf (builtins.pathExists cfg.facter-config) cfg.facter-config;

    networking.hostName = cfg.hostname;
    networking.hostId = cfg.hostId;

    systemd.network = lib.mkIf (!cfg.disableNetworkSetup) (
      if cfg.staticNetwork == null then {
        enable = true;
        networks."10-lan" = {
          matchConfig.Name = "en*";
          networkConfig.DHCP = "ipv4";
          linkConfig.RequiredForOnline = true;
        };
      } else {
        enable = true;
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
      });

    powerManagement.cpuFreqGovernor = "performance";

    nix.settings.trusted-users = [ cfg.username ];
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.settings.auto-optimise-store = true;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # See https://www.freedesktop.org/software/systemd/man/journald.conf.html#SystemMaxUse=
    services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=4G
    SystemMaxFileSize=100M
    MaxFileSec=day
    '';

    # hashedPasswordFile only works if users are not mutable.
    users.mutableUsers = false;
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      inherit (cfg) hashedPasswordFile;
      openssh.authorizedKeys.keyFiles = [ cfg.sshAuthorizedKeyFile ];
    };

    security.sudo.extraRules = [
      { users = [ cfg.username ];
        commands = [
          { command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    environment.systemPackages = [
      pkgs.vim
      pkgs.curl
      pkgs.nixos-facter
    ];

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
      ports = [ cfg.sshPort ];
      hostKeys = lib.mkForce [];
      extraConfig = ''
        HostKey /boot/host_key
      '';
    };

    system.stateVersion = "23.11";
  };
}
