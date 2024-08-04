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

      nixosConfigurations.skarabox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.skarabox
        ];
      };
    };
}
