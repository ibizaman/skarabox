{ nixpkgs }:
{
  # nixosSystem is found in nixpkgs/flake.nix and we must
  # copy it here to be able to use the full patched nixpkgs.
  # Otherwise, we can override pkgs which is a good first step
  # but we can't access the patched lib/ or nixos/modules/ this way.
  nixosSystem =
    args@{
      lib ? null,
      nixpkgs' ? nixpkgs,
      ...
    }:
    import "${nixpkgs'}/nixos/lib/eval-config.nix" (
      {
        system = null;
        modules = (args.modules or []) ++ [
          ({ config, pkgs, lib, ... }:
            {
              nixpkgs.flake.source = nixpkgs.outPath;
            }
          )
        ];
      }
      // (if lib == null then {} else { inherit lib; })
      // builtins.removeAttrs args [ "modules" "lib" "nixpkgs'" ]
    );
}
