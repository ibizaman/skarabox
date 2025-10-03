{ system, nix, jq, writeShellScriptBin }:
{
  staticIP = writeShellScriptBin "staticIP" ''
    set -e

    e () {
      echo -e "\e[1;31mSKARABOX-TEMPLATE:\e[0m \e[1;0m$@\e[0m"
    }

    group () {
      if [ -z "$CI" ]; then
        e "$@"
      else
        echo "::group::$@"
      fi
    }

    endgroup () {
      if [ -z "$CI" ]; then
        e "$@"
      else
        e "$@"
        echo "::endgroup::"
      fi
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
      group "Creating tmpdir"
      tmpdir="$(mktemp -d)"
      e "Created temp dir at $tmpdir, will be cleaned up on exit or abort"

      # Kills all children bash processes,
      # like the one that will run in the background hereunder.
      # https://stackoverflow.com/a/2173421/1013628
      trap "rm -rf $tmpdir/* $tmpdir/.* $tmpdir; trap - SIGTERM && kill -- -$$ || :" SIGINT SIGTERM EXIT
      endgroup "Done creating tmpdir"
    else
      e "Using provided temp dir $tmpdir, nothing will be cleaned up"
    fi
    cd $tmpdir

    group "Initialising template"
    echo skarabox1234 | ${nix} run ${../.}#init -- -n myskarabox -v -y -s -p ${../.}
    sed -i "s/\(ip =\) \"192.168.1.30\"/\1 \"127.0.0.1\"/" "flake.nix"
    sed -i "s/\(system =\) \"x86_64-linux\"/\1 \"${system}\"/" "flake.nix"
    ${nix} run .#myskarabox-gen-knownhosts-file
    # Using a git repo here allows to only copy in the nix store non temporary files.
    # In particular, we avoid copying the disk*.qcow2 files.
    git init
    echo ".skarabox-tmp" > .gitignore
    git add .
    git config user.name "skarabox"
    git config user.email "skarabox@skarabox.com"
    git commit -m 'init repository'
    endgroup "Initialisation done"

    sed -i 's-staticNetwork = null-staticNetwork = { ip="10.0.2.15"; gateway="10.0.2.255"; }-' ./myskarabox/configuration.nix

    group "Nix flake show"
    ${nix} flake show
    endgroup "Done nix flake show"

    e "Starting beacon VM."

    ${nix} run .#myskarabox-beacon-vm -- $graphic &

    sleep 10

    group "Starting ssh loop to figure out when beacon started."
    e "You might see some flickering on the command line."
    # We can't yet be strict on the host key check since the beacon
    # initially has a random one.
    while ! ${nix} run .#myskarabox-ssh -- -F none -o CheckHostIP=no -o StrictHostKeyChecking=no echo "connected"; do
      sleep 5
    done
    endgroup "Beacon VM has started."

    group "Generating hardware config."
    ${nix} run .#myskarabox-get-facter > ./myskarabox/facter.json
    ${jq}/bin/jq < ./myskarabox/facter.json
    git add ./myskarabox/facter.json
    git commit -m 'generate hardware config'
    endgroup "Generation succeeded."

    group "Starting installation on beacon VM."
    ${nix} run .#myskarabox-install-on-beacon -- --no-substitute-on-destination
    endgroup "Installation succeeded."

    group "Starting ssh loop to figure out when VM is ready to receive root passphrase."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#myskarabox-boot-ssh -- -F none echo "connected"; do
      sleep 5
    done
    endgroup "Beacon VM is ready to accept root passphrase."

    group "Decrypting root dataset."
    ${nix} run .#myskarabox-unlock -- -F none
    endgroup "Decryption done."

    group "Starting ssh loop to figure out when VM has booted."
    e "You might see some flickering on the command line."
    while ! ${nix} run .#myskarabox-ssh -- -F none echo "connected"; do
      sleep 5
    done
    endgroup "Beacon VM has started."
  '';
}
