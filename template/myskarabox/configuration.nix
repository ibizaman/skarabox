# This is a NixOS Module.
#
# More info at:
# - https://wiki.nixos.org/wiki/NixOS_modules
# - https://nixos.org/manual/nixos/stable/#sec-writing-modules
{ lib, config, ... }:
let
  inherit (lib) mkMerge;
in
{
  imports = [
  ];

  options = {
  };

  config = mkMerge [
    # Skarabox config. Update the values to match your hardware.
    {
      skarabox.hostname = "skarabox";
      skarabox.username = "skarabox";
      skarabox.hashedPasswordFile = config.sops.secrets."skarabox/user/hashedPassword".path;
      skarabox.facter-config = ./facter.json;
      skarabox.disks.rootDisk = "/dev/nvme0n1";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.rootDisk2 = null;  # Set a value only if you have a second disk for the root partition.
      skarabox.disks.rootReservation = "500M";  # Set to 10% of size SSD.
      skarabox.disks.dataDisk1 = "/dev/sda";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.dataDisk2 = "/dev/sdb";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.enableDataPool = true;  # Disable if only an SSD for root is present.
      skarabox.disks.dataReservation = "10G";  # Set to 5% of size Hard Drives.
      # For security by obscurity, we choose another ssh port here than the default 22.
      skarabox.disks.bootSSHPort = lib.toInt (builtins.readFile ./ssh_boot_port);
      skarabox.sshPorts = [ (lib.toInt (builtins.readFile ./ssh_port)) ];
      skarabox.sshAuthorizedKeyFile = ./ssh_skarabox.pub;
      skarabox.hostId = lib.trim (builtins.readFile ./hostid);
      skarabox.setupLanWithDHCP = true;  # Set to false to disable the catch-all network configuration from skarabox and instead set your own

      # Hardware drivers are figured out using nixos-facter.
      # If it still fails to find the correct driver,
      # run the following command on the host:
      #   nix shell nixpkgs#pciutils --command lspci -v | grep -iA8 'network\|ethernet'
      # then uncomment the following line
      # and replace the driver with the one obtained above.
      boot.initrd.availableKernelModules = [
        # "r8169" # this is an example
      ];
      # The following catch-all option is worth enabling too
      # if some drivers are missing.
      hardware.enableAllHardware = false;

      sops.defaultSopsFile = ../secrets.yaml;
      sops.age = {
        sshKeyPaths = [ "/boot/host_key" ];
      };

      sops.secrets."skarabox/user/hashedPassword" = {
        # Keep this option true or the user will not be able to log in.
        # https://github.com/Mic92/sops-nix?tab=readme-ov-file#setting-a-users-password
        neededForUsers = true;
      };
      sops.secrets."skarabox/disks/rootPassphrase" = {};
      sops.secrets."skarabox/disks/dataPassphrase" = {};
    }
    # Your config
    {
    }
  ];
}
