# Skarabox

<!--toc:start-->
- [Installation Procedure](#installation-procedure)
  - [A. (option 1) Bootstrapping](#a-option-1-bootstrapping)
  - [A. (option 2) Add in Existing Repo](#a-option-2-add-in-existing-repo)
  - [B. (option 1) Test on a VM](#b-option-1-test-on-a-vm)
  - [B. (option 2) Install on an On-Premise Server](#b-option-2-install-on-an-on-premise-server)
  - [B. (option 3) Install on a Cloud Server](#b-option-3-install-on-a-cloud-server)
  - [C. Run the Installer](#c-run-the-installer)
- [Normal Operations](#normal-operations)
- [Options](#options)
- [Post Installation Checklist](#post-installation-checklist)
  - [Domain Name](#domain-name)
  - [Router Configuration](#router-configuration)
  - [Add Services](#add-services)
  - [Recovery](#recovery)
<!--toc:end-->

This repository originates from https://github.com/ibizaman/skarabox.

Help can be asked by [opening an issue][issue] in the repository
or by [joining the Matrix channel][matrix].

[issue]: https://github.com/ibizaman/skarabox/issues/new
[matrix]: https://matrix.to/#/#selfhostblocks:matrix.org

## Installation Procedure

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

> [!CAUTION]
> Following the installation procedure on a server
> WILL ERASE THE CONTENT of any disk on that server.
> Take the time to remove any disk you care about.

[bootstrapping]: #a-option-1-bootstrapping
[Add in Existing Repo]: #a-option-2-add-in-existing-repo
[VM]: #b-option-1-test-on-a-vm
[On-Premise Server]: #b-option-2-install-on-an-on-premise-server
[Cloud Instance]: #b-option-3-install-on-a-cloud-instance
[Run the Installer]: #c-run-the-installer

### A. (option 1) Bootstrapping

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

### A. (option 2) Add in Existing Repo

Add inputs:

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  skarabox.url = "github:ibizaman/skarabox";

  nixos-generators.url = "github:nix-community/nixos-generators";
  nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

  nixos-anywhere.url = "github:nix-community/nixos-anywhere";
  nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";

  nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
  flake-parts.url = "github:hercules-ci/flake-parts";
  deploy-rs.url = "github:serokell/deploy-rs";
  sops-nix.url = "github:Mic92/sops-nix";
};
```

Transform the outputs in a flake-parts module like outlined [in the official tutorial][tutorial].

[tutorial]: https://flake.parts/getting-started.html#existing-flake

In short:
1. Add `mkFlake` around the outputs attrset:

```nix
outputs = inputs@{ self, skarabox, sops-nix, nixpkgs, flake-parts, ... }: flake-parts.lib.mkFlake { inherit inputs; } (let
in {
});
```

2. Add the `systems` you want to handle:

```nix
systems = [
  "x86_64-linux"
  "aarch64-linux"
];
```

3. Import Skarabox' flake module:

```nix
imports = [
  skarabox.flakeModules.default
];
```

4. Add NixOS module importing your configuration.

```nix
flake = {
  nixosModules = {
    myskarabox = {
      imports = [
        ./myskarabox/configuration.nix
      ];
    };
  };
};
```

5. Add a Skarabox managed host, here called `myskarabox`
   that uses the above NixOS module:

```nix
skarabox.hosts = {
  myskarabox = {
    system = "x86_64-linux";
    hostKeyPub = ./myskarabox/host_key.pub;
    ip = ./myskarabox/ip;
    sshPublicKey = ./myskarabox/ssh.pub;
    knownHosts = ./myskarabox/known_hosts;

    modules = [
      sops-nix.nixosModules.default
      self.nixosModules.myskarabox
    ];
  };
};
```

6. Create Sops main key `sops.key` if needed:

   `nix run .#sops-create-main-key`.

7. Add Sops main key to Sops config `.sops.yaml`:

   `nix run .#sops-add-main-key`.

8. Create config for host `myskarabox` in folder `./myskarabox`:

   `nix run .#gen-new-host myskarabox`.

   Tweak `./myskarabox/configuration.nix` to change for example the username.
   The username will also be used as the user in the beacon.

### B. (option 1) Test on a VM

Assuming the [./configuration.nix](./myskarabox/configuration.nix) file is left untouched,
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

Then, start the VM:

```bash
$ nix run .#myskarabox-beacon-vm &
```

For info, this VM has 4 hard drives:

- `/dev/nvme0`
- `/dev/nvme1`
- `/dev/sda`
- `/dev/sdb`

Now, skip to [step B](#b-run-the-installation-process).

### B. (option 2) Install on an On-Premise Server

_This guide assumes you know how to boot your server on a USB stick._

1. Setup IP and system.

   ```bash
   $ echo 192.168.1.30 > ./myskarabox/ip
   $ echo x86_64-linux > ./myskarabox/system
   ```

   Choose an IP that you can access in your network
   and the system that matches your server.

   The IP used here will be statically assigned to the beacon
   and will be used to setup the WiFi hotspot from the beacon,
   if a WiFi card is enabled.
   Having a same IP for all makes the installation procedure much easier.

   You can also setup a static IP for the server itself by enabling
   the `skarabox.staticNetwork` option in your `./myskarabox/configuration.nix` file.

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

6. Open the [./myskarabox/configuration.nix](./configuration.nix) file and tweak values to match your hardware.

### B. (option 3) Install on a Cloud Server

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

### C. Run the Installer

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

## Normal Operations

All commands are prefixed by the hostname, allowing to handle multiple hosts.

1. Decrypt `root` pool after boot

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

   Modify the [./configuration.nix](./configuration.nix) file then run one of the following snippets:

   To deploy with [deploy-rs](https://github.com/serokell/deploy-rs):
   ```bash
   $ nix run .#deploy-rs
   ```

   To deploy with [colmena](https://github.com/zhaofengli/colmena):
   ```bash
   $ nix run .#colmena apply
   ```

   Specific options for deploy-rs or colmena can be added by appending
   a double dash followed by the arguments, like so:

   ```bash
   $ nix run .#colmena apply -- --on myskarabox
   ```

5. Update dependencies

   ```bash
   $ nix flake update
   $ nix run .#deploy-rs
   ```

6. Edit secrets

   ```bash
   $ nix run .#sops ./myskarabox/secrets.yaml
   ```

7. Add other hosts

   ```bash
   $ nix run .#gen-new-host otherhost.
   ```

   and copy needed config in `./flake.nix`.

8. Rotate host key

   ```bash
   $ ssh-keygen -f ./myskarabox/host_key
   $ nix run .#add-sops-cfg -- -o .sops.yaml alias myskarabox $(ssh-to-age -i ./myskarabox/host_key.pub)
   $ nix run .#deploy-rs
   $ nix run .#baryum-gen-knownhosts-file
   ```

## Options
  
(WIP: generate the options here automatically see [skarabox#51](https://github.com/ibizaman/skarabox/issues/51)).

For now, rely on the `template/flake.nix` which exposes the options or look in the code
at [flakeModule.nix](https://github.com/ibizaman/skarabox/blob/main/flakeModule.nix),
[configuration.nix](https://github.com/ibizaman/skarabox/blob/main/modules/configuration.nix)
and [disks.nix](https://github.com/ibizaman/skarabox/blob/main/modules/disks.nix).

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

### Recovery

If the system becomes unbootable,
recovering it amounts to the following steps.
You might be able to skip some steps, but follow them in order.

1. Boot on beacon

    Follow steps at [A.2. Install on a Real Server](#a2-install-on-a-real-server).

2. Import ZFS pools

    Without doing this, listing the pools will return an empty list.
    Avoid yourself the same heart attack as me and run this command first.

    ```bash
    sudo zpool import root -f
    sudo zpool import zdata -f
    <... for other datasets>
    ```

    They are still locked with a passphrase, next 2 steps will take care of that.

3. Mount `root` ZFS pool

    First, unlock the ZFS pool:

    ```bash
    sudo zfs load-key root
    # Enter root passphrase
    ```

    Then mount required directories:

    ```bash
    sudo mount -t zfs root/local/root /mnt
    sudo mount -t zfs root/local/nix /mnt/nix
    sudo mount -t zfs root/safe/home /mnt/home
    sudo mount -t zfs root/safe/persist /mnt/persist
    ```

    The `/persist` filesystem holds the passphrases of the other ZFS pools, if any.

4. Enter the NixOS installation

    This will activate the system and even populate secrets in `/run/secrets`.

    ```bash
    sudo nixos-enter
    mount /boot
    ```

    **The rest of the instructions are from within this new shell.**

5. List ZFS pools and datasets

    This is mostly to make sure everything looks good before continuing.

    ```bash
    zpool list
    zfs list
    ```

6. Unlock other pools

    With `/persist` mounted and from inside the NixOS installation,
    unlocking the other pools becomes easy:

    ```bash
    zfs load-key zdata
    ```

    No prompt will be shown on `load-key`.

    Repeat for other ZFS pools.

7. Make a snapshot of all datasets

    Useful to safeguard against mistakes but also
    to be able to send the snapshot somewhere else
    like in next step.

    The following command does a recursive snapshot,
    descending in all children datasets.

    ```bash
    zfs snapshot -r root@<name of snapshot>
    ```

    Do that for each ZFS pool.

    List the snapshots with:

    ```bash
    zfs list -t snapshot
    ```

8. Send full clone elsewhere

    Assuming you made a snapshot like in the previous step,
    the following command clones the whole `root` ZFS pool
    to the `backup` ZFS pool.

    ```bash
    zfs send -v -wR root@<name of snaphost> | zfs recv -Fu backup/root
    ```

    The `-w` command sends the raw stream, which is required for encrypted ZFS pools.

    Of course, if you already regularly do this procedure as a backup job,
    you can skip this.

9. Re-install bootloader

    Following the steps from the [wiki](https://nixos.wiki/wiki/Bootloader#Re-installing_the_bootloader)
    gives:

    ```bash
    NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot
    ```

10. Install fresh system

    Of course, **this will wipe out the whole system and partition the hard drives.**

    So before anything,
    perform a ZFS snapshot of the root filesystem and send it elsewhere.

    Next, physically disconnect all hard drives except those required
    for the `root` ZFS pool. In other words, remove the hard drives
    for the `zdata` and any other ZFS pool.

    When all that is done, with the beacon booted and accessible from the network,
    follow step [B. Run the Installation](#b-run-the-installation).

    The system should have rebooted on the new installation.
    If not, hop on the [matrix channel][matrix]
    or [post an issue][issue].

    Now, the system will not be able to complete the installation since
    the hard drives for the data ZFS pool are not connected yet.
    Shutdown the system. We will fix this in the next step.

11. Restore previous system

    Connect back the hard drives for the other ZFS pools and boot on the beacon.

    Import the root ZFS pool and load its key. Do not mount any dataset.
    Also, no need to run `nixos-enter`.

    Delete the `root/safe` dataset and its children since we'll restore it.

    ```bash
    sudo zfs destroy -r root/safe
    ```

    Restore the complete `root/safe` dataset to its previous state with:

    ```bash
    sudo zfs send -v -wR backup/root/safe@<name of snaphost> | sudo zfs recv -Fu root/safe
    ```

    Use `zfs list -t snapshot -r backup/root` to list the snapshots if you don't remember its name.

    Note that we require one more step. Each dataset [inherited the key from the parent][zfs issue],
    which means each dataset will need to be unlocked individually.

    To see the problem, run:

    ```bash
    zfs list -o name,encryptionroot -r root/safe

    NAME                                      ENCROOT
    root/safe                                 root/safe
    root/safe/acme                            root/safe/acme
    root/safe/forgejo                         root/safe/forgejo
    ```

    We want the encryption root for all datasets to be `root/safe`

    To fix this, we need to first load the key for all datasets
    (yes, this step is annoying):

    ```bash
    sudo zfs load-key -r root/safe
    ```

    Then recursively call `zfs change-key -i` on all datasets:

    ```bash
    zfs list -r -o name root/safe | tail -n+2 | xargs -n1 bash -c 'echo $0; sudo zfs change-key -i $0'
    ```

    Which indeed changed the encryption root:

    ```bash
    zfs list -o name,encryptionroot -r root/safe

    NAME                                      ENCROOT
    root/safe                                 root
    root/safe/acme                            root
    root/safe/forgejo                         root
    ```

    One last safety check is unloading all keys then trying to reload them all:

    ```bash
    sudo zfs unload-key -r root/safe
    sudo zfs load-key -r root/safe
    ```

    Only one passphrase should be asked.

    [zfs issue]: https://github.com/openzfs/zfs/issues/6847

    In case impermanence was not setup correctly for some reason,
    you might want to check if any of the datasets under `backup/root/local`
    do contain some file. You can do that with:

    ```bash
    mount -t zfs backup/root/local/root /mnt
    du /mnt
    ```

    Assuming everything is restored correctly, export the ZFS pools:

    ```bash
    sudo zpool export root
    sudo zpool export zdata
    <... for other datasets>
    ```

    Now, reboot on the new system with `sudo reboot`, remove the USB key
    and all services should be up and running with the state they had before.
    If not, hop on the [matrix channel][matrix]
    or [post an issue][issue].
