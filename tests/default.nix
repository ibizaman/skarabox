{ pkgs, system, nix-flake-tests }:
let
  # It is necessary to add --allow-import-from-derivation explicitly because the flake show command
  # does not pick it up from the config, on purpose.
  nix = "${pkgs.nix}/bin/nix --allow-import-from-derivation --extra-experimental-features nix-command -L";

in
{
  lib = nix-flake-tests.lib.check {
    inherit pkgs;
    tests = pkgs.callPackage ./lib.nix {};
  };
}
// (import ./variants.nix { inherit system nix; inherit (pkgs) gnugrep jq writeShellScriptBin; })
// (import ./static.nix { inherit system nix; inherit (pkgs) jq writeShellScriptBin; })
