<!-- Read these docs at https://installer.skarabox.com -->
# Installation {#installation}

If you don't have an existing repository, choose the [bootstrapping][]
method. If you do have one you want to integrate with Skarabox,
follow the [Add in Existing Repo][] method.

The installation procedure can be followed on a [VM][],
to test the installation process, on an [on-premise server][]
or on a [cloud instance][].
For the first option, this flake template will create a suitable VM to
test on and for the second, an ISO file will be produced that you
can install on a USB stick and boot from on your on-premise server.

Finally, [run the installer][].

::: {.warning}
Following the installation procedure on a server
WILL ERASE THE CONTENT of any disk on that server.
Take the time to remove any disk you care about.
:::

[bootstrapping]: #bootstrapping
[Add in Existing Repo]: #existing-repo
[VM]: #vm
[On-Premise Server]: #on-premise
[Cloud Instance]: #cloud
[Run the Installer]: #run-installer

## A. (option 1) Bootstrapping {#bootstrapping}

Create a directory and download the template.

```bash
$ mkdir myskarabox
$ cd myskarabox
$ nix run github:ibizaman/skarabox?ref=@VERSION@#init -- -n myskarabox
```

This last command will also generate the needed secrets
and ask for the password you want for the admin user
for a host named `myskarabox` whose files are located
under the [myskarabox](@REPO@/template/myskarabox) folder.

All the files at the root of this new repository
are common to all hosts.

It will finally ask you to fill out two files: [./ip](@REPO@/template/myskarabox/ip)
and [./system](@REPO@/template/myskarabox/system):
and afterwards generate [./known_hosts](@REPO@/template/myskarabox/known_hosts). This will be done in Step B.

## A. (option 2) Add in Existing Repo {#existing-repo}

::: {.info}
For a concrete example, look at the commit history of
[this repo](https://github.com/ibizaman/nix-starter-configs-skarabox)
which shows how to add a host managed by Skarabox
to a repository using [nix-starter-configs](https://github.com/Misterio77/nix-starter-configs/).
:::

1. Transform the outputs in a flake-parts module like outlined [in the official tutorial][tutorial].
   In short, make your `flake.nix` look like the [template][] one.

   [tutorial]: https://flake.parts/getting-started.html#existing-flake
   [template]: @REPO@/template/flake.nix

2. Create Sops main key `sops.key` if needed:

   `nix run .#sops-create-main-key`.

3. Add Sops main key to Sops config `.sops.yaml`:

   `nix run .#sops-add-main-key`.

4. Create config for host `myskarabox` in folder `./myskarabox`:

   `nix run .#gen-new-host myskarabox`.

   Tweak [./myskarabox/configuration.nix][]
   to change for example the username.
   The username will also be used as the user in the beacon.

   [./myskarabox/configuration.nix]: @REPO@/template/myskarabox/configuration.nix

   Now, pick one of the Step B underneath.

## B. (option 1) Test on a VM {#vm}

Assuming the [./myskarabox/configuration.nix][] file is left untouched,
you can now test the installation process on a VM.
This VM has 3 hard drives, one for the OS
and two in raid for the data.

To do that, first we tweak the ports
to more sensible defaults for a VM:

```bash
$ echo 127.0.0.1 > ./myskarabox/ip
$ echo x86_64-linux > ./myskarabox/system
$ echo 2222 > ./myskarabox/ssh_port
$ echo 2223 > ./myskarabox/ssh_boot_port
```

Generate the known hosts file:

```bash
nix run .#myskarabox-gen-knownhosts-file
```

Then, start the VM:

```bash
$ nix run .#myskarabox-beacon-vm &
```

For info, this VM has 4 hard drives:

- `/dev/nvme0`
- `/dev/nvme1`
- `/dev/sda`
- `/dev/sdb`

Now, skip to [step C](#run-installer).

## B. (option 2) Install on an On-Premise Server {#on-premise}

_This guide assumes you know how to boot your server on a USB stick._

1. Setup IP and system.

   ```bash
   $ echo 192.168.1.30 > ./myskarabox/ip
   $ echo x86_64-linux > ./myskarabox/system
   $ nix run .#myskarabox-gen-knownhosts-file
   ```

   Choose an IP that you can access in your network
   and the system that matches your server.

   The IP used here will be statically assigned to the beacon
   and will be used to setup the WiFi hotspot from the beacon,
   if a WiFi card is enabled.
   Having a same IP for all makes the installation procedure much easier.

   You can also setup a static IP for the server itself by enabling
   the `skarabox.staticNetwork` option in your [./myskarabox/configuration.nix][] file.

2. Create the .iso file.

   ```bash
   $ nix build .#myskarabox-beacon
   ```

3. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run .#beacon-usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

4. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with the user `skarabox.username`.

5. Note down the IP address and disk layout of the server.
   For that, follow the steps that appeared when booting on the USB stick.
   To reprint the steps, run the command `skarabox-help`.

6. Open the [./myskarabox/configuration.nix][] file and tweak values to match your hardware.

## B. (option 3) Install on a Cloud Server {#cloud}

No need for the beacon here.
As long as you can boot the instance, [nixos-anywhere][] will
take care of installing NixOS on it. For Hetzner for example,
you can start in recovery mode.

Retrieve the IP of the server, then:

```bash
echo <ip> > myskarabox/ip
echo x86_64-linux > myskarabox/system
nix run .#myskarabox-gen-knownhosts-file
```

Replace the system with the correct one for your instance.

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere

## C. Run the Installer {#run-installer}

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
$ nix run .#myskarabox-install-on-beacon
```

The server will reboot into NixOS on its own.
Upon booting, the root partition will need to be decrypted
as outlined in the next section.

## Post Installation Checklist {#checklist}

These items act as a checklist that you should go through to make sure your installation is robust.
How to proceed with each item is highly dependent on which hardware you have so it is hard for Skarabox to give a detailed explanation here.

### Domain Name {#checklist-domain}

Get your external IP Address by connecting to your home network and going to [https://api.ipify.org/](https://api.ipify.org/).

- Buy a cheap domain name.
  I recommend [https://porkbun.com/](https://porkbun.com/) because I use it and know it works but others work too.
- Configure the domain's DNS entries to have:
  - A record: Your domain name to your external IP Address.
  - A record: `*` (yes, a literal "asterisk") to your external IP Address.

To check if this setup works, you will first need to go through the step below too.

### Router Configuration {#checklist-router}

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

### Add Services {#checklist-services}

I do recommend using the sibling project [SelfHostBlocks](https://github.com/ibizaman/selfhostblocks) to setup services like Vaultwarden, Nextcloud and others.

The [flake template][template] is wired to use SelfHostBlocks already.
