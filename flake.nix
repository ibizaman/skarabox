{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules = {
      url = "github:numtide/nixos-facter-modules";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    nix-flake-tests = {
      url = "github:antifuchs/nix-flake-tests";
    };

    nmdsrc = {
      url = "git+https://git.sr.ht/~rycee/nmd";
      flake = false;
    };
  };

  outputs = inputs@{
    self,
    flake-parts,
    nixos-anywhere,
    nixos-facter-modules,
    nix-flake-tests,
    ...
  }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      # Darwin systems are supported but not as hosts to deploy to.
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    perSystem = { self', inputs', pkgs, system, ... }: {
      packages = rec {
        # Usage:
        #  init [-h] [-y] [-s] [-v] [-p PATH]
        #
        # print help:
        #  init -h
        init = import ./lib/gen-initial.nix {
          inherit pkgs gen-new-host sops-create-main-key sops-add-main-key;
        };

        add-sops-cfg = import ./lib/add-sops-cfg.nix {
          inherit pkgs;
        };

        sops-create-main-key = import ./lib/sops-create-main-key.nix {
          inherit pkgs;
        };

        sops-add-main-key = import ./lib/sops-add-main-key.nix {
          inherit pkgs add-sops-cfg;
        };

        gen-new-host = import ./lib/gen-new-host.nix {
          inherit pkgs add-sops-cfg gen-hostId;
          inherit (pkgs) lib;
        };

        gen-hostId = pkgs.writeShellApplication {
          name = "gen-hostId";

          runtimeInputs = [
            pkgs.util-linux
          ];

          text = ''
          uuidgen | head -c 8
        '';
        };

        manualHtml = pkgs.callPackage ./docs {
          inherit (inputs) nmdsrc;
          skaraboxModules = [
            ./modules/bootssh.nix
            ./modules/configuration.nix
            ./modules/disks.nix
            ./modules/hotspot.nix
          ];
          beaconModules = [
            ./modules/beacon.nix
          ];
          flakeModuleModules = [
            ./flakeModules/default.nix
            ./flakeModules/colmena.nix
            ./flakeModules/deploy-rs.nix
          ];
          release = builtins.readFile ./VERSION;
        };
      };

      checks = import ./tests {
        inherit pkgs system nix-flake-tests;
      };

      # Used to experiment with ruamel library.
      devShells.pythonShell = pkgs.mkShell {
        packages = [
          (pkgs.python3.withPackages (python-pkgs: [
            python-pkgs.ruamel-yaml
          ]))
        ];
      };
    };

    flake = {
      lib = import ./lib/functions.nix;

      skaraboxInputs = inputs;

      flakeModules.default = ./flakeModules/default.nix;
      flakeModules.colmena = ./flakeModules/colmena.nix;
      flakeModules.deploy-rs = ./flakeModules/deploy-rs.nix;

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
          nixos-facter-modules.nixosModules.facter
          ./modules/disks.nix
          ./modules/bootssh.nix
          ./modules/configuration.nix
        ];
      };

      nix-ci = {
        cachix = {
          name = "selfhostblocks";
          public-key = "selfhostblocks.cachix.org-1:H5h6Uj188DObUJDbEbSAwc377uvcjSFOfpxyCFP7cVs=";
        };
      };
    };
  };
}
