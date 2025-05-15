{
  pkgs
}:
pkgs.writeShellApplication {
  name = "gen-sopsconfig-file";

  runtimeInputs = [
    pkgs.age
    pkgs.ssh-to-age
  ];

  text = ''
    usage () {
      cat <<USAGE
    Usage: $0 [-h] [-p PUBHOSTKEY] [-s SOPSKEY] [-o SOPSCFG]

    Create a new sops config file at SOPSCFG with two sops keys able to decrypt a secrets.yaml file.
    The master sops key (-s SOPSKEY) will be generated while the host key (-p PUBHOSTKEY) will be derived
    from an ssh public key.

      -h:        Shows this usage
      -p PUBHOSTKEY:  Path to the public ssh host key of the host.
      -s SOPSKEY:     Path to the master sops key.
      -o SOPSCFG:     Output path where the sops config will be written
    USAGE
    }

    sopscfg=.sops.yaml

    while getopts "hp:o:s:" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        p)
          pubhostkey=''${OPTARG}
          ;;
        s)
          sopskey=''${OPTARG}
          ;;
        o)
          sopscfg=''${OPTARG}
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1))

    if [ -z "$sopskey" ]; then
      echo "Please pass sops key with -k argument."
      exit 1
    fi

    if [ -f "$sopscfg" ]; then
      echo "A file already exists at $sopscfg. Please remove the file to continue."
      exit 1
    fi

    if [ -z "$pubhostkey" ]; then
      echo "Please pass sops key with -o argument."
      exit 1
    fi

    me_age_key="$(age-keygen -y "$sopskey")"
    host_age_key="$(ssh-to-age -i "$pubhostkey")"

    cat <<SOPS > "$sopscfg"
    keys:
      # To obtain the age key for &me, run:
      #   nix shell .#age --command age-keygen -y $sopskey
      - &me $me_age_key
      # To obtain the age key for &server, run:
      #   nix shell .#age --command age-keygen -y $pubhostkey
      - &server $host_age_key
    creation_rules:
      - path_regex: secrets\.yaml$
        key_groups:
        - age:
          - *me
          - *server
    SOPS
  '';
}
