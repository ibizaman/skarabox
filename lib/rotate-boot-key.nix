{
  pkgs,
  name,
  cfg,
  ssh,
}:
pkgs.writeShellApplication {
  name = "rotate-boot-key";

  runtimeInputs = [
    ssh
    pkgs.openssh     # ssh-keygen
    pkgs.coreutils   # cat
  ];

  text = ''
    set -euo pipefail

    # From flake configuration
    hostname="${name}"
    private_key_path="${cfg.hostKeyPath}"

    usage () {
      cat <<USAGE
Usage: $0 [-h]

Rotates the boot SSH key with secure partition wipe for host: ${name}

WARNING: Destructive operation - wipes boot partition with dd + TRIM.
Old key becomes unrecoverable after block-level overwrite.

Process:
  1. Backup /boot to tmpfs
  2. Unmount and securely wipe partition (dd + TRIM/discard)
  3. Recreate filesystem and restore boot files with new key
  4. Reinstall bootloader
  5. Handle mirrored boot partitions if present

Prerequisites:
  - Must run after deploying separated-key configuration
  - Target host must be reachable via runtime SSH key

Options:
  -h: Shows this usage
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

    # Validate
    if [ ! -f "$private_key_path" ]; then
      echo "Error: $private_key_path not found" >&2
      exit 1
    fi

    # https://stackoverflow.com/a/29436423/1013628
    yes_or_no () {
      while true; do
        echo -ne "\e[1;31mWARNING:\e[0m "
        read -rp "$* [y/N]: " yn
        case $yn in
          [Yy]*) return 0 ;;
          [Nn]*|"") echo "Aborted." ; exit 0 ;;
        esac
      done
    }

    # Show fingerprints
    echo "Boot SSH Key Rotation for $hostname"
    echo "===================================="
    echo ""
    old_key_fp=$(ssh "sudo ssh-keygen -l -f /boot/host_key")
    new_key_fp=$(ssh-keygen -l -f "$private_key_path")

    echo "Old key: $old_key_fp"
    echo "New key: $new_key_fp"
    echo ""

    # Validate keys are different
    if [ "$old_key_fp" = "$new_key_fp" ]; then
      echo "❌ ERROR: Old and new keys are identical!" >&2
      echo "" >&2
      echo "You must generate a new key before rotating:" >&2
      echo "  ssh-keygen -t ed25519 -f $private_key_path -N \"\"" >&2
      echo "" >&2
      exit 1
    fi

    echo "This will:"
    echo " 1. Backup /boot contents to tmpfs"
    echo " 2. Securely wipe the boot partition (dd + TRIM/discard)"
    echo " 3. Recreate the filesystem"
    echo " 4. Restore boot files with new SSH key"
    echo " 5. Reinstall bootloader"
    echo ""
    echo "⚠️  DESTRUCTIVE: Old key will be unrecoverable (block-level wipe)"
    echo ""
    yes_or_no "Continue with rotation?"

    # Remote script - uses system tools already on NixOS
    echo ""
    echo "Running rotation on remote system..."
    echo ""

    # Read the private key content
    private_key_content=$(cat "$private_key_path")

    # Execute remote script with key embedded
    # shellcheck disable=SC2087
    ssh bash <<REMOTE_SCRIPT
      set -euo pipefail

      # Private key content embedded in script
      private_key_content='$private_key_content'

      # Discover current boot partition configuration
      echo "[1/8] Discovering current partition layout..."
      boot_dev=\$(findmnt -n -o SOURCE /boot)
      boot_fstype=\$(lsblk -ndo FSTYPE "\$boot_dev")
      boot_label=\$(lsblk -ndo LABEL "\$boot_dev" || echo "")
      boot_mount_opts=\$(findmnt -n -o OPTIONS /boot)

      # Check for mirrored boot
      if findmnt /boot-backup &>/dev/null; then
        has_backup=1
        backup_dev=\$(findmnt -n -o SOURCE /boot-backup)
        echo "     Found mirrored boot: \$backup_dev"
      else
        has_backup=0
      fi

      echo "     Device: \$boot_dev"
      echo "     Filesystem: \$boot_fstype"
      echo "     Label: \''${boot_label:-<none>}"
      echo "     Mount options: \$boot_mount_opts"

      # Validate it's vfat (we only handle FAT filesystems)
      if [ "\$boot_fstype" != "vfat" ]; then
        echo "Error: Expected vfat filesystem, found \$boot_fstype" >&2
        exit 1
      fi

      # Backup boot contents
      echo ""
      echo "[2/8] Backing up boot files to tmpfs..."
      mkdir -p /tmp/boot-backup
      sudo rsync -a /boot/ /tmp/boot-backup/ --exclude=host_key
      echo "     \$(du -sh /tmp/boot-backup | cut -f1) backed up"

      # Unmount and wipe
      echo ""
      echo "[3/8] Unmounting /boot..."
      sudo umount /boot

      echo ""
      echo "[4/8] Securely wiping \$boot_dev (this may take a moment)..."
      sudo dd if=/dev/zero of="\$boot_dev" bs=1M status=progress 2>&1 || true
      echo "     → Block-level wipe complete"

      # Issue TRIM/discard for SSDs (helps with wear-leveling)
      if command -v blkdiscard >/dev/null 2>&1; then
        echo "     → Issuing TRIM/discard..."
        sudo blkdiscard "\$boot_dev" 2>&1 || echo "     → (TRIM not supported, skipping)"
      fi

      # Recreate filesystem with discovered parameters
      echo ""
      echo "[5/8] Recreating filesystem..."
      if [ -n "\$boot_label" ]; then
        sudo mkfs.vfat -F 32 -n "\$boot_label" "\$boot_dev"
      else
        sudo mkfs.vfat -F 32 "\$boot_dev"
      fi

      # Mount with discovered options
      echo "     Mounting..."
      sudo mount -o "\$boot_mount_opts" "\$boot_dev" /boot

      # Restore and install new key
      echo ""
      echo "[6/8] Restoring boot files and installing new key..."
      sudo rsync -a /tmp/boot-backup/ /boot/
      echo "\$private_key_content" | sudo install -m 600 /dev/stdin /boot/host_key
      echo "     New key installed"

      # Handle mirrored boot
      if [ "\$has_backup" -eq 1 ]; then
        echo "     → Processing mirrored boot partition..."
        sudo umount /boot-backup
        sudo dd if=/dev/zero of="\$backup_dev" bs=1M status=progress 2>&1 || true
        if command -v blkdiscard >/dev/null 2>&1; then
          sudo blkdiscard "\$backup_dev" 2>&1 || true
        fi
        if [ -n "\$boot_label" ]; then
          sudo mkfs.vfat -F 32 -n "\$boot_label" "\$backup_dev"
        else
          sudo mkfs.vfat -F 32 "\$backup_dev"
        fi
        sudo mount -o "\$boot_mount_opts" "\$backup_dev" /boot-backup
        sudo rsync -a /tmp/boot-backup/ /boot-backup/
        echo "\$private_key_content" | sudo install -m 600 /dev/stdin /boot-backup/host_key
        echo "     → Mirror synchronized"
      fi

      # Reinstall bootloader using the system's current bootloader configuration
      echo ""
      echo "[7/8] Reinstalling bootloader..."
      if [ -x "/run/current-system/bin/switch-to-configuration" ]; then
        sudo /run/current-system/bin/switch-to-configuration boot || {
          echo "     Warning: Bootloader reinstall may have failed, but boot contents are restored"
        }
      else
        echo "     Warning: Could not find bootloader installer, boot files restored but EFI may need manual update"
      fi

      echo ""
      echo "[8/8] Cleaning up..."
      sudo rm -rf /tmp/boot-backup

      echo ""
      echo "Rotation complete!"
REMOTE_SCRIPT

    # Verify
    echo ""
    echo "Verification"
    echo "============"
    actual_fp=$(ssh "sudo ssh-keygen -l -f /boot/host_key")
    expected_fp=$(ssh-keygen -l -f "$private_key_path")
    echo "Expected: $expected_fp"
    echo "Actual:   $actual_fp"

    if [ "$expected_fp" = "$actual_fp" ]; then
      echo "Key rotation verified successfully"
    else
      echo "Warning: Key fingerprints do not match!" >&2
      exit 1
    fi

    echo ""
    echo "Next steps:"
    echo " 1. Update known_hosts:"
    echo "      nix run .#${name}-gen-knownhosts-file"
    echo ""
    echo " 2. Reboot to activate:"
    echo "      nix run .#${name}-ssh sudo reboot"
    echo ""
  '';
}
