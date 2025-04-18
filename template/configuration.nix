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
      skarabox.setupLanWithDHCP = true;  # Set to false to disable the catch-all network configuration from skarabox and instead set your own

      # This setting is needed if the ssh server does not start on boot in stage-1,
      # to decrypt the root partition.
      # If not, to find out which driver you need, run on the machine you want to install:
      #   nix shell nixpkgs#pciutils --command lspci -v | grep -iA8 'network\|ethernet'
      # Running this command works if you boot the server on the beacon too.
      # For example: skarabox.disks.networkCardKernelModules = [ "e1000" ];
      # skarabox.disks.networkCardKernelModules = [  ];

      # You can remove this line and enable firmwares one by one
      # but only do this if you know what you're doing.
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
