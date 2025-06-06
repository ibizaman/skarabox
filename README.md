# SkaraboxOS

[![build](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml/badge.svg)](https://github.com/ibizaman/skarabox/actions/workflows/build.yaml)

SkaraboxOS aims to be the fastest way to install NixOS on a server
with all batteries included.

<!--toc:start-->
- [Content](#content)
- [Usage](#usage)
- [Provided operations:](#provided-operations)
- [Why?](#why)
- [Hardware Requirements](#hardware-requirements)
- [Architecture](#architecture)
- [Roadmap](#roadmap)
- [Contribute](#contribute)
- [Links](#links)
<!--toc:end-->

## Content

See [usage][] if you're interested in what the commands to get all this look like.

[usage]: #usage

This flake [template](./template) combines turn-key style:

- Creating a bootable ISO, installable on an USB key.
- Alternatively, creating a VM based on the bootable ISO
  to test the installation procedure (like shown in the snippet above).
- Managing host keys, known hosts and ssh keys
  to provide a secure and seamless SSH experience.
- [nixos-anywhere][] to install NixOS headlessly.
- [disko][] to format the drives using native ZFS encryption
- Remote root pool decryption through ssh.
- Disk mirroring: 1 or 2 disks in raid1 using ZFS mirroring for the OS,
  boot partition is then mirrored using grub mirrored devices
  and 0 or 2 disks in raid1 using ZFS mirroring for the data disks.
- [nixos-facter][] to handle hardware configuration.
- [flake-parts][] to make the resulting `flake.nix` small.
- Handle having multiple hosts managed by one flake
  and programmatically add more with generated secrets with one command.
- [sops-nix][] to handle secrets: the user's password and the root and data ZFS pool passphrases.
- Programmatically populate Sops secrets file.
- Fully pinned inputs.
- [deploy-rs][] to deploy updates.
- Backed by [tests][] for all disk variants
  and [CI][] to make sure the installation procedure does work!
  Why don't you run them yourself: `nix run github:ibizaman/skarabox#checks.x86_64-linux.oneOStwoData -- -g`.
- Supporting `x86_64-linux` and `aarch64-linux` platform.
- Some pretty extensive [recovery][] instructions. (Tests yet to be written)

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[flake-parts]: https://flake.parts/
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml
[recovery]: ./template/README.md#recovery

This repository does not invent any of those wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

Services can then be installed by using NixOS options directly
or through [Self Host Blocks][].
The latter, similarly to SkaraboxOS, provides an opinionated way to configure services in a seamless way.

[Self Host Blocks]: https://github.com/ibizaman/selfhostblocks

## Usage

1. Initialize repo

    a. Either from scratch

      ```bash
      mkdir myskarabox
      cd myskarabox
      nix run github:ibizaman/skarabox#init
      ```

    b. Or in existing repo

      Merge [./template/flake.nix](./template/flake.nix) with yours, then:

      ```bash
      # Create Sops main key `sops.key` if needed
      nix run .#sops-create-main-key

      # Add Sops main key to Sops config `.sops.yaml`
      nix run .#sops-add-main-key

      # Create config for host `myskarabox` in folder `./myskarabox`
      nix run .#gen-new-host myskarabox
      ```

2. Start beacon

    a. Either test on VM

     ```bash
     nix run .#myskarabox-beacon-vm &

     echo 127.0.0.1 > myskarabox/ip
     echo x86_64-linux > myskarabox/system
     echo 2222 > myskarabox/ssh_port
     echo 2223 > myskarabox/ssh_boot_port
     nix run .#myskarabox-gen-knownhosts-file
     ```

     This VM has 4 hard drives:

        - `/dev/nvme0`
        - `/dev/nvme1`
        - `/dev/sda`
        - `/dev/sdb`

    b. Or install on an on-premise host

      By default, the beacon uses DHCP to get an IP address.
      To use a static IP instead, or modify the beacon configuration
      in any way, modify the `extraBeaconModules` in [./template/flake.nix](./template/flake.nix).
     
      ```bash
      nix build .#myskarabox-beacon
      nix run .#beacon-usbimager
      ```

      Use usbimager to burn `./result/iso/beacon.iso` 
      on a USB key, then boot on that USB key.
      Get IP from host and use it in next snippet:
      
      ```bash
      echo 192.168.1.XX > myskarabox/ip
      echo x86_64-linux > myskarabox/system
      nix run .#myskarabox-gen-knownhosts-file
      ```

    c. Or install on Cloud Instance

      For Hetzner, start in recovery mode and retrieve the IP.
      
      ```bash
      echo <ip> > myskarabox/ip
      echo x86_64-linux > myskarabox/system
      nix run .#myskarabox-gen-knownhosts-file
      ```

3. Install on target host

   ```bash
   nix run .#myskarabox-get-facter > ./myskarabox/facter.json
   nix run .#myskarabox-install-on-beacon
   ```
   
   Target host will reboot and ask the passphrase to decrypt
   the root partition. See next section for how to give it.

I used this successfully on my own on-premise x86 server
and on Hetzner dedicated ARM and x86 hosts.

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
