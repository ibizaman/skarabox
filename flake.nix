{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, nixos-generators, disko, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    perSystem = { self', pkgs, system, ... }: {
      packages = {
        beacon = nixos-generators.nixosGenerate {
          inherit system;
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
          })];
        };

        beacon-test = let
          pkgs = import nixpkgs {
            inherit system;
          };
          iso = "${self'.outputs.packages.${system}.beacon}/iso/beacon.iso";
          hostSshPort = 2222;
        in (pkgs.writeShellScriptBin "runner.sh" ''
          ${pkgs.qemu}/bin/qemu-system-x86_64 \
            -m 2048M \
            -nic hostfwd=tcp::${toString hostSshPort}-:22 \
            --drive media=cdrom,format=raw,readonly=on,file=${iso}

          '');
      };

      apps = {
        beacon-test = {
          type = "app";
          program = "${self'.outputs.packages.x86_64-linux.beacon-test}/bin/runner.sh";
        };
      };
    };

    flake = {
      templates = {
        skarabox = {
          path = ./template;
          description = "Skarabox template";
        };

        default = self.templates.skarabox;
      };


      nixosModules.skarabox = {
        imports = [
          disko.nixosModules.disko
          ./installNixOs/disks.nix
          ./installNixOs/configuration.nix
        ];
      };
    };
  };
}
