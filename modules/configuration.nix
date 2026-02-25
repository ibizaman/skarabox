{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox;
in
{
  imports = [
    ./options.nix
    ./network.nix
  ];

  config = {
    facter.reportPath = lib.mkIf (builtins.pathExists cfg.facter-config) cfg.facter-config;

    networking.hostName = cfg.hostname;
    networking.hostId = cfg.hostId;

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
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKey;
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

    networking.firewall.allowedTCPPorts = [ cfg.sshPort ];
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
