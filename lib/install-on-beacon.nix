{ pkgs, nixos-anywhere }:
pkgs.writeShellApplication {
  name = "install-on-beacon";

  runtimeInputs = [
    nixos-anywhere
    pkgs.bash
    pkgs.sops
  ];

  text = ''
    usage () {
      cat <<USAGE
    Usage: $0 -i IP -p PORT -f FLAKE -k HOST_KEY -r ROOT_PASSPHRASE_FILE -d DATA_PASSPHRASE_FILE [-a EXTRA_OPTS]

      -h:                       Shows this usage
      -i IP:                    IP of the target host running the beacon.
      -p PORT:                  Port of the target host running the beacon.
      -f FLAKE:                 Flake to install on the target host.
      -k HOST_KEY_FILE:         SSH key to use as the host identification key.
      -r ROOT_PASSPHRASE_PATH:  Path in the yaml secrets file for the root passphrase used to encrypt the root ZFS pool.
      -d DATA_PASSPHRASE_PATH:  Path in the yaml secrets file for the data passphrase used to encrypt the root ZFS pool.
      -s SOPS_KEY:              File containing a sops key capable of decrypting the secrets.
      -e SECRETS_FILE:          File containing the secrets.
      -a EXTRA_OPTS:            Extra options to pass verbatim to nixos-anywhere.
    USAGE
    }

    check_empty () {
      if [ -z "$1" ]; then
        echo "$3 must not be empty, pass with flag $2"
      fi
    }

    while getopts "hi:p:f:k:r:d:s:e:a:" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        i)
          ip=''${OPTARG}
          ;;
        p)
          port=''${OPTARG}
          ;;
        f)
          flake=''${OPTARG}
          ;;
        k)
          host_key_file=''${OPTARG}
          ;;
        r)
          root_passphrase_path=''${OPTARG}
          ;;
        d)
          data_passphrase_path=''${OPTARG}
          ;;
        s)
          sopskey=''${OPTARG}
          ;;
        e)
          secretsfile=''${OPTARG}
          ;;
        a)
          read -ra extra_opts <<< "''${OPTARG}"
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1))

    check_empty "$ip" -i ip
    check_empty "$port" -p port
    check_empty "$flake" -f flake
    check_empty "$host_key_file" -k host_key_file
    check_empty "$root_passphrase_path" -r root_passphrase_path
    check_empty "$data_passphrase_path" -d data_passphrase_path
    check_empty "$sopskey" -s sopskey
    check_empty "$secretsfile" -e secretsfile

    export SOPS_AGE_KEY_FILE=$sopskey
    root_passphrase=$(sops decrypt --extract "$root_passphrase_path" "$secretsfile")
    data_passphrase=$(sops decrypt --extract "$data_passphrase_path" "$secretsfile")

    set -x

    nixos-anywhere \
      --flake "$flake" \
      --disk-encryption-keys /tmp/host_key "$host_key_file" \
      --disk-encryption-keys /tmp/root_passphrase <(echo "$root_passphrase") \
      --disk-encryption-keys /tmp/data_passphrase <(echo "$data_passphrase") \
      --ssh-port "$port" \
      "''${extra_opts[@]}" \
      skarabox@"$ip"
  '';
}
