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
  flakeCompat = import (builtins.fetchTree templateLock.nodes.flake-compat.locked);
  templateInputs = (flakeCompat { src = ../template; }).outputs.inputs;
in
{
  lib = nix-flake-tests.lib.check {
    inherit pkgs;
    tests = pkgs.callPackage ./lib.nix { };
  };
}
// pkgs.lib.optionalAttrs (system == "x86_64-linux") {
  template = import ./template.nix {
    inherit pkgs;
    inherit (self.packages.${system})
      gen-new-host
      sops-add-main-key
      sops-create-main-key
      ;
  };
}
// pkgs.lib.optionalAttrs (system == "x86_64-linux") (
  import ./variants.nix {
    inputs = templateInputs;
    inherit pkgs system;
    skarabox = self;
  }
)
// pkgs.lib.optionalAttrs (system == "x86_64-linux") (
  import ./static.nix {
    inputs = templateInputs;
    inherit pkgs system;
    skarabox = self;
  }
)
