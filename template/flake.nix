{
  description = "Flake for skarabox.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    skarabox.url = "github:ibizaman/skarabox";
    skarabox.inputs.nixpkgs.follows = "nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";

    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, skarabox, sops-nix, deploy-rs }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    perSystem = { inputs', pkgs, ... }: {
      packages = {
        inherit (inputs'.skarabox.packages) beacon demo-beacon install-on-beacon beacon-ssh;

        inherit (inputs'.nixpkgs.legacyPackages) age usbimager util-linux ssh-to-age sops openssl;

        # nix run .#boot-ssh [<command> ...]
        # nix run .#boot-ssh
        # nix run .#boot-ssh echo hello
        boot-ssh = pkgs.writeShellScriptBin "ssh.sh" ''
        ${inputs'.skarabox.packages.ssh}/bin/ssh.sh \
          "${builtins.readFile ./ip}" \
          "${builtins.readFile ./ssh_boot_port}" \
          root \
          $@
        '';

        # nix run .#ssh [<command> ...]
        # nix run .#ssh
        # nix run .#ssh echo hello
        ssh = pkgs.writeShellScriptBin "ssh.sh" ''
        ${inputs'.skarabox.packages.ssh}/bin/ssh.sh \
          "${builtins.readFile ./ip}" \
          "${builtins.readFile ./ssh_port}" \
          ${self.nixosConfigurations.skarabox.config.skarabox.username} \
          $@
        '';
      };

      apps = {
        deploy = inputs.deploy-rs.apps.x86_64-linux.deploy-rs;
      };
    };

    flake = let
      system = builtins.readFile ./system;
    in {
      nixosModules.skarabox = {
        imports = [
          skarabox.nixosModules.skarabox
          sops-nix.nixosModules.default
          ./configuration.nix
        ];
      };

      # Used with nixos-anywere for installation.
      nixosConfigurations.skarabox = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.skarabox
        ];
      };

      # Used with deploy-rs for updates.
      deploy.nodes.skarabox = let
        pkgs = import nixpkgs { inherit system; };

        # Taken from https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
        deployPkgs = import nixpkgs {
          inherit system;
          overlays = [
            deploy-rs.overlay
            (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
          ];
        };
      in {
        hostname = builtins.readFile ./ip;
        sshUser = self.nixosConfigurations.skarabox.config.skarabox.username;
        sshOpts = [ "-o" "IdentitiesOnly=yes" "-i" "ssh_skarabox" "-p" (builtins.readFile ./ssh_port) ];
        profiles = {
          system = {
            user = "root";
            path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.skarabox;
          };
        };
      };
      # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
  };
}
