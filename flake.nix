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

    sops-nix = {
      url = "github:Mic92/sops-nix";
    };
  };

  outputs = inputs@{
    self,
    flake-parts,
    nixpkgs,
    nixos-generators,
    nixos-anywhere,
    nixos-facter-modules,
    deploy-rs,
    sops-nix,
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
        init = import ./lib/initialgen.nix {
          inherit pkgs gen-sopsconfig-file sops-yq-edit;
        };

        gen-sopsconfig-file = import ./lib/gensopsconfigfile.nix {
          inherit pkgs;
        };

        sops-yq-edit = import ./lib/sopsyqedit.nix {
          inherit pkgs;
        };

        inherit (pkgs) yq;
      };

      checks = import ./tests {
        inherit pkgs inputs system;
      };
    };

    flake = {
      lib = import ./lib {
        inherit
          deploy-rs
          nixpkgs
          nixos-anywhere
          nixos-generators
          sops-nix
          self
        ;
      };

      templates = {
        skarabox = {
          path = ./template;
          description = "Skarabox template";
        };

        default = self.templates.skarabox;
      };

      nixosModules.beacon = { config, lib, modulesPath, ... }: {
        imports = [
          ./modules/beacon.nix
          (modulesPath + "/profiles/minimal.nix")
        ];
      };

      nixosModules.skarabox = {
        imports = [
          nixos-anywhere.inputs.disko.nixosModules.disko
          nixos-facter-modules.nixosModules.facter
          sops-nix.nixosModules.default
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
