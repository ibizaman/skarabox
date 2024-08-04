{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    selfhostblocks = {
      url = "github:ibizaman/selfhostblocks";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "selfhostblocks/nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "selfhostblocks/nixpkgs";
    };
  };

  outputs = { self, selfhostblocks, nixos-generators, disko, ... }:
    let
      nixpkgs = selfhostblocks.inputs.nixpkgs;
    in
    {
    packages.x86_64-linux = {
      beacon = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "install-iso";

        modules = [({ config, lib, ... }: {
          users.users.nixos.initialHashedPassword = lib.mkForce "$y$j9T$7EZvmryvlpTHSRG7dC5IU1$lBc/nePnkvqZ//jNpx/UpFKze/p6P7AIhJubK/Ghj68";

          isoImage.isoName = lib.mkForce "beacon.iso";

          networking.firewall.allowedTCPPorts = [ 22 ];

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

          services.getty.helpLine = lib.mkForce ''

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

            If the server is equipped with a WiFi card, a WiFi network called "skarabox" will
            be available. Connect your laptop to that WiFi network. This network will only be
            available during installation.

            A wired network connection is available if you connect an Ethernet cable. If you
            need a wireless connection, configure a network by typing the command "wpa_cli"
            without the enclosing double quotes.

            * Step 2.  Run the installer.

            When running the installer, you will need to enter the password "skarabox123" as
            well as the IP address of this server. To know the IP address, first follow the
            step 1 above then type the command "ip -brief a" verbatim, without the enclosing
            double quotes.

            Try all IP addresses one by one until one works. An IP address looks like so:

              192.168.1.15
              10.0.2.15

            * Step 3.

            No step 3. The server will reboot automatically in the new system as soon as the
            installer ran successfully. Enjoy your NixOS system powered by Skarabox!
          '';
        })];
      };

      beacon-test = let
        system = "x86_64-linux";
        pkgs = import nixpkgs {
          inherit system;
        };
        iso = "${self.outputs.packages.${system}.beacon}/iso/beacon.iso";
        hostSshPort = 2222;
      in (pkgs.writeShellScriptBin "runner.sh" ''
        ${pkgs.qemu}/bin/qemu-system-x86_64 \
          -m 2048M \
          -nic hostfwd=tcp::${toString hostSshPort}-:22 \
          --drive media=cdrom,format=raw,readonly=on,file=${iso}
        
        '');
    };

    nixosModules.skarabox = let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      imports = [
        disko.nixosModules.disko
        "${pkgs.path}/nixos/modules/profiles/all-hardware.nix"
        ./installNixOs/disks.nix
        ./installNixOs/configuration.nix
      ];
    };

    apps.x86_64-linux = {
      beacon-test = {
        type = "app";
        program = "${self.outputs.packages.x86_64-linux.beacon-test}/bin/runner.sh";
      };
    };

    templates = {
      skarabox = {
        path = ./template;
        description = "Skarabox template";
      };

      default = self.templates.skarabox;
    };
  };
}
