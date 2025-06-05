{ pkgs, nixos-anywhere }:
pkgs.writeShellApplication {
  name = "install-on-beacon";

  runtimeInputs = [
    nixos-anywhere
    pkgs.bash
  ];

  text = ''
    usage () {
      cat <<USAGE
    Usage: $0 -i IP -p PORT -f FLAKE -k HOST_KEY_FILE -u USERNAME [-a EXTRA_OPTS]

      -h:               Shows this usage
      -i IP:            IP of the target host running the beacon.
      -p PORT:          Port of the target host running the beacon.
      -f FLAKE:         Flake to install on the target host.
      -k HOST_KEY_FILE: SSH key to use as the host identification key.
      -u USERNAME:      Username to connect to the host with.
      -a EXTRA_OPTS:    Extra options to pass verbatim to nixos-anywhere.
    USAGE
    }

    check_empty () {
      if [ -z "$1" ]; then
        echo "$3 must not be empty, pass with flag $2"
      fi
    }

    while getopts "hi:p:f:k:d:a:u:" o; do
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
        u)
          username=''${OPTARG}
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
    check_empty "$username" -u username

    nixos-anywhere \
      --flake "$flake" \
      --disk-encryption-keys /tmp/host_key "$host_key_file" \
      --ssh-port "$port" \
      "''${extra_opts[@]}" \
      "$username"@"$ip"
  '';
}
