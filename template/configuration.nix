# This is a NixOS Module.
#
# More info at:
# - https://wiki.nixos.org/wiki/NixOS_modules
# - https://nixos.org/manual/nixos/stable/#sec-writing-modules
{ lib, ... }:
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
      skarabox.disks.rootDisk = "/dev/nvme0n1";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.rootDisk2 = null;  # Set a value only if you have a second disk for the root partition.
      skarabox.disks.rootReservation = "100G";  # Set to 10% of size SSD.
      skarabox.disks.dataDisk1 = "/dev/sda";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.dataDisk2 = "/dev/sdb";  # Update with result of running `fdisk -l` on the USB stick.
      skarabox.disks.enableDataPool = true;  # Disable if only an SSD for root is present.
      skarabox.disks.dataReservation = "500G";  # Set to 5% of size Hard Drives.
      skarabox.sshAuthorizedKeyFile = ./ssh_skarabox.pub;
      skarabox.hostId = builtins.readFile ./hostid;

      hardware.enableAllHardware = true;
      boot.initrd.network.ssh.port = 2222;

      sops.defaultSopsFile = ./secrets.yaml;
      sops.age = {
        sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      };
    }
    # Your config
    {
    }
  ];
}
