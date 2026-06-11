{
  pkgs,
  name,
  ssh-beacon,
}:
pkgs.writeShellApplication {
  name = "get-facter";

  runtimeInputs  = [
    ssh-beacon
  ];

  text = ''
    set -e
    set -o pipefail

    args=()
    if [ "$(ssh id -u)" -ne 0 ]; then
      args+=(sudo)
    fi

    if ssh type nixos-facter &>/dev/null; then
      args+=(nixos-facter)
    else
      if ! ssh type nix &>/dev/null; then
        echo "Neither the nixos-facter or nix binary could be found on the beacon."
        echo "You can use nixos-anywhere's kexec phase to start in a nix environment:"
        echo "  nix run .#${name}-install-on-beacon -- --phases kexec"
        exit 1
      fi
      args+=(nix run nixpkgs#nixos-facter)
    fi

    ssh "''${args[@]}"
  '';
}
