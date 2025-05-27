{
  pkgs
}:
pkgs.writeShellApplication {
  name = "sops-yq-edit";

  runtimeInputs = [
    pkgs.sops
    pkgs.yq-go
  ];

  text = ''
    while getopts ":hf:s:t:" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        f)
          file=''${OPTARG}
          ;;
        s)
          sopskey=''${OPTARG}
          ;;
        t)
          transformation=''${OPTARG}
          ;;
        *)
          ;;
      esac
    done
    shift $((OPTIND-1))

    set -euo pipefail

    export SOPS_AGE_KEY_FILE="$sopskey"
    sops encrypt --filename-override "$file" --output "$file.dup" <( \
      sops decrypt "$file" \
        | yq "$transformation"
    ) \
    && mv "$file.dup" "$file"
  '';
}
