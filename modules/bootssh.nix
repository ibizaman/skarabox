{ config, lib, pkgs, ... }:
let
  cfg = config.skarabox.boot;

  inherit (lib) getExe mkOption optionals types;

  replyPassword = "${config.boot.initrd.systemd.package}/lib/systemd/systemd-reply-password";

  unlockRootNonTty = pkgs.writeShellApplication {
    name = "skarabox-unlock-root-non-tty";

    text = ''
      # Without a TTY, stdin is the passphrase from the generated unlock command.
      # Read it before talking to systemd so it cannot be echoed by any terminal
      # password prompt.
      if ! IFS= read -r passphrase; then
        echo "No root passphrase received." >&2
        exit 1
      fi

      # Queue the same "continue booting" transaction as above. `--no-block` is
      # required because boot will stop at the root-key prompt; this script has
      # to keep running so it can answer that prompt.
      /bin/systemctl --no-block default

      # systemd publishes pending password requests as ask.* files under
      # /run/systemd/ask-password. Each file describes one prompt and contains a
      # Socket= field naming the Unix socket where password agents should reply.
      attempts=0
      while [ "$attempts" -lt 60 ]; do
        for request in /run/systemd/ask-password/ask.*; do
          if [ ! -e "$request" ]; then
            continue
          fi

          socket=
          while IFS='=' read -r key value; do
            if [ "$key" = Socket ]; then
              socket=$value
              break
            fi
          done < "$request"

          if [ -n "$socket" ]; then
            # systemd-reply-password is systemd's ask-password protocol helper.
            # It reads one line from stdin and sends it to the Socket= endpoint.
            if printf '%s\n' "$passphrase" | ${replyPassword} 1 "$socket"; then
              echo "Root unlock successful; continuing boot."
              exit 0
            fi
          fi
        done

        attempts=$((attempts + 1))
        sleep 1
      done

      echo "Timed out waiting for a systemd password request." >&2
      exit 1
    '';
  };

  unlockRoot = pkgs.writeShellApplication {
    name = "skarabox-unlock-root";

    text = ''
      # An SSH session with a TTY is the manual unlock path. `systemctl default`
      # asks the initrd systemd manager to continue booting by starting its
      # default target. With a TTY attached, the normal systemd password prompt
      # can use the SSH terminal, so hand the session over to systemctl.
      if [ -t 0 ]; then
        exec /bin/systemctl default
      else
        exec ${getExe unlockRootNonTty}
      fi
    '';
  };

in
{
  options.skarabox.boot = {
    sshPort = mkOption {
      type = types.int;
      description = "Port the SSH daemon used to decrypt the root partition listens to.";
      default = 2223;
    };
  };

  config = {
    # Keep this in sync with the stage-2 networkd config in ./network.nix.
    boot.initrd.systemd.network = {
      enable = true;
    } // (if config.skarabox.staticNetwork == null then {
      networks."10-lan" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
        linkConfig.RequiredForOnline = true;
      };
    } else {
      networks."10-lan" = {
        matchConfig.Name = "en*";
        address = [
          "${config.skarabox.staticNetwork.ip}/24"
        ];
        routes = [
          { Gateway = config.skarabox.staticNetwork.gateway; }
        ];
        linkConfig.RequiredForOnline = true;
      };
    });

    boot.initrd.systemd.storePaths = [
      unlockRoot
      unlockRootNonTty
      replyPassword
    ];

    boot.initrd.network = {
      enable = true;
      ssh = {
        enable = true;
        # To prevent ssh clients from freaking out because a different host key is used,
        # a different port for ssh is used.
        port = lib.mkDefault cfg.sshPort;
        hostKeys = lib.mkForce ([ "/boot/host_key" ] ++ (optionals (config.skarabox.disks.rootPool.disk2 != null) [ "/boot-backup/host_key" ]));
        # Only allow remote unlocks, not arbitrary initrd commands.
        authorizedKeys = map (key: ''command="${getExe unlockRoot}" ${key}'') config.skarabox.sshAuthorizedKeys;
      };
    };
  };
}
