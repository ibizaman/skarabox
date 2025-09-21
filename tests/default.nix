{ pkgs, system, nix-flake-tests }:
let
  nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";

in
{
  lib = nix-flake-tests.lib.check {
    inherit pkgs;
    tests = pkgs.callPackage ./lib.nix {};
  };
}
// (import ./variants.nix { inherit system nix; inherit (pkgs) gnugrep jq writeShellScriptBin; })
// (import ./upgrades.nix { inherit system nix; inherit (pkgs) gnugrep jq writeShellScriptBin; })
// (import ./static.nix { inherit system nix; inherit (pkgs) jq writeShellScriptBin; })
