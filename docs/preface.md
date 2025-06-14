<!-- Read these docs at https://installer.skarabox.com -->
# Preface {#preface}

::: {.note}
Skarabox is hosted on [GitHub](https://github.com/ibizaman/skarabox).
If you encounter problems or bugs then please report them on the [issue
tracker](https://github.com/ibizaman/skarabox/issues).

Feel free to join the dedicated Matrix room
[matrix.org#selfhostblocks](https://matrix.to/#/#selfhostblocks:matrix.org).
:::

Skarabox aims to be the fastest way to install NixOS on a server
with all batteries included. It provides a flake template which includes:

- A bootable ISO called beacon, installable on an USB key.
- A WiFi hotspot with SSID Skarabox available from the beacon.
- Alternatively, a VM based on the bootable ISO
  to test the installation procedure.
- Managing host keys, known hosts and ssh keys
  to provide a secure and seamless SSH experience.
- [nixos-anywhere][] to install NixOS headlessly.
- [disko][] to format the drives using native ZFS encryption.
- Remote root pool decryption through ssh.
- Disk mirroring: 1 or 2 disks in raid1 using ZFS mirroring for the OS,
  boot partition is then mirrored using grub mirrored devices
  and 0 or 2 disks in raid1 using ZFS mirroring for the data disks.
- [nixos-facter][] to handle hardware configuration.
- [flake-parts][] to make the user-facing `flake.nix` small.
- Handle having multiple hosts managed by one flake
  and programmatically add more with generated secrets with one command.
- [sops-nix][] to handle secrets: the user's password and the root and data ZFS pool passphrases.
- [deploy-rs][] or [colmena][] to deploy updates.
- Statically assigned IP for beacon and WiFi hotspot for
  easier installation procedure.
- DHCP or static IP for host.
- Programmatically populate Sops secrets file.
- Fully pinned inputs.
- Backed by [tests][] for all disk variants
  and [CI][] to make sure the installation procedure does work!
  Why don't you run them yourself: `nix run github:ibizaman/skarabox#checks.x86_64-linux.oneOStwoData -- -g`.
- Supporting `x86_64-linux` and `aarch64-linux` platform.
- Some pretty extensive [recovery][] instructions.
- All choices are documentation in the [architecture](architecture.html) document.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere
[disko]: https://github.com/nix-community/disko
[nixos-facter]: https://github.com/nix-community/nixos-facter
[flake-parts]: https://flake.parts/
[sops-nix]: https://github.com/Mic92/sops-nix
[deploy-rs]: https://github.com/serokell/deploy-rs
[colmena]: https://github.com/zhaofengli/colmena
[tests]: ./tests/default.nix
[CI]: ./.github/workflows/build.yaml
[recovery]: ./template/README.md#recovery

This repository does not invent any of those wonderful tools.
It merely provides an opinionated way to make them all fit together.
By being more opinionated, it gets you set up faster.

Services can then be installed by using NixOS options directly
or through [Self Host Blocks][].
The latter, similarly to Skarabox, provides an opinionated way to configure services in a seamless way.

[Self Host Blocks]: https://github.com/ibizaman/selfhostblocks
