{ config, lib, pkgs, ... }: let
  inherit (lib) mkForce types;

  cfg = config.skarabox;

  helptext = ''
  * Step 1.  Enable network access to this server.

  For a wired network connection, just plug in an ethernet cable from your router
  to this server. The connection will be made automatically.

  For a wireless connection, if a card is found, a "Skarabox" wifi hotspot will
  be created automatically. Connect to it from your laptop.
  ''
  + (if (cfg.staticNetwork == null) then ''
  The IP address for this beacon is set through DHCP.
  Run "ip a" command to get the IP address.
  '' else ''
  The IP address for this beacon is ${cfg.staticNetwork.ip}.
  '')
  + ''
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

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsListOfStr = v: if lib.isList v then map readAsStr v else [ (readAsStr v) ];
in {
  imports = [
    ./hotspot.nix
    ./network.nix
  ];

  options.skarabox = {
    ip = lib.mkOption {
      description = ''
        Static IP of the beacon.
      '';
      type = types.str;
      default = cfg.ip;
      defaultText = "config.skarabox.ip";
    };

    hostname = lib.mkOption {
      description = ''
        Hostname to give to the beacon.

        Defaults to the hostname configured for the target host.
      '';
      type = types.str;
      default = "skarabox";
    };

    username = lib.mkOption {
      description = ''
        Username with which you can log into the beacon.

        Defaults to the hostname configured for the target host which works well if using the beacon.

        If installing on a cloud instance, set this to the user that can ssh into the instance as given by your cloud provider.
      '';
      type = types.str;
      default = "skarabox";
    };

    sshPort = lib.mkOption {
      type = types.int;
      description = ''
        Port the SSH daemon listens to on the beacon.

        Defaults to the same port configured for the target host which works well if using the beacon.

        If installing on a cloud instance, set this to the port that can ssh into the instance as given by your cloud provider, usually 22.
      '';
      default = cfg.sshPort;
      defaultText = "config.skarabox.sshPort";
    };

    sshAuthorizedKey = lib.mkOption {
      type =
        with types;
        let
          t = oneOf [
            str
            path
          ];
        in
        oneOf [
          t
          (listOf t)
        ];
      description = ''
        Public key(s) to connect to the beacon.

        Each key defined will be added to the authorized key for the user.

        Usually, for the beacon, one key is enough but the option allows multiple
        to match the configuration for the target host.

        Defaults to the same key(s) configured for the target host which works well if using the beacon.

        If installing on a cloud instance, set this to the ssh key that can ssh into the instance as given by your cloud provider.
      '';
      default = cfg.sshAuthorizedKey;
      defaultText = "config.skarabox.sshAuthorizedKey";
      apply = readAsListOfStr;
    };
  };

  config = {
    networking.hostName = cfg.hostname;

    # Also allow root to connect for nixos-anywhere.
    users.users.root = {
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKey;
    };
    # Override user set in profiles/installation-device.nix
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "video" ];
      # Allow the graphical user to login without password
      initialHashedPassword = "";
      # Set shared ssh key
      openssh.authorizedKeys.keys = cfg.sshAuthorizedKey;
    };
    # Automatically log in at the virtual consoles.
    services.getty.autologinUser = lib.mkForce cfg.username;
    nix.settings.trusted-users = [ cfg.username ];
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    image.fileName = mkForce "beacon.iso";
    image.baseName = mkForce "beacon";

    boot.loader.systemd-boot.enable = true;

    # Skarabox does not support systemd in stage1 yet.
    boot.initrd.systemd.enable = false;

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

    services.openssh = {
      enable = true;
      ports = [ cfg.sshPort ];
    };

    services.getty.helpLine = mkForce (''

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

    ''
    + (if (cfg.staticNetwork == null) then ''
    The IP address for this beacon is set through DHCP.
    Run "ip a" command to get the IP address.

    '' else ''
    The IP address for this beacon is ${cfg.staticNetwork.ip}.

    '')
    + ''
    The ssh server is listening on port ${toString cfg.sshPort}.
    '');
  };
}
