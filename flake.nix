{
  description = "Skarabox's flake to install NixOS";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
  };

  outputs = inputs@{ self, flake-parts, nixpkgs, nixos-generators, nixos-anywhere, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    perSystem = { self', pkgs, system, ... }: {
      packages = {
        beacon = nixos-generators.nixosGenerate {
          inherit system;
          format = "install-iso";

          modules = [
            ./modules/beacon.nix
          ];
        };

        beacon-vm = let
          pkgs = import nixpkgs {
            inherit system;
          };
          iso = "${self'.packages.beacon}/iso/beacon.iso";
          hostSshPort = 2222;
          nixos-qemu = pkgs.callPackage "${pkgs.path}/nixos/lib/qemu-common.nix" {};
          qemu = nixos-qemu.qemuBinary pkgs.qemu;
        in (pkgs.writeShellScriptBin "runner.sh" ''
          [ ! -f disk1.qcow2 ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 disk1.qcow2 20G
          [ ! -f disk2.qcow2 ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 disk2.qcow2 20G
          [ ! -f disk3.qcow2 ] && ${pkgs.qemu}/bin/qemu-img create -f qcow2 disk3.qcow2 20G
          ${qemu} \
            -m 2048M \
            -nic hostfwd=tcp::${toString hostSshPort}-:22 \
            --drive media=cdrom,format=raw,readonly=on,file=${iso} \
            --drive id=disk1,format=qcow2,if=virtio,file=disk1.qcow2 \
            --drive id=disk2,format=qcow2,if=virtio,file=disk2.qcow2 \
            --drive id=disk3,format=qcow2,if=virtio,file=disk3.qcow2 \
            $@
          '');

        install-on-beacon-vm = let
          pkgs = import nixpkgs {
            inherit system;
          };
          hostSshPort = 2222;
        in (pkgs.writeShellScriptBin "runner.sh" ''
          ${nixos-anywhere.packages.${system}.nixos-anywhere}/bin/nixos-anywhere \
            --flake .#vm-test \
            --disk-encryption-keys /tmp/root_passphrase <(echo rootpassphrase) \
            --disk-encryption-keys /tmp/data_passphrase <(echo datapassphrase) \
            --ssh-port ${toString hostSshPort} \
            nixos@127.0.0.1
        '');
      };

      apps = {
        nixos-anywhere = {
          type = "app";
          program = "${nixos-anywhere.packages.${system}.nixos-anywhere}/bin/nixos-anywhere";
        };
      };
    };

    flake = {
      templates = {
        skarabox = {
          path = ./template;
          description = "Skarabox template";
        };

        default = self.templates.skarabox;
      };


      nixosModules.skarabox = {
        imports = [
          nixos-anywhere.inputs.disko.nixosModules.disko
          ./modules/disks.nix
          ./modules/configuration.nix
        ];
      };

      # Module with some test preset that match the beacon-vm.
      nixosModules.vm-test = {
        imports = [
          self.nixosModules.skarabox
        ];

        skarabox.hostname = "skarabox";
        skarabox.username = "skarabox";
        skarabox.disks.rootDisk = "/dev/vda";
        skarabox.disks.rootReservation = "500M";
        skarabox.disks.enableDataPool = true;
        skarabox.disks.dataDisk1 = "/dev/vdb";
        skarabox.disks.dataDisk2 = "/dev/vdc";
        skarabox.disks.dataReservation = "10G";
        skarabox.hostId = "12345678";
      };

      nixosConfigurations.vm-test = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.vm-test
        ];
      };
    };
  };
}
