# SkaraboxOS

SkaraboxOS is an opinionated and simplified headless NixOS installer.

It provides a flake [template](./template) which combines:
- Creating a bootable ISO, installable on an USB key.
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to install NixOS headlessly.
- [disko](https://github.com/nix-community/disko) to format the drives using native ZFS encryption with remote unlocking through ssh.
- [sops-nix](https://github.com/Mic92/sops-nix) to handle secrets.
- [deploy-rs](https://github.com/serokell/deploy-rs) to deploy updates.
- Which supports x86_64 and aarch64 platform.

This repository does not invent any of those wonderful tools.
It merely provides an opinionated way to make them all fit together for a seamless experience.

It has a [demo](#demo) which lets you install SkaraboxOS on a VM!
The demo even has a screencast.

## Why?

Because the landscape of installing NixOS could be better and this repository is an attempt at that.
By being more opinionated, it allows you to get set up faster.

By the way, the name SkaraboxOS comes from the scarab (the animal), box (for the server) and OS (for Operating System).
Scarab is spelled with a _k_ because it's kool.
A scarab is a _very_ [strong](https://en.wikipedia.org/wiki/Dung_beetle#Ecology_and_behavior) animal representing well what this repository's intention.

## Hardware Requirements

SkaraboxOS expects a particular hardware layout:

- 1 or 2 SSD or NVMe drive for the OS.
  If 2, they will be formatted in Raid 1 (mirror) so each hard drive should have the same size.
- 0 or 2 Hard drives that will store data.
  Capacity depends on the amount of data that will be stored.
  If 2, they will too be formatted in Raid 1.
<!--
This is for Self Host Blocks.

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
-->

**WARNING: The disks will be formatted and completely wiped out of data.**

## Installation Process Overview

1. Download the flake template
   which automatically generates secrets.
2. Generate a ISO and format a USB key.
3. Boot server on USB key and get its IP address.
4. Run installer from laptop.
5. Done!

At the end of the process, the server will:
- Have an encrypted ZFS root partition using the NVMe drive, unlockable remotely through ssh.
- Have an encrypted ZFS data hard drives.
- Be accessible through ssh for administration and updates.

Services can then be installed by using NixOS options directly or through [Self Host Blocks](https://github.com/ibizaman/selfhostblocks).
The latter, similarly to SkaraboxOS, provides an opinionated way to configure services in a seamless way.

## Caution

Following the steps WILL ERASE THE CONTENT of any disk on that server.

## Demo

This demo will install SkaraboxOS on a VM locally on your computer.
The VM has 3 hard drives, one for the OS
and two in raid 1 for the data.

Here's a screencast of it:

[![Screencast of the steps outlined in the demo](https://img.youtube.com/vi/pXuKwhtC-0I/0.jpg)](https://www.youtube.com/watch?v=pXuKwhtC-0I)

Launch the VM that listens on ports 2222 for normal ssh access
and 2223 for ssh access during boot:

```bash
nix run github:ibizaman/skarabox#demo-beacon 2222 2223
```

_Compared to the real installation, this step replaces installing
the beacon on an USB key and booting on it._

When the installer did boot up and you see the `[nixos@nixos:~]$` prompt,
install SkaraboxOS on the VM with:

```bash
nix run github:ibizaman/skarabox#install-on-beacon 127.0.0.1 2222 github:ibizaman/skarabox
```

Then when the system reboots - actually every time it will boot -
you will be prompted with `Enter passphrase for 'root'` which
waits for the passphrase to decrypt the root partition.
The password is `rootpassphrase` (yes, I know, it's original :D).
but don't enter it through the VM, we can ssh in to enter it:

```bash
printf "rootpassphrase" | nix run github:ibizaman/skarabox#beacon-ssh 127.0.0.1 2223 root
```

When that's done, the boot up will continue and you will see the prompt
`skarabox login`. Enter `skarabox` as username and `skarabox123` as password.

Now you're logged into the VM on a brand new SkaraboxOS installation!

You can test accessing through ssh with:

```
nix run github:ibizaman/skarabox#beacon-ssh 127.0.0.1 2222
```

## Installation

1. Create a directory and download the template.

```bash
$ mkdir myskarabox
$ cd myskarabox
$ nix flake init --template github:ibizaman/skarabox
```

2. Boot on the NixOS installer. You just need to boot, there is nothing to install just yet.

   1. First, create the .iso file.

   ```bash
   $ nix build .#beacon
   ```

   2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run .#usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

   3. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

   4. Note down the IP address and disk layout of the server.
      For that, follow the steps that appeared when booting on the USB stick.
      To reprint the steps, run the command `skarabox-help`.

   5. Open the `configuration.nix` file and tweak values to match you hardware.
      Also, open the other files and see how to generate them too.
      All the instructions are included.

   Note the `root_passphrase` file will contain a passphrase that will need to be provided every time the server boots up.

3. Run the installation process

   1. Run the following command replacing `<ip>` with the IP address you got in the previous step.

   ```bash
   $ nix run .#install-on-beacon <ip> 22 .#skarabox
   ```

   2. The server will reboot into NixOS on its own.

   3. Decrypt the SSD and the Hard Drives.

   Run the following command.

   ```bash
   $ nix run .#boot-ssh
   ```

   You will be prompted to enter the root passphrase.
   Copy the content of the `root_passphrase` file and paste it and press Enter.
   No `*` will appear upon pasting but just press Enter.

   ```bash
   Enter passphrase for 'root':
   ```

   The connection will disconnect automatically.
   This is normal behavior.

   ```bash
   Connection to <ip> closed.
   ```

   Now, the hard drives are decrypted and the server continues to boot.

   It's a good idea to make sure you can SSH in correctly, at least the first time:

   ```bash
   nix run .#ssh
   ```

## Normal Operations

Those can be found in the template's [readme](./template/README.md).

## Contribute

Contributions are very welcomed!

To push to the cache, run for example:

```
nix build --no-link --print-out-paths .#packages.x86_64-linux.demo-beacon  \
  | nix run nixpkgs#cachix push selfhostblocks
```

## Links

- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/cd-dvd/installation-cd-base.nix
- https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/no-os.md#installing-on-a-machine-with-no-operating-system
