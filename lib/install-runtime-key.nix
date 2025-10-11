{
  pkgs,
  name,
  cfg,
  ssh,
}:
pkgs.writeShellApplication {
  name = "install-runtime-key";

  runtimeInputs = [
    ssh
  ];

  text = ''
    set -euo pipefail

    hostname="${name}"
    runtime_key_path="${cfg.runtimeHostKeyPath}"

    usage () {
      cat <<USAGE
Usage: $0 [-h]

Copies runtime key to target host in preparation for separated-key migration.

  -h: Shows this usage

Prerequisites: nix run .#${name}-enable-key-separation
USAGE
    }

    while getopts "h" o; do
      case "''${o}" in
        h)
          usage
          exit 0
          ;;
        *)
          usage
          exit 1
          ;;
      esac
    done
    shift $((OPTIND-1))

    # Validate prerequisites
    echo "Validating prerequisites for $hostname..."

    if [ ! -f "$runtime_key_path" ]; then
      echo "Error: Runtime key not found at: $runtime_key_path" >&2
      echo "Run enable-key-separation first:" >&2
      echo " nix run .#$hostname-enable-key-separation" >&2
      exit 1
    fi

    echo "Prerequisites validated"

    # Install runtime private key directly to final location on target host
    echo "Installing runtime key to $hostname..."

    # Stream key directly via SSH stdin to avoid tmp file exposure
    cat $runtime_key_path | ssh "sudo install -D -m 600 /dev/stdin /persist/etc/ssh/ssh_host_ed25519_key"

    echo "Runtime key installed at /persist/etc/ssh/ssh_host_ed25519_key on $hostname"
    echo ""
    echo "Next steps:"
    echo " 1. Update $hostname/configuration.nix:"
    echo "      sops.age.sshKeyPaths = [ \"/persist/etc/ssh/ssh_host_ed25519_key\" ];"
    echo ""
    echo " 2. Update flake.nix:"
    echo "      runtimeHostKeyPub = ./$hostname/runtime_host_key.pub;"
    echo ""
    echo " 3. Deploy:"
    echo "      nix run .#deploy-rs"
    echo "      nix run .#$hostname-gen-knownhosts-file"
    echo ""
    echo " 4. After deployment, complete migration:"
    echo "      age_key=\$(ssh-to-age < $hostname/host_key.pub)"
    echo "      nix run .#sops -- -r -i --rm-age \"\$age_key\" $hostname/secrets.yaml"
    echo "      sed -i.bak -e '/- \*''${hostname}_boot\$/d' -e '/&''${hostname}_boot/d' .sops.yaml"
    echo "      ssh-keygen -t ed25519 -f $hostname/host_key"
    echo "      nix run .#$hostname-rotate-boot-key"
    echo "      nix run .#$hostname-gen-knownhosts-file"
  '';
}
