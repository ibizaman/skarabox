{ nixpkgs }:
{
  # Copy of upstream nixosSystem that allows to override nixpkgs.
  nixosSystem =
    args@{
      nixpkgs' ? nixpkgs,
      ...
    }:
    import "${nixpkgs'}/nixos/lib/eval-config.nix" (
      {
        system = null;
        modules = (args.modules or []) ++ [
          ({ config, pkgs, ... }:
            {
              nixpkgs.flake.source = nixpkgs.outPath;
            }
          )
        ];
      }
      // builtins.removeAttrs args [ "modules" "nixpkgs'" ]
    );
}
