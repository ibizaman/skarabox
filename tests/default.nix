{ inputs, pkgs }:
{
  vm = import ./vm.nix { inherit inputs pkgs; };
}
