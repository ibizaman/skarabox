# Skarabox

## Why?

Install NixOS on a server in two steps.

- The disk will be formatted to use ZFS.
- [Self Host Blocks](https://github.com/ibizaman/selfhostblocks) project will be used to install services.

## Caution

Following the steps WILL ERASE THE CONTENT of any disk on that server.

## Usage

1. Boot on the NixOS installer. You just need to boot, no need to install.

   1. First, create the .iso file.

   ```
   nix build .#beacon
   ```

   2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```
   nix run nixpkgs#usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

   3. Plug USB in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

## Contribute

To start a VM with the beacon, run:

```
nix run .#beacon-test
```

## Links

- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix
- https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/cd-dvd/installation-cd-base.nix
- https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/no-os.md#installing-on-a-machine-with-no-operating-system
