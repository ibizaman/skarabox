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

          modules = [
            ./modules/beacon.nix
          ];
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
          ./modules/disks.nix
          ./modules/configuration.nix
        ];
      };
    };
  };
}
