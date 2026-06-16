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
      # Only one of deploy-rs or colmena is required to deploy.
      # You can comment the one you don't use and remove the corresponding input.
      inputs.skarabox.flakeModules.deploy-rs
      inputs.skarabox.flakeModules.colmena
    ];

    skarabox.hosts = {
      myskarabox = let
        system = "x86_64-linux";
      in {
        # Comment this line to use inputs.nixpkgs as the input instead of SelfHostBlocks.
        nixpkgs = inputs.selfhostblocks.lib.${system}.patchedNixpkgs;
        inherit system;
        hostKeyPath = "./myskarabox/host_key";
        hostKeyPub = ./myskarabox/host_key.pub;
        ip = "192.168.1.30";
        knownHosts = ./myskarabox/known_hosts;

        # These ports default to the one set in ./myskarabox/configuration.nix
        # You should only need to set these to other values
        # if the target host is accessed through some proxy
        # with some port forwarding.
        #
        # sshPort = 2222;
        # sshBootPort = 2223;

        # If you want to use an ssh agent to store the private key
        # set the sshPrivateKeyPath option to `null`,
        # generate an ssh key and add it to the ssh agent
        # then replace the ssh.pub file with the public key from the ssh agent.
        # Don't forget to set correct permissions on the ssh.pub file with
        # chmod 600 ssh.pub
        #
        # sshPrivateKeyPath = "./myskarabox/ssh";

        modules = [
          inputs.selfhostblocks.nixosModules.default
          inputs.sops-nix.nixosModules.default
          self.nixosModules.myskarabox
        ];

        # Set these options only if they differ from the options above.
        # This is the case for example when installing on a cloud instance
        # where the ssh config is given to you by the cloud provider.
        beacon = {
          # username = "<given by the cloud provider>";
          # sshPort = <given by the cloud provider>;
          # sshPrivateKeyPath = "<given by the cloud provider>";
        };
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
