# Skarabox

[![build](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml/badge.svg)](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml)

Skarabox aims to be the fastest way to install NixOS on a server
with all batteries included.

<!--toc:start-->
- [Content](#content)
- [Usage in Brief](#usage-in-brief)
- [Provided operations:](#provided-operations)
- [Architecture](#architecture)
- [Why?](#why)
- [Hardware Requirements](#hardware-requirements)
- [Contribute](#contribute)
- [Funding](#funding)
<!--toc:end-->

## Usage

Skarabox is a flake template which combines three main features
which all work together to provide a seamless NixOS install experience.

Skarabox uses a lot of existing wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

After the installation is done, services can be installed
using NixOS options directly or through [Self Host Blocks][].
The latter, similarly to Skarabox, provides
an opinionated way to configure services in a seamless way.

[Self Host Blocks]: https://github.com/ibizaman/selfhostblocks

### Beacon

To install NixOS on you server, you must be able to first
boot on it. For a cloud install, that's usually easy but
for an on-premise server, you must create a bootable USB key.
That's the goal of the beacon which generates an ISO file
that's writable on an USB key.

On top of just booting up, Skarabox' beacon:
- Assigns a static IP to the beacon which matches the server's IP.
- Creates a WiFi hotspot with SSID "Skarabox".

To test the installation, Skarabox provides a VM beacon
that runs on your laptop and which contains 2 OS drive and 2 data drive,
mimicking the supported disk layout by Skarabox.

### Flake Module

The flake module is used with [flake-parts][] to manage one or more servers
under the [skarabox.hosts option][Flake module options]
and provide commands and packages for each of those.

For example, the `nix run .#gen-new-host <newhost>` command is used to create
the directory structure to manage a new host, including new random secrets.

The flake module:

- Assigns the same values, like IP address, to the [beacon options][] and the [NixOS module options][].
- Creates random host key and ssh key to access the server.
  The host key is used then to populate a known hosts file.
- Create main [SOPS][sops-nix] key.
- Create one `secrets.yaml` SOPS file per host, encrypted by main SOPS key
  and by the corresponding host key.
- Uses fully pinned inputs to avoid incompatible dependency versions.

[flake-parts]: https://flake.parts
[beacon options]: https://installer.skarabox.com/options.html#beacon-options
[NixOS module options]: https://installer.skarabox.com/options.html#skarabox-options
[Flake module options]: https://installer.skarabox.com/options.html#flake-module-options

### NixOS Module

The NixOS module provides features useful during installation
and also afterwards:

- [nixos-anywhere][] to install NixOS headlessly.
- [disko][] to format the drives using native ZFS encryption.
- Remote root pool decryption through ssh.
- Disk mirroring: 1 or 2 disks in raid1 using ZFS mirroring for the OS,
  boot partition is then mirrored using grub mirrored devices
  and 0 or 2 disks in raid1 using ZFS mirroring for the data disks.
- Backed by [tests][] for all disk variants
  and [CI][] to make sure the installation procedure does work!
  Why don't you try them yourself: `nix run github:ibizaman/skarabox#checks.x86_64-linux.oneOStwoData -- -g`.
- [nixos-facter][] to handle hardware configuration.
- [sops-nix][] to handle secrets: the user's password and the root and data ZFS pool passphrases.
- Use [deploy-rs][] or [colmena][] to deploy updates.
- Configures DHCP or static IP for host.
- Supports `x86_64-linux` and `aarch64-linux` platform.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[colmena]: https://github.com/zhaofengli/colmena
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml

## Current State

The code is pretty robust, especially thanks to the tests.
I used Skarabox successfully on my own on-premise x86 server
and on Hetzner dedicated ARM and x86 hosts.

## Manual

The manual can be found [online][manual]
It includes some pretty extensive [recovery][] instructions
and an [architecture][] document explaining the inner workings
of Skarabox.

[manual]: https://installer.skarabox.com
[recovery]: https://installer.skarabox.com/recovery.html
[architecture]: https://installer.skarabox.com/architecture.html

## Usage in Brief

1. Initialize repo either from scratch or in an existing repo.
2. Start beacon either in a VM for testing or install on an on-premise host
   or even on a cloud instance.
3. Install on target host.

Afterwards, commands are provided for common operations:

```bash
# Decrypt root partition:
nix run .#myskarabox-unlock

# SSH in:
nix run .#myskarabox-ssh

# Deploy changes:
nix run .#deploy-rs
# or
nix run .#colmena

# Edit Sops file:
nix run .#sops ./myskarabox/secrets.yaml

# Reboot:
nix run .#myskarabox-ssh sudo reboot
```

## Why?

Because the landscape of installing NixOS could be better
and this repository is an attempt at that.

By the way, the name Skarabox comes from the scarab (the animal),
box (for the server) and OS (for Operating System).
Scarab is spelled with a _k_ because it's kool.
A scarab is a _very_ [strong][] animal representing well what this repository's intention.

[strong]: https://en.wikipedia.org/wiki/Dung_beetle#Ecology_and_behavior

## Hardware Requirements

Skarabox is currently tailored for NAS users, not necessarily homelab users.
It expects a particular hardware layout:

- 1 or 2 SSD or NVMe drive for the OS.
  If 2, they will be formatted in Raid 1 (mirror) so each hard drive should have the same size.
- 0 or 2 Hard drives that will store data.
  Capacity depends on the amount of data that will be stored.
  If 2, they will too be formatted in Raid 1.

> [!WARNING]
> The disks will be formatted and completely wiped out of data.

## Contributing

Contributions are very welcomed, help is wanted in all those areas:

- Use this project to install on an x86 or ARM machine.
  Does everything work fine? Are there UX improvements possible?
- Documentation. Text is hard to read or is missing information?
- Tackle issues. Have an idea on how to fix an issue?
- Refactoring. See something weird in the code? Could it be done better?
- Propose new ideas. Something should be covered but is not?
- Report bugs. Saw an issue? Please do report it.

Issues that are being worked on are labeled with the [in progress][] label.
Before starting work on those, you might want to talk about it in the issue tracker
or in the [matrix][] channel.

[in progress]: https://github.com/ibizaman/skarabox/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22in%20progress%22
[matrix]: https://matrix.to/#/#selfhostblocks:matrix.org

The prioritized issues are those belonging to the [next milestone][milestone].
Those issues are not set in stone and I'd be very happy to solve
an issue an user has before scratching my own itch.

[issues]: https://github.com/ibizaman/skarabox/issues
[milestone]: https://github.com/ibizaman/skarabox/milestones

## Funding

I was lucky to [obtain a grant][nlnet] from NlNet which is an European fund,
under [NGI Zero Core][NGI0],
to work on this project.
This also funds the [Self Host Blocks][] project.

Go apply for a grant too!

[nlnet]: https://nlnet.nl/project/SelfHostBlocks
[NGI0]: https://nlnet.nl/core/

<p>
<img alt="NlNet logo" src="https://nlnet.nl/logo/banner.svg" width="200" />
<img alt="NGI Zero Core logo" src="https://nlnet.nl/image/logos/NGI0Core_tag.svg" width="200" />
</p>
