<!-- Read these docs at https://installer.skarabox.com -->
# All Options {#all-options}

## Skarabox Options {#skarabox-options}

These options are set in the NixOS module,
in `myskarabox/configuration.nix` in the template.

The options for the beacon are derived from the values set here.

```{=include=} options
id-prefix: skarabox-opt-
list-id: skarabox-options
source: @SKARABOX_OPTIONS_JSON@
```

## Flake Module Options {#flake-module-options}

These options are set in the flake module,
in `flake.nix` in the template.

```{=include=} options
id-prefix: flake-module-opt-
list-id: flake-module-options
source: @FLAKE_MODULE_OPTIONS_JSON@
```
