{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox;

  inherit (lib) mkOption toInt types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsInt = v: let
    vStr = readAsStr v;
  in
    if lib.isString vStr then toInt vStr else vStr;

in
{
  options.skarabox = {
    hostname = mkOption {
      type = types.str;
      default = "skarabox";
      description = "Hostname to give to the server.";
    };

    username = mkOption {
      type = types.str;
      default = "skarabox";
      description = "Name given to the admin user on the server.";
    };

    hashedPasswordFile = mkOption {
      type = types.str;
      description = "Contains password for the admin user.";
    };

    facter-config = lib.mkOption {
      type = lib.types.path;
      description = ''
        nixos-facter config file.
      '';
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
      default = [ 22 ];
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

    setupLanWithDHCP = mkOption {
      type = types.bool;
      description = ''
        Sets up a default IPV4 network on lan.

        This should suit most needs but if not,
        disable this and set it manually.
        The [wiki][] is very useful.

        [wiki]: https://wiki.nixos.org/wiki/Systemd/networkd
      '';
      default = true;
    };

    system = mkOption {
      type = types.str;
    };
  };

  config = {
    nixpkgs.hostPlatform = cfg.system;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    facter.reportPath = lib.mkIf (builtins.pathExists cfg.facter-config) cfg.facter-config;

    networking.hostName = cfg.hostname;
    networking.hostId = cfg.hostId;

    # https://wiki.nixos.org/wiki/Systemd/networkd
    systemd.network = lib.mkIf cfg.setupLanWithDHCP {
      enable = true;
      networks."10-lan" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
      };
    };

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
