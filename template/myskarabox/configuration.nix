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
      skarabox.hostname = "myskarabox";
      skarabox.username = "skarabox";
      skarabox.hashedPasswordFile = config.sops.secrets."myskarabox/user/hashedPassword".path;
      skarabox.facter-config = ./facter.json;
      skarabox.disks.rootPool = {
        disk1 = "/dev/nvme0n1";  # Update with result of running `fdisk -l` on the USB stick.
        disk2 = null;  # Set a value only if you have a second disk for the root partition.
        reservation = "500M";  # Set to 10% of size SSD.
      };
      skarabox.disks.dataPool = {
        enable = true;  # Disable if only an SSD for root is present.
        disk1 = "/dev/sda";  # Update with result of running `fdisk -l` on the USB stick.
        disk2 = "/dev/sdb";  # Update with result of running `fdisk -l` on the USB stick.
        reservation = "10G";  # Set to 5% of size Hard Drives.
      };
      # For security by obscurity, we choose another ssh port here than the default 22.
      skarabox.boot = {
        sshPort = ./ssh_boot_port;
      };
      skarabox.sshPort = ./ssh_port;
      skarabox.sshAuthorizedKey = ./ssh.pub;
      skarabox.hostId = ./hostid;

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

      sops.defaultSopsFile = ./secrets.yaml;
      sops.age = {
        sshKeyPaths = [ "/boot/host_key" ];
      };

      sops.secrets."myskarabox/user/hashedPassword" = {
        # Keep this option true or the user will not be able to log in.
        # https://github.com/Mic92/sops-nix?tab=readme-ov-file#setting-a-users-password
        neededForUsers = true;
      };
    }
    # Skarabox network configuration
    {
      # Set to { ip = ./ip; gateway = "192.168.1.1"; } to use static IP instead of DHCP configuration.
      # This will set static IP also during initrd to unlock root partition.
      skarabox.staticNetwork = null;
      # Set to true to disable the network configuration from skarabox and instead set your own.
      skarabox.disableNetworkSetup = false;
    }
    # Your config
    {
    }
  ];
}
