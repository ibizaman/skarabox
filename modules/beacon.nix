{ config, lib, pkgs, ... }: let
  inherit (lib) mkForce types;

  cfg = config.skarabox;
in {
  options.skarabox = {
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

    services.hostapd = {
      enable = true;
      radios.skarabox = {
        band = "2g";
        networks.skarabox = {
          ssid = "Skarabox";
          authentication = {
            mode = "wpa2-sha256";
            wpaPassword = "skarabox";
          };
        };
      };
    };

    environment.systemPackages = let
      skarabox-help = pkgs.writeText "skarabox-help" config.services.getty.helpLine;
    in [
      (pkgs.writeShellScriptBin "skarabox" ''
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

    services.getty.helpLine = mkForce ''

        /           \\
       |/  _.-=-._  \\|       SKARABOX
       \\'_/`-. .-'\\_'/
        '-\\ _ V _ /-'
          .' 'v' '.     Hello, you just booted on the Skarabox beacon.
        .'|   |   |'.   Congratulations!
        v'|   |   |'v
          |   |   |     Nothing is installed yet on this server. To abort, just
         .\\   |   /.    close this server and remove the USB stick.
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


      * Step 1.  Enable network access to this server.

      For a wired network connection, just plug in an ethernet cable from your router
      to this server. The connection will be made automatically.

      If you need a wireless connection, configure a network by typing the command
      "wpa_cli" without the enclosing double quotes.

      * Step 2.  Identify the disk layout.

      To know what disk existing in the system, type the command "fdisk -l" without
      the double quotes. This will show lines like so:

      Disk /dev/nvme0n1       This is an NVMe drive
      Disk /dev/sda           This is an SSD or HDD drive
      Disk /dev/sdb           This is an SSD or HDD drive

      With the above setup, in the flake.nix template, set the following options:

          skarabox.disks.rootDisk = "/dev/nvme0n1"
          skarabox.disks.dataDisk1 = "/dev/sda"
          skarabox.disks.dataDisk2 = "/dev/sdb"

      * Step 3.  Run the installer.

      When running the installer, you will need to enter the password "skarabox123" as
      well as the IP address of this server. To know the IP address, first follow the
      step 1 above then type the command "ip -brief a" verbatim, without the enclosing
      double quotes.

      Try all IP addresses one by one until one works. An IP address looks like so:

        192.168.1.15
        10.0.2.15

      * Step 4.

      No step 4. The server will reboot automatically in the new system as soon as the
      installer ran successfully. Enjoy your NixOS system powered by Skarabox!
    '';
  };
}
