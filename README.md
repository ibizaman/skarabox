# SkaraboxOS

[![build](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml/badge.svg)](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml)

SkaraboxOS aims to be the fastest way to install NixOS on a server
with all batteries included.

<!--toc:start-->
- [Usage](#usage)
- [Provided operations:](#provided-operations)
- [Why?](#why)
- [Hardware Requirements](#hardware-requirements)
- [Architecture](#architecture)
- [Roadmap](#roadmap)
- [Contribute](#contribute)
- [Links](#links)
<!--toc:end-->

## Usage

<table>
<tr>
<th colspan="6">1. Initialize repo</th>
</tr>
<tr>
<th colspan="3">1.a. From scratch</th>
<th colspan="3">1.b. In existing repo</th>
</tr>
<tr>
<td colspan="3">

```bash
mkdir myskarabox
cd myskarabox
nix run github:ibizaman/skarabox#init
```
</td>
<td colspan="3">

1. Merge [./template/flake.nix](./template/flake.nix) with yours.
2. Create Sops main key `sops.key` if needed:

   `nix run .#sops-create-main-key`.
3. Add Sops main key to Sops config `.sops.yaml`:

   `nix run .#sops-add-main-key`.
4. Create config for host `myskarabox` in folder `./myskarabox`:

   `nix run .#gen-new-host myskarabox`.

</td>
</tr>

<tr>
<th colspan="6">2. Start beacon</th>
</tr>
<tr>
<th colspan="2">2.a. Test on VM</th>
<th colspan="2">2.b. Install on Host</th>
<th colspan="2">2.c. Install on Cloud Instance</t0>
</tr>
<tr>
<td colspan="2">

```bash
nix run .#myskarabox-beacon-vm &

echo 127.0.0.1 > myskarabox/ip
echo x86_64-linux > myskarabox/system
echo 2222 > myskarabox/ssh_port
echo 2223 > myskarabox/ssh_boot_port
nix run .#myskarabox-gen-knownhosts-file
```
</td>
<td colspan="2">

Use usbimager to install
`./result/iso/beacon.iso` on a USB key
and boot on the USB key.

```bash
nix build .#myskarabox-beacon
nix run .#beacon-usbimager
```

Then burn on an USB key
then boot on USB key.

```bash
echo 192.168.1.XX > myskarabox/ip
echo x86_64-linux > myskarabox/system
nix run .#myskarabox-gen-knownhosts-file
```

</td>
<td colspan="2">
For Hetzner, start in recovery mode.

```nix
echo 192.168.1.XX > myskarabox/ip
echo x86_64-linux > myskarabox/system
nix run .#myskarabox-gen-knownhosts-file
```
</td>
</tr>
<tr>
<td colspan="6">3. Install on target host</td>
</tr>

<tr>
<td colspan="6">

```bash
nix run .#myskarabox-get-facter > ./myskarabox/facter.json
nix run .#myskarabox-install-on-beacon .#myskarabox
```

VM or target host will reboot and ask the passphrase to decrypt
the root partition. 

</td>
</tr>
</table>

## Provided operations:

```
# Decrypt root partition:
nix run .#myskarabox-unlock

# SSH in:
nix run .#myskarabox-ssh

# Deploy changes if any:
nix run .#deloy-rs

# Edit Sops file:
nix run .#sops ./myskarabox/secrets.yaml

# Reboot:
nix run .#myskarabox-ssh sudo reboot
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
- [flake-parts][] to make the resulting `flake.nix` small.
  Also to handle having multiple hosts managed by one flake.
- [sops-nix][] to handle secrets: the user's password and the root and data ZFS pool passphrases.
- Programmatically populate Sops secrets file.
- Fully pinned inputs.
- [deploy-rs][] to deploy updates.
- Backed by [tests][] and [CI][] to make sure the installation procedure does work!
  Why don't you run them yourself: `nix run github:ibizaman/skarabox#checks.x86_64-linux.template -- -g`.
- Supporting `x86_64-linux` and `aarch64-linux` platform.

I used this successfully on my own on-premise x86 server
and on Hetzner dedicated ARM and x86 hosts.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[flake-parts]: https://flake.parts/
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml

This repository does not invent any of those wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

Services can then be installed by using NixOS options directly
or through [Self Host Blocks](https://github.com/ibizaman/selfhostblocks).
The latter, similarly to SkaraboxOS, provides an opinionated way to configure services in a seamless way.

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

## Architecture

The [Architecture][] document covers how all pieces fit together.

[Architecture]: ./docs/architecture.md

## Roadmap

All ideas are noted in [issues][]
and prioritized issues can be found in the [milestones][].

[issues]: https://github.com/ibizaman/skarabox/issues
[milestones]: https://github.com/ibizaman/skarabox/milestones

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
