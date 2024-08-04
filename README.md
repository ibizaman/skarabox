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

### Installation

1. Boot on the NixOS installer. You just need to boot, no need to install.

   1. First, create the .iso file.

   ```bash
   $ nix build github:ibizaman/skarabox#beacon
   ```

   2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run nixpkgs#usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

   3. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

   4. Note down the IP address of the server. For that, follow the steps that appeared when booting
      on the USB stick.

2. Connect to the installer and install

   1. Create a directory and download the template.

   ```bash
   $ mkdir myskarabox
   $ cd myskarabox
   $ nix flake init --template github:ibizaman/skarabox
   ```

   2. Open the new `flake.nix` file and generate whatever it needs.
   Also, open the other files and see how to generate them too.

   Note the root_passphrase file will contain a passphrase that will need to be provided every time the server boots up.

   3. Run the following command replacing `<ip>` with the IP address you got in the previous step.

   ```bash
   $ nix run github:nix-community/nixos-anywhere -- \
     --flake .#skarabox' \
     --ssh-option "IdentitiesOnly=yes" \
     --disk-encryption-keys /tmp/root_passphrase root_passphrase \
     --disk-encryption-keys /tmp/data_passphrase data_passphrase \
     nixos@<ip>
   ```

   You will be prompted for a password, enter "skarabox123" without the double quotes.

   4. The server will reboot into NixOS on its own.

   5. Decrypt the SSD and the Hard Drives.

   Run the following command.

   ```bash
   $ ssh -p 2222 root@<ip> -o IdentitiesOnly=yes -i ssh_skarabox
   ```

   It will prompt you a first time to verify the key fingerprint.

   ```bash
   The authenticity of host '[<ip>]:2222 ([<ip>]:2222)' can't be established.
   ED25519 key fingerprint is SHA256:<redacted>.
   This key is not known by any other names.
   Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```

   Just enter `"yes"` followed by pressing on the Enter key.
   Next time the server will boot, you will not need to do this step.

   ```bash
   Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
   Warning: Permanently added '[<ip>]:2222' (ED25519) to the list of known hosts.
   ```

   You will be prompted a second time, this time to enter the root passphrase.
   Copy paste the content of the `root_passphrase` file and paste it and press Enter.
   No `*` will appear upon pasting but just press Enter.

   ```bash
   Enter passphrase for 'root':
   ```

   The connection will disconnect automatically.

   ```bash
   Connection to <ip> closed.
   ```

   Now, the hard drives are decrypted and the server continues to boot.

   It's a good idea to make sure you can login correctly, at least the first time.
   See next section.

### Normal Operations

   1. Login

   ```bash
   $ ssh -p 22 skarabox@<ip> -o IdentitiesOnly=yes -i ssh_skarabox
   ```

   2. Deploy an Update

   Modify the `./configuration.nix` file then run:

   ```bash
   nix run nixpkgs#deploy-rs
   ```

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
