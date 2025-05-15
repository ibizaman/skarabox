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
    while getopts "hp:s:" o; do
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

    if [ -z "$pubhostkey" ]; then
      echo "Please pass sops key with -o argument."
      exit 1
    fi

    me_age_key="$(age-keygen -y "$sopskey")"
    host_age_key="$(ssh-to-age -i "$pubhostkey")"

    cat <<SOPS > .sops.yaml
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
