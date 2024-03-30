{ config, lib, pkgs, ... }: {
  options = {
    hostId = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    networking.hostId = config.hostId;
    networking.useDHCP = lib.mkDefault config.hardware.enableRedistributableFirmware;

    nixpkgs.hostPlatform = "x86_64-linux";
    powerManagement.cpuFreqGovernor = "performance";
    hardware.cpu.amd.updateMicrocode = true;

    users.users.skarabox = {
      isNormalUser = true;
      extraGroups = [ "backup" "wheel" ];
    };

    security.sudo.extraRules = [
      { users = [ "skarabox" ];
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
      PasswordAuthentication = true;
    };

    system.stateVersion = "23.11";
  };
}
