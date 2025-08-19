# Normal Operations {#normal-operations}

All commands are prefixed by the hostname, allowing to handle multiple hosts.

## Decrypt `root` pool after boot {#decrypt-root}

   ```bash
   $ nix run .#myskarabox-unlock
   ```

   The connection will then disconnect automatically with no message.
   This is normal behavior.

## SSH in {#ssh}

   ```bash
   $ nix run .#myskarabox-ssh
   ```

## Reboot {#reboot}

   ```bash
   $ nix run .#myskarabox-ssh sudo reboot
   ```

   You will then be required to decrypt the hard drives upon reboot as explained above.

## Deploy an Update {#deploy-update}

   Modify the [./configuration.nix](@REPO@/template/myskarabox/configuration.nix) file then run one of the following snippets:

   To deploy with [deploy-rs](https://github.com/serokell/deploy-rs),
   first import the flake module `skarabox.flakeModules.deploy-rs` as shown in the template [flake.nix][] then:
   ```bash
   $ nix run .#deploy-rs
   ```

   [flake.nix]: @REPO@/template/flake.nix

   To deploy with [colmena](https://github.com/zhaofengli/colmena),
   first import the flake module `skarabox.flakeModules.colmena` as shown in the template [flake.nix][] then:
   ```bash
   $ nix run .#colmena apply
   ```

   Specific options for deploy-rs or colmena can be added by appending
   a double dash followed by the arguments, like so:

   ```bash
   $ nix run .#colmena apply -- --on myskarabox
   ```

## Update dependencies {#update-dependencies}

   ```bash
   $ nix flake update
   $ nix run .#deploy-rs
   ```

   To pin Skarabox to the latest release, edit the [flake.nix][]
   and replace `?ref=<oldversion>` with `?ref=@VERSION@`,
   then run:
   
   ```bash
   $ nix flake update skarabox
   ```

   [flake.nix]: @REPO@/template/flake.nix

## Edit secrets {#edit-secrets}

   ```bash
   $ nix run .#sops ./myskarabox/secrets.yaml
   ```

## Add other hosts {#add-host}

   ```bash
   $ nix run .#gen-new-host otherhost.
   ```

   and copy needed config in [flake.nix][].

## Rotate host key {#rotate-host-key}

   ```bash
   $ ssh-keygen -f ./myskarabox/host_key
   $ nix run .#add-sops-cfg -- -o .sops.yaml alias myskarabox $(ssh-to-age -i ./myskarabox/host_key.pub)
   $ nix run .#deploy-rs
   $ nix run .#baryum-gen-knownhosts-file
   ```
