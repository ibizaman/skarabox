{ pkgs, nixos-anywhere }:
pkgs.writeShellScriptBin "install-on-beacon" ''
  usage () {
    cat <<USAGE
Usage: $0 -i IP -p PORT -f FLAKE -k HOST_KEY -r ROOT_PASSPHRASE_FILE -d DATA_PASSPHRASE_FILE [-a EXTRA_OPTS]

  -h:                       Shows this usage
  -i IP:                    IP of the target host running the beacon.
  -p PORT:                  Port of the target host running the beacon.
  -f FLAKE:                 Flake to install on the target host.
  -k HOST_KEY_FILE:         SSH key to use as the host identification key.
  -r ROOT_PASSPHRASE_FILE:  File containing the root passphrase used to encrypt the root ZFS pool.
  -d DATA_PASSPHRASE_FILE:  File containing the data passphrase used to encrypt the data ZFS pool.
  -a EXTRA_OPTS:            Extra options to pass verbatim to nixos-anywhere.
USAGE
  }
  while getopts "hi:p:f:k:r:d:a:" o; do
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
        root_passphrase_file=''${OPTARG}
        ;;
      d)
        data_passphrase_file=''${OPTARG}
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

  ${nixos-anywhere}/bin/nixos-anywhere \
    --flake $flake \
    --disk-encryption-keys /tmp/host_key $host_key_file \
    --disk-encryption-keys /tmp/root_passphrase $root_passphrase_file \
    --disk-encryption-keys /tmp/data_passphrase $data_passphrase_file \
    --ssh-port $port \
    skarabox@$ip \
    $extra_opts
''
