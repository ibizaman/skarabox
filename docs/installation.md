<!-- Read these docs at https://installer.skarabox.com -->
# Installation {#installation}

The installation is split in 3 major steps - A, B and C.
Each individual step may be split it in parallel tracks,
depending on your setup.

- Step A: [Repository](#a-repository).
  - If you don't have an existing repository, follow the [A.1. bootstrapping](#a-repository-bootstrapping)) method.
  - If you do have one, follow the [A.2. Add in Existing Repo](#a-repository-existing-repo) method.

- Step B: [Beacon](#b-beacon). The installation can be done on:
  - A [VM](#b-beacon-vm), which is provided by Skarabox.
  - An [on-premise server](#b-beacon-on-premise),
    for which Skarabox provides an ISO file that you can install on a USB stick
    and boot from on your on-premise server
  - A [cloud instance](#b-beacon-cloud),
    which needs nothing special as you should be able to configure
    your cloud VM to have ssh access, for example by booting in rescue mode.

- Step C. Finally, [run the installer](#c-installer).

::: {.warning}
Following the installation procedure on a server
WILL ERASE THE CONTENT of any disk on that server.
Take the time to remove any disk you care about.
:::

## A. Repository {#a-repository}

This will prepare a repository where Skarabox is configured.

### A. (option 1) Bootstrapping {#a-repository-bootstrapping}

Create a directory and download the template.

```bash
$ mkdir myskarabox
$ cd myskarabox
$ nix run github:ibizaman/skarabox?ref=v@VERSION@#init
```

The `#init` command accepts arguments, add `-- -h` so see them.

The `#init` command by default asks for the password you want for the admin user
and will generate all other secrets.
The hostname will be `myskarabox` and the files located
under the [./myskarabox](@REPO@/template/myskarabox) folder.

All the files at the root of this new repository
are common to all hosts.

It will finally ask you to fill out two options: `skarabox.hosts.<name>.ip` and `skarabox.hosts.<name>.system`
in  [./configuration.nix](@REPO@/template/myskarabox/configuration.nix)
then afterwards to generate [./known_hosts](@REPO@/template/myskarabox/known_hosts).
Detailed instructions will be shown in Step B.

### A. (option 2) Add in Existing Repo {#a-repository-existing-repo}

::: {.note}
For a concrete example, look at the commit history of
[this repo](https://github.com/ibizaman/nix-starter-configs-skarabox)
which shows how to add a host managed by Skarabox
to a repository using [nix-starter-configs](https://github.com/Misterio77/nix-starter-configs/).
:::

1. Transform the outputs in a flake-parts module like outlined [in the official tutorial][tutorial].
   In short, make your `flake.nix` look like the [template][] one.

   [tutorial]: https://flake.parts/getting-started.html#existing-flake
   [template]: @REPO@/template/flake.nix

2. Create Sops main key file named `sops.key`, if you don't have one already:

   `nix run .#sops-create-main-key`.

3. Add Sops main key to Sops config file `.sops.yaml`:

   `nix run .#sops-add-main-key`.

4. Create config for target host `myskarabox` in folder `./myskarabox`:

   `nix run .#gen-new-host myskarabox`.

   Tweak [./myskarabox/configuration.nix][]
   to change for example the username.
   The username will also be used as the user in the beacon.

   [./myskarabox/configuration.nix]: @REPO@/template/myskarabox/configuration.nix

   Now, pick one of the Step B underneath.

## B. Beacon {#b-beacon}

### B. (option 1) Test on a VM {#b-beacon-vm}

Assuming the [./myskarabox/configuration.nix][] file is left untouched,
you can now test the installation process on a VM.
To do that, first we tweak some options
for more sensible defaults for a VM:

```bash
skarabox.hosts.<name> = {
  system = "x86_64-linux";
  ip = "127.0.0.1";
};
```

Generate the known hosts file:

```bash
nix run .#myskarabox-gen-knownhosts-file
```

This file is for the final installed system. The beacon VM has its own temporary
SSH host key, which will be trusted after the VM starts.

Then, start the VM:

```bash
$ nix run .#myskarabox-beacon-vm &
```

Trust the beacon SSH host key:

```bash
$ nix run .#myskarabox-beacon-trust
```

For info, this VM has 4 hard drives:

- `/dev/nvme0`
- `/dev/nvme1`
- `/dev/sda`
- `/dev/sdb`

Now, skip to [step C](#c-installer).

### B. (option 2) Install on an On-Premise Server {#b-beacon-on-premise}

_This guide assumes you know how to boot your server on a USB stick.
Usually this involves opening your computer's BIOS and selecting the USB stick._

The beacon can either connect to the local network
and/or setup its own WiFi hotspot with SSID `Skarabox`.
Connecting to the beacon will thus depend on the chosen method.

1. Choose either DHCP or static IP configuration.

   In [./myskarabox/configuration.nix][], set the configuration of the server.
   The default is DHCP:

   ```nix
   skarabox.staticNetwork = null;
   ```

   To setup a static IP, replace the `null` value with something like:

   ```nix
   skarabox.staticNetwork = {
     ip = "192.168.1.30";
     gateway = "192.168.1.1";
   }
   ```

   The same configuration will be used in the beacon.

2. Modify the ssh ports if needed.

   In [./myskarabox/configuration.nix][], set the ssh ports the OpenSSH server will listen on.
   The default is:

   ```nix
   skarabox = {
     sshPort = 2222;
     boot.sshPort = 2223;
   }
   ```

   In [./flake.nix][], set the ssh ports that will be used to connect to the server.
   The default is the same as above:

   ```nix
   skarabox.hosts.<name> = {
     sshPort = 2222;
     sshBootPort = 2223;
   }
   ```

   Usually, they should be the same, but if you access the server through a router with port forwarding,
   they can differ.

   [./flake.nix]: @REPO@/template/flake.nix.

3. Setup system in the [./flake.nix][].

   ```nix
   skarabox.hosts.<name> = {
     system = "x86_64-linux";
   }
   ```

4. Create the .iso file.

   ```bash
   $ nix build .#myskarabox-beacon
   ```

5. Copy the .iso file to a USB key. This WILL ERASE THE CONTENT of the USB key.

   ```bash
   $ nix run .#beacon-usbimager
   ```

   - Select `./result/iso/beacon.iso` file in row 1 (`...`).
   - Select USB key in row 3.
   - Click write (arrow down) in row 2.

6. Plug the USB stick in the server. Choose to boot on it.

   You will be logged in automatically with the user `skarabox.username`.

7. Setup IP to reach the server in [./flake.nix][].

   If a static IP was used, it will be the same as the one in `skarabox.staticNetwork.ip`.

   If DHCP was used, first find the IP given to the beacon
   by following the steps that appeared when booting on the USB stick.
   To reprint the steps, run the command `skarabox-help`.
   For example, if the IP is `192.168.1.30`:

   ```nix
   skarabox.hosts.<name> = {
     ip = "192.168.1.30";
   }
   ```

   It is also possible to use a hostname as long as it can resolve to the correct IP,
   for example if you set up your ssh config accordingly.

8. Generate the known host file for the final installed system:

   ```bash
   $ nix run .#myskarabox-gen-knownhosts-file
   ```

   Redo this step if any of the ssh port or IP under the flake `skarabox.hosts.<name>` option changes.

9. Trust the beacon SSH host key:

   ```bash
   $ nix run .#myskarabox-beacon-trust
   ```

   This writes `./myskarabox/beacon_known_hosts`, which is local trust state for
   the temporary beacon environment. If the beacon is rebooted and its key
   changes, rerun the command with `--force` after verifying the new fingerprint.

10. Open the various files just to see if everything looks good.

### B. (option 3) Install on a Cloud Server {#b-beacon-cloud}

No need for the beacon here.
You just need to start the instance and enable ssh access.
The easiest is usually to boot in rescue mode.

Retrieve the IP of the server, then update the values:

```nix
skarabox.hosts.<name> = {
  system = "x86_64-linux";
  ip = "192.168.1.30";
}
```

Generate the known hosts file:

```bash
nix run .#myskarabox-gen-knownhosts-file
```

This file is for the final installed system. To trust the cloud rescue
environment used for installation, run:

```bash
nix run .#myskarabox-beacon-trust
```

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere

## C. Run the Installer {#c-installer}

Create a `./myskarabox/facter.json` file containing
the hardware specification of the host (or the VM) with:

```bash
$ nix run .#myskarabox-beacon-get-facter > ./myskarabox/facter.json
```

Add the `./myskarabox/facter.json` to git (run `git add ./myskarabox/facter.json`).

Optionally, if you want to see exactly what `nixos-facter` did find
and will configure, run one or both of:

```bash
$ nix run .#myskarabox-debug-facter-nix-diff
$ nix run .#myskarabox-debug-facter-nvd
```

3. Run the installer

Now, run the installation process on the target host:

```bash
$ nix run .#myskarabox-beacon-install
```

The server will reboot into NixOS on its own.
Upon booting, the root partition will need to be decrypted
as outlined in the [Normal Operations](./normal-operations.html#decrypt-root) section.
But first, read the next section.

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
  Router usually allow to "pin" a lease.
  This is not needed if the IP was set statically above.
- Enable port redirection for ports to the server IP:
  - 80 to 80.
  - 443 to 443.
  - `skarabox.sshPort` to `skarabox.sshPort` (default 2222) to be able to ssh into your server from abroad.
  - `skarabox.sshBootPort` to `skarabox.sshBootPort` 2223 to be able to start the server from abroad.

To check if this setup works,
you can connect to another network (like using the tethered connection from your phone or connecting to another WiFi network)
and then ssh into your server like shown in the [Normal Operations](./normal-operations.html#ssh) section,
but instead of using the IP address, use the domain name in `skarabox.hosts.<name>.ip`.

### Add Services {#checklist-services}

I do recommend using the sibling project [SelfHostBlocks](https://github.com/ibizaman/selfhostblocks) to setup services like Vaultwarden, Nextcloud and others.

The [flake template][template] is wired to use SelfHostBlocks already.
