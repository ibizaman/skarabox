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
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = inputs@{ self, skarabox, sops-nix, nixpkgs, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } (let
    inherit (skarabox.lib) readAndTrim;
    inherit (nixpkgs.lib) toInt;
  in {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    imports = [
      skarabox.flakeModules.default
    ];

    skarabox.hosts = {
      myskarabox = {
        system = readAndTrim ./myskarabox/system;
        hostKeyPub = ./myskarabox/host_key.pub;
        ip = readAndTrim ./myskarabox/ip;
        sshPublicKey = ./myskarabox/ssh.pub;
        knownHosts = ./myskarabox/known_hosts;
        sshPort = toInt (readAndTrim ./myskarabox/ssh_port);
        sshBootPort = toInt (readAndTrim ./myskarabox/ssh_boot_port);

        modules = [
          sops-nix.nixosModules.default
          self.nixosModules.myskarabox
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
