{
  pkgs,
  add-sops-cfg,
}:
pkgs.writeShellApplication {
  name = "gen-new-host";

  runtimeInputs  = [
    add-sops-cfg
    pkgs.gnused
    pkgs.mkpasswd
    pkgs.openssh
    pkgs.openssl
    pkgs.sops
    pkgs.ssh-to-age
    pkgs.util-linux
  ];

  text = ''
    set -e
    set -o pipefail

    yes=0
    mkpasswdargs=
    verbose=

    usage () {
      cat <<USAGE
Usage: $0 [-h] [-y] [-s] [-v] -n HOSTNAME

  The only required argument, HOSTNAME, is the hostname
  you want to give to the new host. It will also be used
  as a nickname for the host in the nix configuration.

  -h:        Shows this usage
  -y:        Answer yes to all questions
  -s:        Take user password from stdin. Only useful
             in scripts.
  -v:        Shows what commands are being run.
  -n:        Generate files for this hostname.
USAGE
    }

    while getopts "hynsv" o; do
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

    hostname=$1
    if [ -z "$hostname" ]; then
      echo "Please give a hostname. Add -h for usage."
      exit 1
    fi

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

    e "This script will create a new folder ./$hostname and initiate the template and secrets to manage a host using Skarabox."
    yes_or_no "Most of the steps are automatic but there are some instructions you'll need to follow manually at the end, continue?"

    if [ -e "$hostname" ]; then
      e "Cannot create $hostname folder as it already exists. Please remove it or use another hostname."
      exit 1
    fi

    mkdir -p "$hostname"

    e "Generating $hostname/configuration.nix"
    cp ${../template/myskarabox/configuration.nix} "$hostname/configuration.nix"
    sed -i "s/myskarabox/$hostname/" "$hostname/configuration.nix"

    host_key="./$hostname/host_key"
    host_key_pub="$host_key.pub"
    e "Generating server host key in $host_key and $host_key.pub..."
    ssh-keygen -t ed25519 -N "" -f "$host_key" && chmod 600 "$host_key"

    ssh_key="./$hostname/ssh"
    e "Generating ssh key in $ssh_key and $ssh_key.pub..."
    ssh-keygen -t ed25519 -N "" -f "$ssh_key" && chmod 600 "$ssh_key"

    hostid="./$hostname/hostid"
    e "Generating hostid in $hostid..."
    uuidgen | head -c 8 > "$hostid"

    sops_cfg="./.sops.yaml"
    secrets="$hostname/secrets.yaml"
    e "Adding host key in $sops_cfg..."
    host_age_key="$(ssh-to-age -i "$host_key_pub")"
    add-sops-cfg -o "$sops_cfg" alias "$hostname" "$host_age_key"
    add-sops-cfg -o "$sops_cfg" path-regex main "$secrets"
    add-sops-cfg -o "$sops_cfg" path-regex "$hostname" "$secrets"

    sops_key="./sops.key"
    export SOPS_AGE_KEY_FILE=$sops_key
    e "Generating sops secrets file $secrets..."
    echo "tmp_secret: a" > "$secrets"
    sops encrypt -i "$secrets"

    e "Generating initial password for user in $secrets under $hostname/user/hashedPassword"
    sops set "$secrets" \
      "['$hostname']['user']['hashedPassword']" \
      "\"$(mkpasswd $mkpasswdargs)\""

    e "Generating root pool passphrase in $secrets under $hostname/disks/rootPassphrase"
    sops set "$secrets" \
      "['$hostname']['disks']['rootPassphrase']" \
      "\"$(openssl rand -hex 64)\""

    e "Generating data pool passphrase in $secrets under $hostname/disks/dataPassphrase"
    sops set "$secrets" \
      "['$hostname']['disks']['dataPassphrase']" \
      "\"$(openssl rand -hex 64)\""

    sops unset "$secrets" \
      "['tmp_secret']"

    e "You will need to fill out the ./$hostname/ip and ./$hostname/system file and generate ./$hostname/known_hosts."
    e "Optionally, adjust the ./$hostname/ssh_port and ./$hostname/ssh_boot_port if you want to."
    e "Follow the ./README.md for more information and to continue the installation."
  '';

}
