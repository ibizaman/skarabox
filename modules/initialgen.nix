{ pkgs }:
pkgs.writeShellScriptBin "init" (
  let
    nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";
  in ''
    set -e
    set -o pipefail

    yes=0
    mkpasswdargs=
    path=
    verbose=

    usage () {
      cat <<USAGE
Usage: $0 [-h] [-y] [-s] [-v] [-p PATH]

  -h:        Shows this usage
  -y:        Answer yes to all questions
  -s:        Take user password from stdin. Only useful
             in scripts.
  -v:        Shows what commands are being run.
  -p PATH:   Replace occurences of github:ibizaman/skarabox
             with the given path, for example ../skarabox.
             This is useful for testing with your own fork
             of skarabox.
USAGE
    }

    while getopts "hysp:v" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        y)
          yes=1
          ;;
        s)
          mkpasswdargs=-s
          ;;
        p)
          path=''${OPTARG}
          ;;
        v)
          verbose=1
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1))

    e () {
      echo -e "\e[1;31mSKARABOX:\e[0m \e[1;0m$@\e[0m"
    }

    # From https://stackoverflow.com/a/29436423/1013628
    yes_or_no () {
      while true; do
        echo -ne "\e[1;31mSKARABOX:\e[0m "
        if [ "$yes" -eq 1 ]; then
          echo "$* Forced yes"
          return 0
        else
          read -p "$* [y/n]: " yn
          case $yn in
            [Yy]*) return 0 ;;
            [Nn]*) echo "Aborting" ; exit 2 ;;
          esac
        fi
      done
    }

    if [ -n "$verbose" ]; then
      set -x
    fi

    e "This script will initiate a Skarabox template in the current directory."
    yes_or_no "Most of the steps are automatic but there are some instructions you'll need to follow manually at the end, continue?"

    ${nix} flake init --template ${../.}
    ${nix} flake update

    if [ -n "$path" ]; then
      ${nix} flake update --override-input skarabox "$path" skarabox
    fi

    e "Now, we will generate the secrets needed."

    e "Generating server host key in ./host_key and ./host_key.pub..."
    rm host_key && ${nix} shell ${../.}#openssh --command ssh-keygen -t ed25519 -N "" -f host_key && chmod 600 host_key

    e "Generating ssh key in ./ssh_skarabox and ./ssh_skarabox.pub..."
    rm ssh_skarabox && ${nix} shell ${../.}#openssh --command ssh-keygen -t ed25519 -N "" -f ssh_skarabox && chmod 600 ssh_skarabox

    e "Generating initial password for user in ./initialHashedPassword..."
    ${nix} run ${../.}#mkpasswd -- $mkpasswdargs > initialHashedPassword

    e "Generating hostid in ./hostid..."
    ${nix} shell ${../.}#util-linux --command uuidgen | head -c 8 > hostid

    e "Generating root pool passphrase in ./root_passphrase..."
    chmod 600 root_passphrase
    ${nix} run ${../.}#openssl -- rand -hex 64 > root_passphrase

    e "Generating data pool passphrase in ./data_passphrase..."
    chmod 600 data_passphrase
    ${nix} run ${../.}#openssl -- rand -hex 64 > data_passphrase

    e "Generating sops key ./sops.key..."
    rm sops.key && ${nix} shell ${../.}#age --command age-keygen -o sops.key

    e "You will need to fill out the ./ip, ./known_hosts and ./system file"
    e "and adjust the ssh_port and ssh_boot_port if you want to."
    e "After that, the next step is to follow the ./README.md file"
  '')
