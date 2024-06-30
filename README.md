# SkaraboxOS

SkaraboxOS is an opinionated and simplified headless NixOS installation for a server geared towards
self-hosting applications and services. Upon installation, it will format the drives and install
[Self Host Blocks][SHB].

[SHB]: https://github.com/ibizaman/selfhostblocks

## Hardware Requirements

SkaraboxOS expects a certain hardware layout of the server:
- 1 SSD or NVMe drive for the OS. 500Gb or more.
- 2 Hard drives that will store data.
  Capacity depends on the amount of data that will be stored.
  They will be formatted in Raid 1 (mirror) so each hard drive should have the same size.
- 16Gb or more of RAM.
- AMD or Intel CPU with embedded graphics.
  (Personally using AMD Ryzen 5 5600G with great success).
- *Work In Progress* Optional graphics card.
  Only needed for speech to text applications like for Home Assistant.
- Internet access is optional.
  It is only required:
  - for updates;
  - for accessing services from outside the LAN;
  - for federation (to share documents or pictures across the internet).

**WARNING: The 3 disks will be formatted and completely wiped out of data.**

## Installation Process Overview

The process requires to format a USB key.
The server will need to be booted on that key.

As the server is headless, an external device - laptop or desktop - is required
to complete the installation process.
This device will later be used to administer SkaraboxOS
and will contain all required passwords.
Other devices can then be configured to administer SkaraboxOS.

Services offered by SkaraboxOS will be accessible from any device - laptop, desktop or smartphone -
connected in the same LAN as the server or, if configured, from anywhere on the internet.

At the end of the process, the server will:
- have an encrypted ZFS root partition using the NVMe drive, unlockable remotely through ssh.
- have an encrypted ZFS data hard drives.
- be accessible through ssh for administration.
- have Self Host Blocks installed.

## Caution

Following the steps WILL ERASE THE CONTENT of any disk on that server.

## Usage

1. Boot on the NixOS installer. You just need to boot, no need to install.

   1. First, create the .iso file.

   ```
   nix build github:ibizaman/skarabox#beacon
   ```

   2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```
   nix run nixpkgs#usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

   3. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

   4. Note down the IP address of the server. For that, follow the steps that appeared when booting
      on the USB stick.

2. Connect to the installer and install

   1. Create a file somewhere containing a long passphrase (must be more than 8 characters) that
      will be used to encrypt the disk. This means you will need to provide this passphrase every
      time you boot up the server.

   2. Run the following command, replacing `<path/to/passphrase>` with where you saved the file in
      the previous step and `<ip>` with the IP address you got in the previous step.

   ```
   nix run github:nix-community/nixos-anywhere -- \
     --flake '.#remote-installer' \
     --ssh-option "IdentitiesOnly=yes" \
     --disk-encryption-keys /tmp/disk.key <path/to/passphrase> \
     nixos@<ip>
   ```

   You will be prompted for a password, enter "skarabox123" without the double quotes.

## Contribute

To start a VM with the beacon, run:

```
nix run .#beacon-test
```

To test the installer, run:

```
nix run github:nix-community/nixos-anywhere -- --flake .#installer --vm-test
```

## Links

- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/cd-dvd/installation-cd-base.nix
- https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/no-os.md#installing-on-a-machine-with-no-operating-system
