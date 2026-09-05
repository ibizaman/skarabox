{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.skarabox;
  journalSettings = {
    SystemMaxUse = "2G";
    SystemKeepFree = "4G";
    SystemMaxFileSize = "100M";
    MaxFileSec = "1d";
  };
in
{
  imports = [
    ./options.nix
    ./network.nix
  ];

  config = {
    hardware.facter.reportPath = lib.mkIf (
      builtins.pathExists cfg.facter-config && (builtins.readFile cfg.facter-config != "")
    ) cfg.facter-config;

    networking.hostName = cfg.hostname;
    networking.hostId = cfg.hostId;

    environment.etc."machine-id".text = cfg.machineId;

    powerManagement.cpuFreqGovernor = "performance";

    nix.settings.trusted-users = [ cfg.username ];
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.settings.auto-optimise-store = true;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # services.journald.settings replaced extraConfig in NixOS 26.11.
    # See https://www.freedesktop.org/software/systemd/man/journald.conf.html#SystemMaxUse=
    services.journald =
      if options.services.journald ? settings then
        { settings.Journal = journalSettings; }
      else
        { extraConfig = lib.generators.toKeyValue { } journalSettings; };

    # hashedPasswordFile only works if users are not mutable.
    users.mutableUsers = false;
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      inherit (cfg) hashedPasswordFile;
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKeys;
    };

    security.sudo.extraRules = [
      {
        users = [ cfg.username ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    boot.initrd.systemd.enable = true;

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
      openFirewall = true;
      hostKeys = lib.mkForce [ ];
      generateHostKeys = false;
      extraConfig = ''
        HostKey /boot/host_key
      '';
    };

    system.stateVersion = "23.11";
  };
}
