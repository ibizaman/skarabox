{ inputs, pkgs }:
{
  vm = pkgs.writeShellScriptBin "vm-test" (let
    nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";
  in ''
    rm -rf disk1.qcow2 disk2.qcow2 disk3.qcow2

    set -ex

    # https://stackoverflow.com/a/2173421/1013628
    trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

    export HOME=$(pwd)
    mkdir -p "$HOME/.ssh"
    chmod 600 "$HOME/.ssh"

    ${nix} run ${../.}#demo-beacon 2222 2223 &
    # TODO: make host key pre-verified
    ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 echo "connected"
    ${nix} run ${../.}#demo-install-on-beacon 127.0.0.1 2222 ${../.}
    # TODO: allow to ssh to enter root passphrase
    # TODO: make host key pre-verified
    ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 echo "connected"
  '');
}
