{
  description = "Flake For Skarabox.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    skarabox.url = "github:ibizaman/skarabox";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    flake-parts.url = "github:hercules-ci/flake-parts";
    deploy-rs.url = "github:serokell/deploy-rs";
    colmena.url = "github:zhaofengli/colmena";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = inputs@{ self, skarabox, sops-nix, nixpkgs, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    imports = [
      skarabox.flakeModules.default
    ];

    skarabox.hosts = {
      myskarabox = {
        system = ./myskarabox/system;
        hostKeyPub = ./myskarabox/host_key.pub;
        ip = ./myskarabox/ip;
        sshPublicKey = ./myskarabox/ssh.pub;
        knownHosts = ./myskarabox/known_hosts;

        modules = [
          sops-nix.nixosModules.default
          self.nixosModules.myskarabox
        ];
        extraBeaconModules = [
          {
            # Uncomment the following snippet to get
            # static IP assigned on the beacon.
            #
            # systemd.network = {
            #   enable = true;
            #   networks."10-lan" = {
            #     matchConfig.Name = "en*";
            #     address = [
            #       "192.168.1.10/24"
            #     ];
            #     routes = [
            #       { Gateway = "192.168.1.1"; }
            #     ];
            #     linkConfig.RequiredForOnline = true;
            #   };
            # };
            #
            # Add more utilities
            #
            # environment.systemPackages = [
            #   pkgs.tmux
            #   pkgs.htop
            #   pkgs.glances
            #   pkgs.iotop
            # ];
          }
        ];
      };
    };

    flake = {
      nixosModules = {
        myskarabox = {
          imports = [
            ./myskarabox/configuration.nix
          ];
        };
      };
    };
  };
}
