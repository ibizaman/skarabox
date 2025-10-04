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
    Usage: $0 -i IP -p PORT -f FLAKE -u USERNAME

      -h:               Shows this usage
      -i IP:            IP of the target host running the beacon.
      -p PORT:          Port of the target host running the beacon.
      -f FLAKE:         Flake to install on the target host.
      -u USERNAME:      Username to connect to the host with.
      
      Any additional arguments after the flags will be passed to nixos-anywhere.
    USAGE
    }

    check_empty () {
      if [ -z "$1" ]; then
        echo "$3 must not be empty, pass with flag $2"
      fi
    }

    while getopts "hi:p:f:u:" o; do
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
        u)
          username=''${OPTARG}
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
    check_empty "$username" -u username

    nixos-anywhere \
      --flake "$flake" \
      --ssh-port "$port" \
      "$@" \
      "$username"@"$ip"
  '';
}
