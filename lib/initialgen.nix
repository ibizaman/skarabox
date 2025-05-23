{
  pkgs,
  gen-sopsconfig-file,
}:
pkgs.writeShellApplication {
  name = "init";

  runtimeInputs  = [
    gen-sopsconfig-file
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

    while getopts "hynsp:v" o; do
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

    ${nix} flake init --template ${../.}
    ${nix} flake update

    if [ -n "$path" ]; then
      ${nix} flake update --override-input skarabox "$path" skarabox
    fi

    e "Now, we will generate the secrets needed."

    host_key="./myskarabox/host_key"
    e "Generating server host key in $host_key and $host_key.pub..."
    rm $host_key && ssh-keygen -t ed25519 -N "" -f $host_key && chmod 600 $host_key

    sops_key="./sops.key"
    sops_cfg="./.sops.yaml"
    e "Generating sops key $sops_key..."
    rm $sops_key && age-keygen -o $sops_key
    e "Generating sops config $sops_cfg..."
    rm $sops_cfg && gen-sopsconfig-file -s $sops_key -p $host_key.pub -o $sops_cfg

    secrets="./secrets.yaml"
    e "Generating sops secrets file $secrets..."
    touch $secrets
    export SOPS_AGE_KEY_FILE=$sops_key
    sops encrypt -i $secrets

    ssh_key="./myskarabox/ssh_skarabox"
    e "Generating ssh key in $ssh_key and $ssh_key.pub..."
    ssh-keygen -t ed25519 -N "" -f $ssh_key && chmod 600 $ssh_key

    e "Generating initial password for user in $secrets under skarabox/user/hashedPassword"
    sops set $secrets \
      '["skarabox"]["user"]["hashedPassword"]' \
      "\"$(mkpasswd $mkpasswdargs)\""

    hostid="./myskarabox/hostid"
    e "Generating hostid in $hostid..."
    uuidgen | head -c 8 > $hostid

    e "Generating root pool passphrase in $secrets under skarabox/disks/rootPassphrase"
    sops set $secrets \
      '["skarabox"]["disks"]["rootPassphrase"]' \
      "\"$(openssl rand -hex 64)\""

    e "Generating data pool passphrase in $secrets under skarabox/disks/dataPassphrase"
    sops set $secrets \
      '["skarabox"]["disks"]["dataPassphrase"]' \
      "\"$(openssl rand -hex 64)\""

    e "You will need to fill out the ./myskarabox/ip, ./myskarabox/known_hosts and ./myskarabox/system file"
    e "and adjust the ./myskarabox/ssh_port and ./myskarabox/ssh_boot_port if you want to."
    e "After that, the next step is to follow the ./README.md file"
  '';

}
