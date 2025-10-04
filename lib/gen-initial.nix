{
  pkgs,
  sops-create-main-key,
  sops-add-main-key,
  gen-new-host,
}:
pkgs.writeShellApplication {
  name = "gen-initial";

  runtimeInputs  = [
    sops-create-main-key
    sops-add-main-key
    gen-new-host
    pkgs.age
    pkgs.mkpasswd
    pkgs.nix
    pkgs.openssh
    pkgs.openssl
    pkgs.sops
    pkgs.util-linux
  ];

  text = let
    nix = "nix --extra-experimental-features nix-command -L";
  in ''
    set -e
    set -o pipefail

    name=myskarabox
    yes=0
    path=
    verbose=

    usage () {
      cat <<USAGE
Usage: $0 [-h] [-n] [-y] [-s] [-v] [-p PATH]

  -h:        Shows this usage
  -n:        Name of host, defaults to "myskarabox".
  -y:        Answer yes to all questions
  -s:        Take user password from stdin. Only useful
             in scripts.
  -p PATH:   Replace occurences of github:ibizaman/skarabox
             with the given path, for example ../skarabox.
             This is useful for testing with your own fork
             of skarabox.
  -v:        Shows what commands are being run.
USAGE
    }

    args=()
    while getopts ":hn:ysp:v" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        n)
          name=''${OPTARG}
          ;;
        y)
          args+=(-y)
          yes=1
          ;;
        s)
          args+=(-s)
          ;;
        p)
          path=''${OPTARG}
          ;;
        v)
          args+=(-v)
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
      echo -e "\e[1;31mSKARABOX:\e[0m \e[1;0m$*\e[0m"
    }

    # From https://stackoverflow.com/a/29436423/1013628
    yes_or_no () {
      while true; do
        echo -ne "\e[1;31mSKARABOX:\e[0m "
        if [ "$yes" -eq 1 ]; then
          echo "$* Forced yes"
          return 0
        else
          read -rp "$* [y/n]: " yn
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

    if [ "$(find . -mindepth 1 | wc -l)" -gt 0 ]; then
      e "Current directory is not empty, aborting."
      exit 1
    fi

    ${nix} flake init --template ${../.}
    ${nix} flake update

    if [ -n "$path" ]; then
      ${nix} flake update --override-input skarabox "$path" skarabox
    fi

    e "Now, we will generate the global secrets."

    sops_key="./sops.key"
    e "Generating main sops key in $sops_key..."
    rm $sops_key && sops-create-main-key $sops_key

    sops_cfg="./.sops.yaml"
    e "Creating initial SOPS config in $sops_cfg..."
    rm $sops_cfg && sops-add-main-key $sops_key $sops_cfg

    e "Now, we will generate the secrets for $name."

    rm -rf myskarabox
    # We force yes because if we came to here, we said yes earlier.
    args+=(-y)
    gen-new-host "''${args[@]}" "$name"
  '';

}
