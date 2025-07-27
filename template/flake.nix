{
  description = "Flake For Skarabox.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    selfhostblocks.url = "github:ibizaman/selfhostblocks";
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

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } ({ config, ... }: {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      # Darwin systems are supported but not as hosts to deploy to.
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    imports = [
      inputs.skarabox.flakeModules.default
    ];

    skarabox.hosts = {
      myskarabox = {
        # Comment this line to use nixpkgs as the input instead of SelfHostBlocks.
        # Note: I'm not fully convinced this line is correct and gets the patch applied.
        nixpkgs = inputs.selfhostblocks.lib.${config.skarabox.hosts.myskarabox.system}.patchedNixpkgs.src;
        system = ./myskarabox/system;
        hostKeyPub = ./myskarabox/host_key.pub;
        ip = ./myskarabox/ip;
        sshAuthorizedKey = ./myskarabox/ssh.pub;
        knownHosts = ./myskarabox/known_hosts;

        modules = [
          inputs.sops-nix.nixosModules.default
          self.nixosModules.myskarabox
        ];
        extraBeaconModules = [
          {
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
  });
}
