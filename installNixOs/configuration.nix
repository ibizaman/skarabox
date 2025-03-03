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
      description = "8 characters unique identifier for this server. Generate with `uuidgen | head -c 8`.";
    };

    sshAuthorizedKeyFile = mkOption {
      type = types.path;
      description = ''
        Public SSH key used to connect on boot to decrypt the root pool.
      '';
      example = "./ssh_skarabox.pub";
    };
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = cfg.hostname;
    networking.hostId = cfg.hostId;
      # TODO: this was a good idea but generating a new hostId every time is not what's needed. The
      # generation should only happen once.
      # (pkgs.lib.readFile ((pkgs.runCommand "hostid.sh" {}
      #   ''
      #     mkdir -p $out
      #     ${pkgs.util-linux}/bin/uuidgen | head -c 8 > $out/hostid
      #   '') + "/hostid"));
    networking.useDHCP = lib.mkDefault config.hardware.enableRedistributableFirmware;

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

    services.openssh.enable = true;
    services.openssh.settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };

    system.stateVersion = "23.11";
  };
}
