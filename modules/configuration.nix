{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox;

  inherit (lib) mkOption types;
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

    initialHashedPassword = mkOption {
      type = types.str;
      default = "$y$j9T$7EZvmryvlpTHSRG7dC5IU1$lBc/nePnkvqZ//jNpx/UpFKze/p6P7AIhJubK/Ghj68";
      description = "Initial password for the admin user. Can be changed later. Default is 'skarabox123'.";
    };

    hostId = mkOption {
      type = types.str;
      description = ''
        8 characters unique identifier for this server. Generate with `uuidgen | head -c 8`.
      '';
    };

    sshPorts = mkOption {
      type = types.listOf types.port;
      default = [ 22 ];
      description = ''
        List of ports the SSH daemon listens to.
      '';
    };

    sshAuthorizedKeyFile = mkOption {
      type = types.path;
      description = ''
        Public SSH key used to connect on boot to decrypt the root pool.
      '';
      example = "./ssh_skarabox.pub";
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
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

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

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
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

    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      inherit (cfg) initialHashedPassword;
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
    ];

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
      ports = cfg.sshPorts;
      hostKeys = lib.mkForce [];
      extraConfig = ''
        HostKey /boot/host_key
      '';
    };

    system.stateVersion = "23.11";
  };
}
