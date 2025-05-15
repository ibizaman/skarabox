# SkaraboxOS

[![build](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml/badge.svg)](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml)

SkaraboxOS aims to be the fastest way to install NixOS on a server
with all batteries included.

<!--toc:start-->
- [Why?](#why)
- [Hardware Requirements](#hardware-requirements)
- [Installation Process Overview](#installation-process-overview)
- [Architecture](#architecture)
- [Contribute](#contribute)
- [Links](#links)
<!--toc:end-->

TL; DR:

```bash
mkdir myskarabox
cd myskarabox
nix run github:ibizaman/skarabox#init

# Tweak settings to match installing on a target host
echo 127.0.0.1 > ip
echo x86_64-linux > system
nix run .#gen-knownhosts-file

# More tweaks to install on a VM (for testing)
echo 2222 > ssh_port
echo 2223 > ssh_boot_port

nix run .#beacon-vm &
nix run .#ssh -- -o StrictHostKeyChecking=no sudo nixos-facter > facter.json
nix run .#install-on-beacon .#skarabox
# VM will reboot.

# Installation is done!
```

Normal operations:

```
# Decrypt root partition:
nix run .#unlock

# SSH in:
nix run .#ssh

# Make a change to ./configuration.nix then deploy:
nix run .#activate

# Reboot:
nix run .#ssh sudo reboot
```

The flake [template](./template) combines:
- Creating a bootable ISO, installable on an USB key.
- Alternatively, creating a VM based on the bootable ISO
  to test the installation procedure (like shown in the snippet above).
- Managing host keys, known hosts and ssh keys
  to provide a secure and seamless SSH experience.
- [nixos-anywhere][] to install NixOS headlessly.
- [disko][] to format the drives using native ZFS encryption with remote unlocking through ssh.
  It supports for the OS 1 or 2 disks in raid 1
  and for the data 0 or 2 disks in raid1.
- [nixos-facter][] to handle hardware configuration.
- [sops-nix][] to handle secrets: the user's password and the root and data ZFS pool passphrases.
- [deploy-rs][] to deploy updates.
- backed by [tests][] and [CI][] to make sure the installation procedure does work!
  Why don't you run them yourself: `nix run github:ibizaman/skarabox#checks.x86_64-linux.template -- -g`.
- and supporting `x86_64-linux` and `aarch64-linux` platform.

I used this successfully on my own on-premise x86 server
and on Hetzner dedicated ARM and x86 hosts.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml

This repository does not invent any of those wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

## Why?

Because the landscape of installing NixOS could be better
and this repository is an attempt at that.

By the way, the name SkaraboxOS comes from the scarab (the animal),
box (for the server) and OS (for Operating System).
Scarab is spelled with a _k_ because it's kool.
A scarab is a _very_ [strong][] animal representing well what this repository's intention.

[strong]: https://en.wikipedia.org/wiki/Dung_beetle#Ecology_and_behavior

## Hardware Requirements

SkaraboxOS is currently tailored for NAS users, not necessarily homelab users.
It expects a particular hardware layout:

- 1 or 2 SSD or NVMe drive for the OS.
  If 2, they will be formatted in Raid 1 (mirror) so each hard drive should have the same size.
- 0 or 2 Hard drives that will store data.
  Capacity depends on the amount of data that will be stored.
  If 2, they will too be formatted in Raid 1.

> [!WARNING]
> The disks will be formatted and completely wiped out of data.

## Installation Process Overview

The TL; DR: snippet in words:

1. Download the flake template
   which automatically generates secrets.
2. Generate a ISO and format a USB key.
3. Boot server on USB key and get its IP address.
4. Run installer from laptop.
   Server will reboot and ask for passphrase to decrypt root partition.
5. SSH in to decrypt root partition.
6. Server boots and you can SSH in.

The [template's README](./template/README.md) contains a more detailed explanation.

Services can then be installed by using NixOS options directly
or through [Self Host Blocks](https://github.com/ibizaman/selfhostblocks).
The latter, similarly to SkaraboxOS, provides an opinionated way to configure services in a seamless way.

## Architecture

The [Architecture][] document covers how all pieces fit together.

[Architecture]: ./docs/architecture.md

## Contribute

Contributions are very welcomed!

To push to the cache, run for example:

```
nix build --no-link --print-out-paths .#packages.x86_64-linux.beacon-vm  \
  | nix run nixpkgs#cachix push selfhostblocks
```

## Links

- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/cd-dvd/installation-cd-base.nix
- https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/no-os.md#installing-on-a-machine-with-no-operating-system
