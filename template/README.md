# Skarabox

This repository originates from https://github.com/ibizaman/skarabox.

Help can be asked by [opening an issue][] in the repository
or by [joining the Matrix channel][].

[opening an issue]: https://github.com/ibizaman/skarabox/issues/new
[joining the Matrix channel]: https://matrix.to/#/#selfhostblocks:matrix.org

## Bootstrapping

Create a directory and download the template.

```bash
$ mkdir myskarabox
$ cd myskarabox
$ nix run github:ibizaman/skarabox#init
```

This last command will also generate the needed secrets
and ask for the password you want for the admin user
for a host named `myskarabox` whose files are located
under the [myskarabox](./myskarabox) folder.

All the files at the root of this new repository
are common to all hosts.

It will finally ask you to fill out two files: [./ip](./ip) and [./system](./system)
and afterwards generate [./known_hosts](./known_hosts) with:

```bash
nix run .#myskarabox-gen-knownhosts-file
```

## Installation

The installation procedure can be followed on a [VM][],
to test the installation process, or on a [real server][].

> [!CAUTION]
> Following the installation procedure on a real server
> WILL ERASE THE CONTENT of any disk on that server.
> Take the time to remove any disk you care about.

[VM]: #a1-test-on-a-vm
[real server]: #a2-install-on-a-real-server

### A.1. Test on a VM

Assuming the [./configuration.nix](./myskarabox/configuration.nix) file is left untouched,
you can now test the installation process on a VM.
This VM has 3 hard drives, one for the OS
and two in raid for the data.

To do that, first we tweak the ports
to more sensible defaults for a VM:

```bash
$ echo 2222 > ./myskarabox/ssh_port
$ echo 2223 > ./myskarabox/ssh_boot_port
```

Then, start the VM:

```bash
$ nix run .#myskarabox-beacon-vm &
```

Now, skip to [step B](#b-run-the-installation-process).

### A.2. Install on a Real Server

_This guide assumes you know how to boot your server on a USB stick._

1. Create the .iso file.

   ```bash
   $ nix build .#myskarabox-beacon
   ```

2. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run .#beacon-usbimager
   ```
   
   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

3. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with user `nixos`.

4. Note down the IP address and disk layout of the server.
   For that, follow the steps that appeared when booting on the USB stick.
   To reprint the steps, run the command `skarabox-help`.

5. Open the [./myskarabox/configuration.nix](./configuration.nix) file and tweak values to match your hardware.

### B. Run the Installation

Create a `./myskarabox/facter.json` file containing
the hardware specification of the host (or the VM) with:

```bash
$ nix run .#myskarabox-get-facter > ./myskarabox/facter.json
```

Add the `./myskarabox/facter.json` to git (run `git add ./myskarabox/facter.json`).

Optionally, if you want to see exactly what `nixos-facter` did find
and will configure, run one or both of:

```bash
$ nix run .#myskarabox-debug-facter-nix-diff
$ nix run .#myskarabox-debug-facter-nvd
```

Now, run the installation process on the host:

```bash
$ nix run .#install-on-beacon .#skarabox
```

The server will reboot into NixOS on its own.
Upon booting, the root partition will need to be decrypted
as outlined in the next section.

## Normal Operations

All commands are prefixed by the hostname, allowing to handle multiple hosts.

1. Decrypt root pool after boot

   ```bash
   $ nix run .#myskarabox-unlock
   ```

   The connection will then disconnect automatically with:
   
   ```
   Connection to <ip> closed.
   ```
   
   This is normal behavior.

2. SSH in

   ```bash
   $ nix run .#myskarabox-ssh
   ```

3. Reboot

   ```bash
   $ nix run .#myskarabox-ssh sudo reboot
   ```
   
   You will then be required to decrypt the hard drives upon reboot as explained above.

4. Deploy an Update

   Modify the [./configuration.nix](./configuration.nix) file then run:
   
   ```bash
   $ nix run .#deploy-rs
   ```

5. Update dependencies

   ```bash
   $ nix flake update
   $ nix run .#deploy-rs
   ```

6. Edit secrets

   ```bash
   $ nix run .#sops secrets.yaml
   ```

## Post Installation Checklist

These items act as a checklist that you should go through to make sure your installation is robust.
How to proceed with each item is highly dependent on which hardware you have so it is hard for Skarabox to give a detailed explanation here.

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
