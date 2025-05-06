{ pkgs, nixos-anywhere }:
let
  # We use a separate script here because sops run script
  # with /bin/sh and this way we can override the shell easily.
  #
  # Other methods of doing that exist but this way also helps with
  # making escaping variables easier. And it runs shellcheck.
  innerScript = pkgs.writeShellApplication {
    name = "inner-install-on-beacon";

    runtimeInputs = [
      pkgs.yq
    ];

    text = ''
      fd="$1"; shift
      ip="$1"; shift
      port="$1"; shift
      flake="$1"; shift
      host_key_file="$1"; shift
      root_passphrase_path="$1"; shift
      data_passphrase_path="$1"; shift

      IFS=' ' read -ra extra_opts <<<"$1"; shift

      # We read the fd once and store it because
      # we can't read it twice.
      secrets="$(cat "$fd")"
      root_passphrase=$(echo "$secrets" | yq -r "$root_passphrase_path")
      data_passphrase=$(echo "$secrets" | yq -r "$data_passphrase_path")

      nixos-anywhere \
        --flake "$flake" \
        --disk-encryption-keys /tmp/host_key "$host_key_file" \
        --disk-encryption-keys /tmp/root_passphrase <(echo "$root_passphrase") \
        --disk-encryption-keys /tmp/data_passphrase <(echo "$data_passphrase") \
        --ssh-port "$port" \
        "''${extra_opts[@]}" \
        skarabox@"$ip"
    '';
  };
in
pkgs.writeShellApplication {
  name = "install-on-beacon";

  runtimeInputs = [
    nixos-anywhere
    pkgs.bash
    pkgs.sops
    pkgs.yq
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
      -a EXTRA_OPTS:            Extra options to pass verbatim to nixos-anywhere.
    USAGE
    }

    check_empty () {
      if [ -z "$1" ]; then
        echo "$3 must not be empty, pass with flag $2"
      fi
    }

    while getopts "hi:p:f:k:r:d:s:a:" o; do
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
        a)
          extra_opts=''${OPTARG}
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

    SOPS_AGE_KEY_FILE=$sopskey sops exec-file secrets.yaml "
      bash \
      ${innerScript}/bin/inner-install-on-beacon {} \
      $ip \
      $port \
      $flake \
      $host_key_file \
      $root_passphrase_path \
      $data_passphrase_path \
      \"$extra_opts\"
    "
  '';
}
