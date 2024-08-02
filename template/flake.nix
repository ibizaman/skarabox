{
  description = "Example flake.nix for skarabox.";

  inputs = {
    skarabox.url = "github:ibizaman/skarabox";
  };

  outputs = { self, skarabox }:
    let
      system = "x86_64-linux";

      nixpkgs = skarabox.inputs.selfhostblocks.inputs.nixpkgs;
    in
    {
      nixosConfigurations.skarabox = nixpkgs.lib.nixosSystem {
        modules = [
          skarabox.nixosModules.skarabox
          ({ config, ... }: {
            skarabox.hostname = "skarabox";
            skarabox.username = "skarabox";
            skarabox.disks.rootDisk = "/dev/sda";
            # 10% of size SSD
            skarabox.disks.rootReservation = "100G";
            # Generate me with `uuidgen | head -c 8`
            skarabox.hostId = "<generate me>";
          })
        ];
      };

      nixosConfigurations.remote-installer = let
        system = "x86_64-linux";
        pkgs = import nixpkgs {
          inherit system;
        };
      in nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.skarabox
        ];
      };
    };
}
