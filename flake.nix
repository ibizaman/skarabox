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

    nixos-facter-modules = {
      url = "github:numtide/nixos-facter-modules";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
    };

    nix-flake-tests = {
      url = "github:antifuchs/nix-flake-tests";
    };
  };

  outputs = inputs@{
    self,
    flake-parts,
    nixpkgs,
    nixos-anywhere,
    nixos-facter-modules,
    deploy-rs,
    nix-flake-tests,
    ...
  }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
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
          inherit add-sops-cfg pkgs;
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
      skaraboxInputs = inputs;

      lib = {
        readAndTrim = f: nixpkgs.lib.strings.trim (builtins.readFile f);
      };

      flakeModules.default = ./flakeModule.nix;

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
