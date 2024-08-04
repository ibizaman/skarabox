{
  description = "Example flake.nix for skarabox.";

  inputs = {
    skarabox.url = "github:ibizaman/skarabox";

    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, skarabox, deploy-rs }:
    let
      nixpkgs = skarabox.inputs.selfhostblocks.inputs.nixpkgs;

      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # Taken from https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
      deployPkgs = import nixpkgs {
        inherit system;
        overlays = [
          deploy-rs.overlay
          (self: super: { deploy-rs = { inherit (pkgs) deploy-rs; lib = super.deploy-rs.lib; }; })
        ];
      };

      ip = "<replace me>";
    in
    {
      nixosModules.skarabox = {
        imports = [
          skarabox.nixosModules.skarabox
          ({ config, ... }: {
            skarabox.hostname = "skarabox";
            skarabox.username = "skarabox";
            skarabox.disks.rootDisk = "/dev/nvme0n1";
            # 10% of size SSD
            skarabox.disks.rootReservation = "100G";
            skarabox.disks.dataDisk1 = "/dev/sda";
            skarabox.disks.dataDisk2 = "/dev/sdb";
            # 5% of size Hard Drives
            skarabox.disks.dataReservation = "500G";
            skarabox.sshAuthorizedKeyFile = ./ssh_skarabox.pub;
            skarabox.hostId = builtins.readFile ./hostid;
            # Needed to be able to ssh to decrypt the SSD.
            boot.initrd.availableKernelModules = [
              "rtw88_8821ce"
              "r8169"
            ];
          })
          ./configuration.nix
        ];
      };

      # Used with nixos-anywere for installation.
      nixosConfigurations.skarabox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.skarabox
        ];
      };

      # Used with deploy-rs for updates.
      deploy.nodes.skarabox = {
        hostname = ip;
        sshUser = "skarabox";
        sshOpts = [ "-o" "IdentitiesOnly=yes" "-i" "ssh_skarabox" ];
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
}
