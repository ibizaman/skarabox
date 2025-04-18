{ inputs, pkgs }:
let
  nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";
in
{
  demo = pkgs.writeShellScriptBin "demo-test" ''
    rm -rf .skarabox-tmp

    set -e

    e () {
      echo -e "\e[1;31mSKARABOX-DEMO:\e[0m \e[1;0m$@\e[0m"
    }

    # Kills all children bash processes,
    # like the one that will run in the background hereunder.
    # https://stackoverflow.com/a/2173421/1013628
    # trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

    e "Starting beacon VM."

    ${nix} run ${../.}#demo-beacon -- 2222 2223 -nographic &

    sleep 10

    e "Starting ssh loop to figure out when beacon started."
    e "You might see some flickering on the command line."
    while ! ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 nixos echo "connected" 2>/dev/null; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Starting installation on beacon VM."
    ${nix} run ${../.}#demo-install-on-beacon 127.0.0.1 2222 ${../.}
    e "Installation succeeded."

    e "Starting ssh loop to figure out when VM is ready to receive root passphrase."
    e "You might see some flickering on the command line."
    while ! ${nix} run ${../.}#demo-ssh 127.0.0.1 2223 root echo "connected" 2>/dev/null; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Decrypting root dataset."
    printf "rootpassphrase" | ${nix} run ${../.}#demo-ssh 127.0.0.1 2223 root
    e "Decryption done."

    e "Starting ssh loop to figure out when VM has booted."
    e "You might see some flickering on the command line."
    while ! ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 skarabox echo "connected" 2>/dev/null; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Rebooting to confirm we can connect after a reboot."
    ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 skarabox sudo reboot
    e "Rebooting in progress."

    e "Starting ssh loop to figure out when VM is ready to receive root passphrase."
    e "You might see some flickering on the command line."
    while ! ${nix} run ${../.}#demo-ssh 127.0.0.1 2223 root echo "connected" 2>/dev/null; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Decrypting root dataset."
    printf "rootpassphrase" | ${nix} run ${../.}#demo-ssh 127.0.0.1 2223 root
    e "Decryption done."

    e "Starting ssh loop to figure out when VM has booted."
    e "You might see some flickering on the command line."
    while ! ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 skarabox echo "connected" 2>/dev/null; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Connecting and shutting down"
    ${nix} run ${../.}#demo-ssh 127.0.0.1 2222 skarabox sudo shutdown
    e "Shutdown complete."
  '');
}
