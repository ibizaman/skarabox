{ inputs, pkgs, system }:
let
  nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";
in
{
  template = pkgs.writeShellScriptBin "template-test" ''
    set -e

    e () {
      echo -e "\e[1;31mSKARABOX-TEMPLATE:\e[0m \e[1;0m$@\e[0m"
    }

    graphic=-nographic
    tmpdir=

    while getopts "gp:" o; do
      case "''${o}" in
        g)
          graphic=
          ;;
        p)
          tmpdir=''${OPTARG}
          ;;
        *)
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1))

    if [ -z "$tmpdir" ]; then
      tmpdir="$(mktemp -d)"
      e "Created temp dir at $tmpdir, will be cleaned up on exit or abort"

      # Kills all children bash processes,
      # like the one that will run in the background hereunder.
      # https://stackoverflow.com/a/2173421/1013628
      trap "rm -rf $tmpdir/* $tmpdir/.* $tmpdir; trap - SIGTERM && kill -- -$$ || :" SIGINT SIGTERM EXIT
    else
      e "Using provided temp dir $tmpdir, nothing will be cleaned up"
    fi
    cd $tmpdir

    e "Initialising template"
    echo skarabox1234 | ${nix} run ${../.}#init -- -v -y -s -p ${../.}
    echo 2223 > ssh_boot_port
    echo 2222 > ssh_port
    echo 127.0.0.1 > ip
    echo ${system} > system
    ${nix} run .#gen-knownhosts-file
    # Using a git repo here allows to only copy in the nix store non temporary files.
    # In particular, we avoid copying the disk*.qcow2 files.
    git init
    echo ".skarabox-tmp" > .gitignore
    git add .
    git config user.name "skarabox"
    git config user.email "skarabox@skarabox.com"
    git commit -m 'init repository'
    e "Initialisation done"

    nix flake show

    e "Starting beacon VM."

    ${nix} run .#beacon-vm -- $graphic &

    sleep 10

    e "Starting ssh loop to figure out when beacon started."
    e "You might see some flickering on the command line."
    # We can't yet be strict on the host key check since the beacon
    # initially has a random one.
    while ! ${nix} run .#ssh -- -F none -o CheckHostIP=no -o StrictHostKeyChecking=no echo "connected"; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Generating hardware config."
    ${nix} run .#ssh -- -o StrictHostKeyChecking=no sudo nixos-facter > facter.json
    git add facter.json
    git commit -m 'generate hardware config'
    e "Generation succeeded."

    e "Starting installation on beacon VM."
    ${nix} run .#install-on-beacon -- .#skarabox --no-substitute-on-destination
    e "Installation succeeded."

    e "Starting ssh loop to figure out when VM is ready to receive root passphrase."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#boot-ssh -- -F none echo "connected"; do
      sleep 5
    done
    e "Beacon VM is ready to accept root passphrase."

    e "Decrypting root dataset."
    ${nix} run .#unlock -- -F none
    e "Decryption done."

    e "Starting ssh loop to figure out when VM has booted."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#ssh -- -F none echo "connected"; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Checking password for skarabox user has been set."
    hashedpwd="$(${nix} run .#sops decrypt secrets.yaml | ${nix} run .#yq -- -r .skarabox.user.hashedPassword)"
    ${nix} run .#ssh -- -F none sudo cat /etc/shadow | ${pkgs.gnugrep}/bin/grep "$hashedpwd"
    e "Password has been set."

    e "Rebooting to confirm we can connect after a reboot."
    # We sleep first and run the whole script in the background
    # to avoid a race condition where the VM reboots too fast
    # and kills the ssh connection, resulting in the test failing.
    # So this is all so we can disconnect first.
    ${nix} run .#ssh -- -F none "(sleep 2 && sudo reboot)&"
    e "Rebooting in progress."

    e "Starting ssh loop to figure out when VM is ready to receive root passphrase."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#boot-ssh -- -F none echo "connected"; do
      sleep 5
    done
    e "Beacon VM is ready to accept root passphrase."

    e "Decrypting root dataset."
    ${nix} run .#unlock -- -F none
    e "Decryption done."

    e "Starting ssh loop to figure out when VM has booted."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#ssh -- -F none echo "connected"; do
      sleep 5
    done
    e "Beacon VM has started."

    e "Checking password for skarabox user has been set."
    hashedpwd="$(${nix} run .#sops decrypt secrets.yaml | ${nix} run .#yq -- -r .skarabox.user.hashedPassword)"
    ${nix} run .#ssh -- -F none sudo cat /etc/shadow | ${pkgs.gnugrep}/bin/grep "$hashedpwd"
    e "Password has been set."

    e "Deploying."
    ${nix} run .#deploy
    e "Deploying done."

    e "Checking password for skarabox user has been set."
    hashedpwd="$(${nix} run .#sops decrypt secrets.yaml | ${nix} run .#yq -- -r .skarabox.user.hashedPassword)"
    ${nix} run .#ssh -- -F none sudo cat /etc/shadow | ${pkgs.gnugrep}/bin/grep "$hashedpwd"
    e "Password has been set."

    e "Connecting and shutting down"
    ${nix} run .#ssh -- -F none sudo shutdown
    e "Shutdown complete."
  '';
}
