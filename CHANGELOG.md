<!---

Template:

## Breaking Changes

## New Features

## User Facing Backwards Compatible Changes

## Fixes

## Other Changes

-->

# Upcoming Release

# v1.4.0

## Breaking Changes

- Removed command-line argument `-n` to flake `#init` command.
  This command was to initialize with a custom hostname but it was not working
  so it was removed in the meantime.
- Removed flake `skarabox.sshAuthorizedKey` because it was a duplicate of the NixOS module one.

## New Features

- Allow to configure hotspot SSID with option `skarabox.hotspot.ssid` which defaults to `Skarabox`.
- Re-use configuration from host for beacon.
  This means the beacon uses the same DHCP or static network configuration than the final host.

## Fixes

- Fix network DHCP setup which was conflicting between systemd and the NixOS' custom script.

# v1.3.0

## Breaking Changes

- Do not allow to override lib in `nixosSystem` function.
  It was a bad idea.
  This was added to support SelfHostBlocks but now that project
  sets up a new `shb` variable containing its functions using `_module.args.shb`.
  The template is updated too.

  ```diff
    skarabox.hosts = {
      myskarabox = {
        nixpkgs = inputs.selfhostblocks.lib.${system}.patchedNixpkgs;
  -     pkgs = inputs.selfhostblocks.lib.${system}.pkgs;

        modules = [
  +       {
  +         nixpkgs.overlays = [
  +           selfhostblocks.overlays.${system}.default
  +         ];
  +       }
        ];
      };
    };
  ```

## Other Changes

- Some rewrite of the manual.

# v1.2.0

## New Features

- Allow to customize starting hostname instead of hardcoded `myskarabox`.

## Breaking Changes

- Remove `hostId` file and directly set the value in the host's `configuration.nix` file.
- Remove `ssh_port` and `ssh_boot_port` files and directly set the value in the host's `configuration.nix` file.
- Remove `ip` and `system` files and directly set the value in the host's `flake.nix` file.
- Added `skarabox.hosts.<name>.pkgs` option to allow overriding `pkgs.lib`.

  ```diff
    skarabox.hosts = {
      myskarabox = {
          nixpkgs = inputs.selfhostblocks.lib.${system}.patchedNixpkgs;
  +       pkgs = inputs.selfhostblocks.lib.${system}.pkgs;
      };
    };
  ```

- Removed `system` from `nixosModules` flake output.

  ```diff
  - inputs.selfhostblocks.nixosModules.${system}.default
  + inputs.selfhostblocks.nixosModules.default
  ```

## Fixes

- Fix multiple hosts overwriting each other in flake outputs.
- Beacon script can be run a darwin guests.

## Other Changes

- `known_hosts` file is generated also with the host's ip without the port.

# v1.1.0

## New Features

- Make `colmena` and `deploy-rs` optional.
- Add integration with SelfHostBlocks in flake template.
- Make `nixosSystem` function take patch to modules and lib too.
- Add preliminary support for darwin hosts. Fixed some binary commands incompatibilities.
  It works as long as you can cross-compile to the target system.
- Allow to pass most options requiring a file as the string value itself instead.

# v1.0.1

First release deemed good enough.
