<!-- Read these docs at https://installer.skarabox.com -->
# Introduction {#introduction}

::: {.note}
Skarabox is hosted on [GitHub](https://github.com/ibizaman/skarabox).
If you encounter problems or bugs then please report them on the [issue
tracker](https://github.com/ibizaman/skarabox/issues).

Feel free to join the dedicated Matrix room
[matrix.org#selfhostblocks](https://matrix.to/#/#selfhostblocks:matrix.org).
:::

Skarabox is a flake template which combines three main features
which all work together to provide a seamless NixOS install experience.

Skarabox uses a lot of existing wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

## NixOS Module {#nixos-module}

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
- Uses [deploy-rs][] or [colmena][] to deploy updates.
- Configures DHCP or static IP for host.
- Supports `x86_64-linux` and `aarch64-linux` platform.
- Supports `x86_64-darwin` and `aarch64-darwin` as long as [cross-compilation][] is enabled.
- Integration with [Self Host Blocks][] which, similarly to Skarabox,
  provides an opinionated way to configure services in a seamless way.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[colmena]: https://github.com/zhaofengli/colmena
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml
[cross-compilation]: https://github.com/cpick/nix-rosetta-builder
[Self Host Blocks]: https://github.com/ibizaman/selfhostblocks

## Beacon {#beacon}

To install NixOS on you server, you must be able to first
boot on it. For a cloud install, that's usually easy but
for an on-premise server, you must create a bootable USB key.
That's the goal of the beacon which generates an ISO file
that's writable on an USB key.

On top of just booting up, Skarabox' beacon:
- Assigns a static IP to the beacon which matches the server's future IP.
- Optionally creates a WiFi hotspot with SSID "Skarabox".

To test the installation, Skarabox provides a VM beacon
that runs on your laptop and which contains 2 OS drive and 2 data drive,
mimicking the supported disk layout by Skarabox.

## Flake Module {#flake-module}

The flake module is used with [flake-parts][] to manage one or more servers
under the [skarabox.hosts option][Flake module options]
and provide commands and packages for each of those.

For example, the `nix run .#gen-new-host <newhost>` command is used to create
the directory structure to manage a new host, including new random secrets.

The flake module:

- Assigns the same values, like IP address, to the [beacon options][] and the [NixOS module options][].
- Creates random host key and ssh key to access the server.
  The host key is used then to populate a known hosts file.
- Create a main [SOPS][sops-nix] key.
- Create one `secrets.yaml` SOPS file per host, encrypted by the main SOPS key
  and by the corresponding host key.
- Uses fully pinned inputs to avoid incompatible dependency versions.

[flake-parts]: https://flake.parts
[beacon options]: https://installer.skarabox.com/options.html#beacon-options
[NixOS module options]: https://installer.skarabox.com/options.html#skarabox-options
[Flake module options]: https://installer.skarabox.com/options.html#flake-module-options

## Contributing {#contributing}

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
