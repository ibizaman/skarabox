{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, disko, ... }: {
    packages.x86_64-linux = {
      beacon = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "install-iso";

        modules = [({ config, lib, ... }: {
          users.users.nixos.initialHashedPassword = lib.mkForce "$y$j9T$7EZvmryvlpTHSRG7dC5IU1$lBc/nePnkvqZ//jNpx/UpFKze/p6P7AIhJubK/Ghj68";

          isoImage.isoName = lib.mkForce "beacon.iso";

          networking.firewall.allowedTCPPorts = [ 22 ];

          services.getty.helpLine = lib.mkForce ''

              /           \\
             |/  _.-=-._  \\|       SKARABOX
             \\'_/`-. .-'\\_'/ 
              '-\\ _ V _ /-'
                .' 'v' '.     Hello, you just booted on the Skarabox beacon.
              .'|   |   |'.   Congratulations!
              v'|   |   |'v
                |   |   |     Nothing is yet installed on this server. To abort, just
               .\\   |   /.    close this server and remove the USB stick.
              (_.'._^_.'._)   
               \\\\       //    To complete the installation of Skarabox on this server, you
                \\'-   -'/     must follow the steps below to run the Skarabox installer.


             WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING
             *                                                                           *
             *    Running the Skarabox installer WILL ERASE EVERYTHING on this server.   *
             *    Make sure the only disk connected and powered on is the disk to        *
             *    install the Operating System on. This disk should be a SSD or NVMe     *
             *    disk for optimal performance. THIS DISK WILL BE ERASED.                *
             *                                                                           *
             WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING - WARNING


            * Step 1.  Enable network access to this server. 

            A wired network connection is available if you connect an Ethernet cable. If you
            need a wireless connection, configure a network by typing the command "wpa_cli"
            without the enclosing double quotes.

            * Step 2.  Run the installer.

            When running the installer, you will need to enter the password "skarabox123" as
            well as the IP address of this server. To know the IP address, first follow the
            first step then type the command "ip -brief a" verbatim, without the enclosing
            double quotes.

            Try all IP addresses one by one until one works. An IP address looks like so:

              192.168.1.15
              10.0.2.15

            * Step 3.  Reboot this server and remove the USB stick.
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

    nixosConfigurations.remote-installer = let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        disko.nixosModules.disko
        "${pkgs.path}/nixos/modules/profiles/all-hardware.nix"
        ./disks.nix
        ./configuration.nix
        {
          networking.hostName = "skarabox";
        }
      ];
    };

    apps.x86_64-linux = {
      beacon-test = {
        type = "app";
        program = "${self.outputs.packages.x86_64-linux.beacon-test}/bin/runner.sh";
      };
    };
  };
}
