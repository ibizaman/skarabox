{
  description = "Flake for skarabox.";

  inputs = {
    skarabox.url = "github:ibizaman/skarabox";
  };

  outputs = inputs@{ self, skarabox }: skarabox.inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    let
      mySkarabox = skarabox.lib {
        hostKeyPub = ./host_key.pub;
        ip = ./ip;
        # Using string here so the sops key does not end up in the nix store.
        sopsKeyName = "sops.key";
        sshPrivateKeyName = "ssh_skarabox";
        sshPublicKey = ./ssh_skarabox.pub;
        knownHostsName = "known_hosts";
        knownHosts = ./known_hosts;
        sshPort = ./ssh_port;
        sshBootPort = ./ssh_boot_port;

        nixosConfiguration = self.nixosConfigurations.skarabox;

        patches = { fetchPatch, ... }: [
          # Leaving commented out for an example.
          # (fetchpatch {
          #   url = "https://github.com/NixOS/nixpkgs/pull/317107.patch";
          #   hash = "sha256-hoLrqV7XtR1hP/m0rV9hjYUBtrSjay0qcPUYlKKuVWk=";
          # })
        ];
        overlays = [
        ];
      };
    in {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem = { self', inputs', pkgs, system, ... }: let
        skaraboxPkgs = mySkarabox.withSystem {
          inherit system;
        };
      in {
        packages =
          skaraboxPkgs.packages
          // skaraboxPkgs.deploy-rs.packages
          // {
            # Add your own packages here
          };
      };

      flake = let
        system = mySkarabox.readFile ./system;

        skaraboxPackages = mySkarabox.withSystem {
          inherit system;
        };
      in {
        nixosModules.skarabox = {
          imports = [
            skarabox.nixosModules.skarabox
            ./configuration.nix
          ];
        };

        # Used with nixos-anywere for installation.
        nixosConfigurations.skarabox = skarabox.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.skarabox
          ];
        };

        # Used with deploy-rs for deploys after installation.
        deploy.nodes.skarabox = skaraboxPackages.deploy-rs.node;

        checks = mySkarabox.deploy-rs.checks self.deploy;
      };
    });
}
