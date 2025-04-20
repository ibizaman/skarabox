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
   Server will reboot and ask for passphrase to decrypt root partition.
5. SSH in to decrypt root partition.
6. Server boots and you can SSH in.

At the end of the process, the server will:
- Have an encrypted ZFS root partition using the NVMe drive, unlockable remotely through ssh.
- Have an encrypted ZFS data hard drives.
- Be accessible through ssh for administration and updates.

See [Installation](./template/README.md#installation) section for detailed process.

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
