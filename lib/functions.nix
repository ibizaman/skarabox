{
  # nixosSystem is found in nixpkgs/flake.nix and we must
  # copy it here to be able to use the full patched nixpkgs.
  # Otherwise, we can override pkgs which is a good first step
  # but we can't access the patched lib/ or nixos/modules/ this way.
  nixosSystem =
    nixpkgs:
    args:
    import "${nixpkgs}/nixos/lib/eval-config.nix" (
      {
        lib = import "${nixpkgs}/lib";
        system = null;
        modules = args.modules ++ [
          ({ config, pkgs, lib, ... }:
            {
              nixpkgs.flake.source = nixpkgs.outPath;
            }
          )
        ];
      }
      // builtins.removeAttrs args [ "modules" ]
    );
}
