{
  pkgs,
  name,
  cfg,
  add-sops-cfg,
}:
pkgs.writeShellApplication {
  name = "enable-key-separation";

  runtimeInputs = [
    pkgs.openssh
    pkgs.yq-go
    pkgs.ssh-to-age
    add-sops-cfg
  ];

  text = ''
    set -euo pipefail

    # From flake configuration
    hostname="${name}"
    boot_key_pub="${cfg.hostKeyPub}"
    runtime_key="${cfg.runtimeHostKeyPath}"
    runtime_key_pub="''${runtime_key}.pub"
    sops_file="${cfg.secretsFilePath}"
    sops_cfg=".sops.yaml"

    usage () {
      cat <<USAGE
Usage: $0 [-h]

Generates runtime keys and updates SOPS configuration for separated-key migration.

  -h: Shows this usage

Note: Must be run from the flake root directory.
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

    validate_prerequisites () {
      # Validate SOPS configuration exists
      if [ ! -f "$sops_cfg" ]; then
        echo "Error: SOPS configuration not found: $sops_cfg" >&2
        exit 1
      fi

      # Validate secrets file exists
      if [ ! -f "$sops_file" ]; then
        echo "Error: SOPS secrets file not found: $sops_file" >&2
        exit 1
      fi
    }

    generate_runtime_key () {
      if [ -f "$runtime_key" ] && [ -f "$runtime_key_pub" ]; then
        echo "[1/6] Runtime SSH key already exists, skipping generation"
        return 0
      fi

      echo "[1/6] Generating runtime SSH key pair for $hostname..."
      ssh-keygen -t ed25519 -N "" -f "$runtime_key" -C "runtime-key@$hostname"
      chmod 600 "$runtime_key"
      chmod 644 "$runtime_key_pub"
      echo "Generated runtime SSH key: $runtime_key"
    }

    get_age_keys () {
      echo "[2/6] Converting SSH keys to Age format..."

      boot_age_key=$(echo "$boot_key_pub" | ssh-to-age 2>/dev/null)
      runtime_age_key=$(ssh-to-age < "$runtime_key_pub" 2>/dev/null)

      if [ -z "$boot_age_key" ] || [ -z "$runtime_age_key" ]; then
        echo "Error: Failed to convert SSH keys to Age format" >&2
        exit 1
      fi

      echo "Boot Age key: $boot_age_key"
      echo "Runtime Age key: $runtime_age_key"
    }

    update_sops_config () {
      echo "[3/6] Updating SOPS configuration..."

      cp "$sops_cfg" "$sops_cfg.bak.$(date +%s)"

      # Check if runtime key already exists in config
      if grep -q "$runtime_age_key" "$sops_cfg" 2>/dev/null; then
        echo "Runtime key already in SOPS config, skipping update"
        return 0
      fi

      # Check for inconsistent state - boot key already renamed but no runtime key
      local boot_renamed_count
      boot_renamed_count=$(yq eval "[.keys.[] | select(anchor == \"''${hostname}_boot\")] | length" "$sops_cfg" 2>/dev/null || echo "0")
      if [ "$boot_renamed_count" -gt 0 ]; then
        echo "Error: .sops.yaml is in an inconsistent state" >&2
        echo "Found ''${hostname}_boot anchor but no runtime key" >&2
        echo "" >&2
        echo "This usually means a previous migration attempt was interrupted." >&2
        echo "To fix:" >&2
        echo "  1. Restore from backup: cp .sops.yaml.bak.* .sops.yaml" >&2
        echo "  2. Or manually edit .sops.yaml to rename ''${hostname}_boot back to $hostname" >&2
        echo "  3. Then re-run this script" >&2
        exit 1
      fi

      # Check if boot key exists with original name (expected state)
      local boot_key_count
      boot_key_count=$(yq eval "[.keys.[] | select(anchor == \"$hostname\")] | length" "$sops_cfg" 2>/dev/null || echo "0")
      if [ "$boot_key_count" -eq 0 ]; then
        echo "Error: Boot key with anchor '$hostname' not found in .sops.yaml" >&2
        echo "Cannot proceed with migration - expected to find original boot key" >&2
        exit 1
      fi

      # Everything looks good, rename the boot key
      echo "Renaming boot host key alias to ''${hostname}_boot..."
      yq eval -i \
        "(.keys.[] | select(anchor == \"$hostname\")) anchor = \"''${hostname}_boot\" |
         (.. | select(alias == \"$hostname\")) alias = \"''${hostname}_boot\"" \
        "$sops_cfg"

      # Add runtime key as primary $hostname alias
      echo "Adding runtime host key as $hostname..."
      if ! add-sops-cfg -o "$sops_cfg" alias "$hostname" "$runtime_age_key"; then
        echo "Error: Failed to add runtime key alias to SOPS configuration" >&2
        exit 1
      fi

      # Add the runtime key to the path regex rules
      if ! add-sops-cfg -o "$sops_cfg" path-regex "$hostname" "$sops_file"; then
        echo "Error: Failed to add runtime key to path regex rules" >&2
        exit 1
      fi

      echo "Updated SOPS configuration with both keys"
    }

    # Note: Secrets re-encryption is now a manual step
  # The script will guide the user after completing the automated steps

    show_migration_status () {
      echo ""
      echo "[4/4] Migration Preparation Complete"
      echo ""
      echo "Files updated:"
      echo "  $runtime_key"
      echo "  $runtime_key_pub"
      echo "  $sops_cfg"

      echo ""
      echo "Next steps:"
      echo " 1. Re-encrypt secrets:"
      echo "      nix run .#sops -- updatekeys $sops_file"
      echo ""
      echo " 2. Install runtime key on target:"
      echo "      nix run .#$hostname-install-runtime-key"
      echo ""
      echo " 3. Update configuration.nix SOPS path:"
      echo "      sshKeyPaths = [\"/persist/etc/ssh/ssh_host_ed25519_key\"];"
      echo ""
      echo " 4. Update flake.nix:"
      echo "      runtimeHostKeyPub = ./$hostname/runtime_host_key.pub;"
      echo ""
      echo " 5. Deploy and regenerate known_hosts:"
      echo "      nix run .#deploy-rs"
      echo "      nix run .#$hostname-gen-knownhosts-file"
      echo ""
    }

    main () {
      echo "Preparing $hostname for separated-key migration..."

      validate_prerequisites

      generate_runtime_key
      get_age_keys
      update_sops_config

      show_migration_status
    }

    main
  '';
}
