<!---

Template:

## New Features

## Breaking Changes

## User Facing Backwards Compatible Changes

## Fixes

## Other Changes

-->

# Upcoming Release

## New Features

- Add separated-key architecture so that SOPS secrets, including ZFS passphrase, are protected at rest from physical access.
- Add migration tools for existing hosts: `enable-key-separation`, `install-runtime-key`, and `rotate-boot-key`.
- Add `runtimeHostKeyPath` and `runtimeHostKeyPub` configuration options for separated-key mode.

## Breaking Changes

- Remove `hostId` file and directly set the value in the host's `configuration.nix` file.
- Remove `ssh_port` and `ssh_boot_port` files and directly set the value in the host's `configuration.nix` file.
- Remove `ip` and `system` files and directly set the value in the host's `flake.nix` file.
- `gen-new-host` now creates separated-key hosts by default. Use `--single-key` flag for legacy single-key mode (existing single-key hosts remain functional).

## Fixes

- Fix multiple hosts overwriting each other in flake outputs.

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
