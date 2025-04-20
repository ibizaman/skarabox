# Skarabox

This repository originates from https://github.com/ibizaman/skarabox.

## Bootstrapping

Create a directory and download the template.

```bash
$ mkdir myskarabox
$ cd myskarabox
$ nix run github:ibizaman/skarabox#init
```

This command will also generate the needed secrets.

It will ask you to fill out two files: `./ip` and `./system`.
If unsure, the IP of the server can be found when booting on the beacon
as explained in [the Installation section](#Installation).

## Test on a VM

Assuming the `configuration.nix` file is left untouched,
after generating all needed files,
you can test the installation process on a VM.
This VM has 3 hard drives, one for the OS
and two in raid for the data.

To do that, first start the VM:

```bash
echo 2222 > ssh_port
echo 2223 > ssh_boot_port
nix run .#demo-beacon 2222-:2222 2223-:2223
```

_We override the default ports. When done testing on the VM,
you can change back the ports to 22 and 2222 respectively._

Then start the installation process:


```bash
nix run .#install-on-beacon 127.0.0.1 2222 .#skarabox
```

When the VM rebooted, you'll need to decrypt the root partition
as explained in the next section.

## Installation

_Following the steps here WILL ERASE THE CONTENT of any disk on that server._

1. Boot on the NixOS installer. You just need to boot, there is nothing to install just yet.

   1. First, create the .iso file.

   ```bash
   $ nix build .#beacon
   ```

   2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run .#usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

   3. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

   4. Note down the IP address and disk layout of the server.
      For that, follow the steps that appeared when booting on the USB stick.
      To reprint the steps, run the command `skarabox-help`.

   5. Open the `configuration.nix` file and tweak values to match you hardware.
      Also, open the other files and see how to generate them too.
      All the instructions are included.

   Note the `root_passphrase` file contains the passphrase
   that will need to be provided every time the server boots up.

2. Run the installation process

   1. Run the following command replacing `<ip>` with the IP address you got in the previous step.

   ```bash
   $ nix run .#install-on-beacon <ip> 22 .#skarabox
   ```

   2. The server will reboot into NixOS on its own.

   3. Decrypt the SSD and the Hard Drives.

   Run the following command.

   ```bash
   $ nix run .#boot-ssh
   ```

   You will be prompted to enter the root passphrase.
   Copy the content of the `root_passphrase` file and paste it and press Enter.
   No `*` will appear upon pasting but just press Enter.

   ```bash
   Enter passphrase for 'root':
   ```

   The connection will disconnect automatically.
   This is normal behavior.

   ```bash
   Connection to <ip> closed.
   ```

   Now, the hard drives are decrypted and the server continues to boot.

   It's a good idea to make sure you can SSH in correctly, at least the first time:

   ```bash
   nix run .#ssh
   ```

## Normal Operations

1. Decrypt root pool after boot

```bash
nix run .#boot-ssh
```

Then, enter the `./root_passphrase`.

2. Login

```bash
nix run .#ssh
```

3. Reboot

```bash
nix run .#ssh sudo reboot
```

You will then be required to decrypt the hard drives as explained above.

4. Deploy an Update

Modify the `./configuration.nix` file then run:

```bash
nix run .#deploy
```

5. Update dependencies

```bash
nix flake update
nix run .#deploy
```

6. Edit secrets

```bash
nix run .#sops secrets.yaml
```

## Post Installation Checklist

These items act as a checklist that you should go through to make sure your installation is robust.
How to proceed with each item is highly dependent on which hardware you have so it is hard for Skarabox to give a detailed explanation here.
If you have any question, don't hesitate to open a [GitHub issue](https://github.com/ibizaman/skarabox/issues/new).

### Secrets with SOPS

To setup secrets with SOPS, you must retrieve the box's host key with:

```bash
$ ssh-keyscan -p 22 -t ed25519 -4 <ip>
<ip> ssh-ed25519 AAAAC3NzaC1lXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Then transform it to an `age` key with:

```bash
$ nix shell .#ssh-to-age --command sh -c "echo ssh-ed25519 AAAAC3NzaC1lXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX | ssh-to-age"
age10gclXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

Finally, allow that key to decrypt the secrets file:

```bash
SOPS_AGE_KEY_FILE=sops.key \
  nix run --impure .#sops -- --config .sops.yaml -r -i \
  --add-age "age10gclXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" \
  secrets.yaml
```

### Domain Name

Get your external IP Address by connecting to your home network and going to [https://api.ipify.org/](https://api.ipify.org/).

- Buy a cheap domain name.
  I recommend [https://porkbun.com/](https://porkbun.com/) because I use it and know it works but others work too.
- Configure the domain's DNS entries to have:
  - A record: Your domain name to your external IP Address.
  - A record: `*` (yes, a literal "asterisk") to your external IP Address.

To check if this setup works, you will first need to go through the step below too.

### Router Configuration

These items should happen on your router.
Usually, connecting to it is done by entering one of the following IP addresses in your browser: `192.168.1.1` or `192.168.1.254`.

- Reduce the DHCP pool to the bounds .100 to .200, inclusive.
  This way, you are left with some space to statically allocate some IPs.
- Statically assign the IP address of the server.
- Enable port redirection for ports to the server IP:
  - 80 to 80.
  - 443 to 443.
  - A random port to 22 to be able to ssh into your server from abroad.
  - A random port to 2222 to be able to start the server from abroad.

To check if this setup works,
you can connect to another network (like using the tethered connection from your phone or connecting to another WiFi network)
and then ssh into your server like above,
but instead of using the IP address, use the domain name in `./ip`.

### Add Services

I do recommend using the sibling project [Self Host Blocks](https://github.com/ibizaman/selfhostblocks) to setup services like Vaultwarden, Nextcloud and others.
