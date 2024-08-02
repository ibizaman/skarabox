{
  description = "Example flake.nix for skarabox.";

  inputs = {
    skarabox.url = "github:ibizaman/skarabox";
  };

  outputs = { skarabox, ... }:
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
            skarabox.disks.rootReservation = "100G";
            skarabox.hostId = "2f44b40a";
          })
        ];
      };
    };
}