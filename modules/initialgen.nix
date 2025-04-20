{ pkgs }:
pkgs.writeShellScriptBin "init" (
  let
    nix = "${pkgs.nix}/bin/nix --extra-experimental-features nix-command -L";
  in ''
    set -e
    set -o pipefail

    e () {
      echo -e "\e[1;31mSKARABOX:\e[0m \e[1;0m$@\e[0m"
    }

    yes=0
    mkpasswdargs=
    if [ "$1" = "-y" ]; then
      yes=1
      mkpasswdargs=-s
    fi

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

    e "This script will initiate a Skarabox template in the current directory."
    yes_or_no "Most of the steps are manual but there are some instructions you'll need to follow manually at the end, continue?"

    ${nix} flake init --template ${../.}

    e "Now, we will generate the secrets needed."

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

    e "Generating ssh key in ./ssh_skarabox and ./ssh_skarabox.pub..."
    rm ssh_skarabox && ${nix} shell ${../.}#openssh --command ssh-keygen -t ed25519 -N "" -f ssh_skarabox && chmod 600 ssh_skarabox

    e "You will need to fill out the ./ip file and ./system file"
    e "After that, the next step is to follow the ./README.md file"
  '')
