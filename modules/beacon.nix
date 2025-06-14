{ config, lib, pkgs, ... }: let
  inherit (lib) mkForce types;

  cfg = config.skarabox;

  helptext = ''
  * Step 1.  Enable network access to this server.

  For a wired network connection, just plug in an ethernet cable from your router
  to this server. The connection will be made automatically.

  For a wireless connection, if a card is found, a "Skarabox" wifi hotspot will
  be created automatically. Connect to it from your laptop.

  * Step 2.  Identify the disk layout.

  To know what disk existing in the system, type the command "lsblk" without
  the double quotes. This will show lines like so:

  NAME             TYPE
  /dev/nvme0n1     disk             This is an NVMe drive
  /dev/sda         disk             This is an SSD or HDD drive
  /dev/sdb         disK             This is an SSD or HDD drive

  With the above setup, in the flake.nix template, set the following options:

      skarabox.disks.rootPool.disk1 = "/dev/nvme0n1"
      skarabox.disks.dataPool.disk1 = "/dev/sda"
      skarabox.disks.dataPool.disk2 = "/dev/sdb"

  * Step 3.  Run the installer.

  From your laptop, run the installer. The server will then reboot automatically
  in the new system as soon as the installer ran successfully.

  Enjoy your NixOS system powered by Skarabox!
  '';
in {
  imports = [
    ./hotspot.nix
  ];

  options.skarabox = {
    ip = lib.mkOption {
      description = "Force static IP for beacon instead of using DHCP.";
      type = types.nullOr types.str;
      default = null;
    };

    hostname = lib.mkOption {
      description = "Hostname to give the beacon. Use the same as for the host to simplify installation.";
      type = types.str;
      default = "skarabox";
    };

    username = lib.mkOption {
      description = "Username with which you can log on the beacon. Use the same as for the host to simplify installation.";
      type = types.str;
      default = "skarabox";
    };

    sshPublicKey = lib.mkOption {
      description = "Public key to connect to the beacon. Use the same as for the host to simplify installation.";
      type = types.path;
    };
  };

  config = {
    networking.hostName = cfg.hostname;

    # Also allow root to connect for nixos-anywhere.
    users.users.root = {
      openssh.authorizedKeys.keyFiles = [ cfg.sshPublicKey ];
    };
    # Override user set in profiles/installation-device.nix
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "video" ];
      # Allow the graphical user to login without password
      initialHashedPassword = "";
      # Set shared ssh key
      openssh.authorizedKeys.keyFiles = [ cfg.sshPublicKey ];
    };
    # Automatically log in at the virtual consoles.
    services.getty.autologinUser = lib.mkForce cfg.username;
    nix.settings.trusted-users = [ cfg.username ];
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    image.fileName = mkForce "beacon.iso";
    image.baseName = mkForce "beacon";

    networking.firewall.allowedTCPPorts = [ 22 ];

    boot.loader.systemd-boot.enable = true;

    environment.systemPackages = let
      skarabox-help = pkgs.writeText "skarabox-help" helptext;
    in [
      (pkgs.writeShellScriptBin "skarabox-help" ''
       cat ${skarabox-help}
       '')
      pkgs.nixos-facter

      pkgs.tmux

      # Useful network tools
      pkgs.dig

      # Useful system tools
      pkgs.htop
      pkgs.glances
      pkgs.iotop
    ];

    systemd.network = lib.mkIf (cfg.ip != null) {
      enable = true;
      networks."10-lan" = {
        matchConfig.Name = "en*";
        address = [
          "${cfg.ip}/24"
        ];
        linkConfig.RequiredForOnline = true;
      };
    };
    skarabox.hotspot.ip = lib.mkIf (cfg.ip != null) cfg.ip;

    services.getty.helpLine = mkForce ''

        /           \\
       |/  _.-=-._  \\|       SKARABOX
       \\'_/`-. .-'\\_'/
        '-\\ _ V _ /-'
          .' 'v' '.     Hello, you just booted on the Skarabox beacon.
        .'|   |   |'.   Congratulations!
        v'|   |   |'v
          |   |   |     Nothing is installed yet on this server. To abort, just
         .\\   |   /.    shutdown this server and remove the USB stick.
        (_.'._^_.'._)
         \\\\       //    To complete the installation of Skarabox on this server, you
          \\'-   -'/     must follow the steps below to run the Skarabox installer.


       WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING
       *                                                                           *
       *    Running the Skarabox installer WILL ERASE EVERYTHING on this server.   *
       *    Make sure the only drives connected and powered on are the disks to    *
       *    install the Operating System on. This drive should be a SSD or NVMe    *
       *    drive for optimal performance and 2 hard drives for data.              *
       *                                                                           *
       *                       THESE DRIVES WILL BE ERASED.                        *
       *                                                                           *
       WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING

      Run the command `skarabox-help` to print more details.
    '';
  };
}
