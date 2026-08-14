{
  pkgs,
  self,
  system,
  nix-flake-tests,
}:
let
  # Installation scenarios must use the same pinned inputs as generated
  # configurations while replacing only Skarabox itself with this source tree.
  templateLock = builtins.fromJSON (builtins.readFile ../template/flake.lock);
  # Register locked sources so Nix can evaluate the generated flake offline in the test derivation.
  templateSources = pkgs.lib.unique (
    map (node: (builtins.fetchTree node.locked).outPath) (
      builtins.filter (node: node ? locked) (builtins.attrValues templateLock.nodes)
    )
  );
  flakeCompat = import (builtins.fetchTree templateLock.nodes.flake-compat.locked);
  templateInputs = (flakeCompat { src = ../template; }).outputs.inputs;
in
{
  lib = nix-flake-tests.lib.check {
    inherit pkgs;
    tests = pkgs.callPackage ./lib.nix { };
  };
}
# The VM topology and facter fixture model the x86_64 QEMU machine used by CI.
# In particular, its IDE data disks are not available on QEMU's aarch64 virt machine.
// pkgs.lib.optionalAttrs (system == "x86_64-linux") (
  (import ./variants.nix {
    inputs = templateInputs;
    inherit pkgs system templateSources;
    skarabox = self;
  })
  // (import ./static.nix {
    inputs = templateInputs;
    inherit pkgs system templateSources;
    skarabox = self;
  })
)
