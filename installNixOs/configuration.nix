{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox;
in
{
  options.skarabox = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "skarabox";
      description = "Hostname to give to the server.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "skarabox";
      description = "Name given to the admin user on the server.";
    };

    initialHashedPassword = lib.mkOption {
      type = lib.types.str;
      default = "$y$j9T$7EZvmryvlpTHSRG7dC5IU1$lBc/nePnkvqZ//jNpx/UpFKze/p6P7AIhJubK/Ghj68";
      description = "Initial password for the admin user. Can be changed later. Default is 'skarabox123'.";
    };
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostName = cfg.hostname;
    networking.hostId = lib.mkDefault
      (pkgs.lib.readFile ((pkgs.runCommand "hostid.sh" {}
        ''
          mkdir -p $out
          ${pkgs.util-linux}/bin/uuidgen | head -c 8 > $out/hostid
        '') + "/hostid"));
    networking.useDHCP = lib.mkDefault config.hardware.enableRedistributableFirmware;

    nixpkgs.hostPlatform = "x86_64-linux";
    powerManagement.cpuFreqGovernor = "performance";
    hardware.cpu.amd.updateMicrocode = true;

    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      inherit (cfg) initialHashedPassword;
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
      PasswordAuthentication = true;
    };

    system.stateVersion = "23.11";
  };
}
