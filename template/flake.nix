{
  description = "Example flake.nix for skarabox.";

  inputs = {
    skarabox.url = "github:ibizaman/skarabox";
  };

  outputs = { self, skarabox }:
    let
      nixpkgs = skarabox.inputs.selfhostblocks.inputs.nixpkgs;
    in
    {
      nixosModules.skarabox = {
        imports = [
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

      nixosConfigurations.skarabox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.skarabox
        ];
      };
    };
}
