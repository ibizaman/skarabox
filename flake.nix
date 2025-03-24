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

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, nixos-generators, nixos-anywhere, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
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
          iso = "${self'.packages.beacon}/iso/beacon.iso";
          hostSshPort = 2222;
          nixos-qemu = pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
          qemu = nixos-qemu.qemuBinary pkgs.qemu;
        in (pkgs.writeShellScriptBin "runner.sh" ''
          ${qemu} \
            -m 2048M \
            -nic hostfwd=tcp::${toString hostSshPort}-:22 \
            --drive media=cdrom,format=raw,readonly=on,file=${iso}
          '');
      };

      apps = {
        beacon-test = {
          type = "app";
          program = "${self'.packages.beacon-test}/bin/runner.sh";
        };

        nixos-anywhere = {
          type = "app";
          program = "${nixos-anywhere.packages.${system}.nixos-anywhere}/bin/nixos-anywhere";
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
          nixos-anywhere.inputs.disko.nixosModules.disko
          ./modules/disks.nix
          ./modules/configuration.nix
        ];
      };
    };
  };
}
