# Architecture

So you want to know more about how all pieces fit together in Skarabox?
That's great. You're at the right place.

<!--toc:start-->
- [Hardware](#hardware)
- [ZFS root pool encryption](#zfs-root-pool-encryption)
- [ZFS data pool encryption](#zfs-data-pool-encryption)
- [Remote decryption of root pool on boot](#remote-decryption-of-root-pool-on-boot)
- [SSH Access](#ssh-access)
- [Erase your darlings](#erase-your-darlings)
- [Host Key](#host-key)
- [SOPS](#sops)
- [hostid](#hostid)
- [ZFS settings](#zfs-settings)
- [Principles](#principles)
<!--toc:end-->

## Hardware

In essence, we let [nixos-facter][] figure out what's needed.

Would it fail to detect the hardware,
we include an escape hatch by adding the two following options
to the template's `configuration.nix` file,
although we give them their default values:

```nix
boot.initrd.availableKernelModules = [];
hardware.enableAllHardware = false;
```

For ZFS, we set the following option which sets up
all the machinery for ZFS to work in initrd and afterwards.
This all happens in [tasks/filesystems/zfs.nix][zfs.nix].

```nix
boot.supportedFilesystems = [ "zfs" ];
```

[nixos-facter]: https://github.com/nix-community/nixos-facter
[zfs.nix]: https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/tasks/filesystems/zfs.nix

## ZFS root pool encryption

We want to encrypt the root pool with a passphrase
that is _not_ stored on the host.
We will need to enter it on every boot.

The configuration lives in [./modules/disks.nix](../modules/disks.nix),
under `disko.devices.zpool` and uses [disko][].

[disko]: https://github.com/nix-community/disko

For the root pool, the relevant encryption settings are:

```nix
boot.supportedFilesystems = [ "zfs" ];
boot.zfs.forceImportRoot = false;

disko.devices.zpool.${cfg.rootPool} = {
  rootFsOptions = {
    encryption = "on";
    keyformat = "passphrase";
    keylocation = "file:///tmp/root_passphrase";
  };
  postCreateHook = ''
    zfs set keylocation="prompt" $pname
  '';
};
```

This means we will encrypt the zpool
with the key located at `/tmp/root_passphrase`.
After the encryption is done,
we will switch the location of the key
to `prompt` which means ZFS will prompt us
to enter the key. That's indeed what we want:
the key should not live on the server,
otherwise what's the point?

We also set `boot.forceImportRoot` to false
because that's what's [recommended][forceImportRoot]
but also because it won't work since we
need to give the passphrase to decrypt it
in the first place.

We add zfs to the `boot.supportedFilesystems`
option otherwise the kernel will not have the
appropriate modules.

[forceImportRoot]: https://search.nixos.org/options?channel=24.11&show=boot.zfs.forceImportRoot&from=0&size=50&sort=relevance&type=packages&query=forceimportroot

Then, we actually need to copy over the passphrase
during the installation process by adding the following
argument to the `nixos-anywhere` command :

```bash
--disk-encryption-keys /tmp/root_passphrase <location of passphrase file>
```

Now, on every boot, a prompt will appear asking us for the passphrase.
We will see in a [later section](#remote-decryption-of-root-pool-on-boot)
how to decrypt the root pool remotely.

## ZFS data pool encryption

For the data pool, the idea is the same as for the [root pool](#zfs-root-pool-encryption).
The difference is that we will store the passphrase
inside the root pool partition, allowing us to unlock
the data pool automatically after decrypting the root pool.

The relevant encryption settings are:

```nix
disko.devices.zpool.${cfg.dataPool} = {
  rootFsOptions = {
    encryption = "on";
    keyformat = "passphrase";
    keylocation = "file:///tmp/data_passphrase";
  };
  postCreateHook = ''
    zfs set keylocation="file:///persist/data_passphrase" $pname;
  '';
}

disko.devices.zpool.${cfg.rootPool}.datasets = {
  "safe/persist" = {
    type = "zfs_fs";
    mountpoint = "/persist";
    options.mountpoint = "legacy";
    postMountHook = ''
      cp /tmp/data_passphrase /mnt/persist/data_passphrase
    '';
  };
};

boot.zfs.extraPools = [ cfg.dataPool ];
```

Similarly to the root pool, we will encrypt
the zpool using the key located at `/tmp/data_passphrase`.
We then switch the location of the key
to `/persist/data_passphrase` which is a dataset
on the root zpool which does not get rolled back
upon reboot (see [Erase your darlings](#erase-your-darlings)).
We copy the key as part of the `postMountHook` commands.

This all means the data zpool gets decrypted automatically
when the root zpool is,
even though it uses a different key.

The `extraPools` option is needed to automatically
import the data pool.

We then copy over the passphrase during the installation
process by adding the following argument to the
`nixos-anywhere` command:

```bash
--disk-encryption-keys /tmp/data_passphrase <location of passphrase file>
```

## Remote decryption of root pool on boot

With the [config above](#zfs-root-pool-encryption),
a prompt will appear during initrd
which will prompt us to enter the root passphrase.
This is all good if you have a keyboard and screen
attached to the host but won't work if not.

So here, we want to run an ssh server in initrd
which allows us to unlock the root pool
and continue the boot process.

The relevant config is in [./modules/disks.nix](../modules/disks.nix):

```nix
boot.initrd.network = {
  enable = true;

  udhcpc.enable = lib.mkDefault true;

  ssh = {
    enable = true;
    port = lib.mkDefault cfg.bootSSHPort;
    authorizedKeyFiles = [
      ./ssh_skarabox.pub
    ];
  };

  postCommands = ''
    zpool import -a
    echo "zfs load-key ${cfg.rootPool}; killall zfs; exit" >> /root/.profile
  '';
```

We enable `boot.initrd.network` and the `.ssh` options.
We set the port to 2222 by default.
We add an ssh public key so we can connect as the root user.

This ssh public key is generated as part of the [initialization](../lib/gen-initial.nix)
process in `./ssh_skarabox.pub` and the private key in `./skarabox`.
We also add that file to `.gitignore` to ensure
we don't store the private file in the repo.

The commands in `postCommands` are executed when the sshd
daemon has started. The command added in `/root/.profile` will
be executed when we log in through SSH.
This results in ZFS prompting us to enter the
root zpool's passphrase as soon as we're logged in.

The `udhcpc.enable` option enables DHCP.
Allowing a static IP here is planned.

If by any change the kernel does not try to connect to the network
and fails to ask for an IP and no error message is shown,
this probably means that the driver for the hardware has failed
loading or that nixos-facter has failed to detect the hardware.
See [Hardware](#hardware) for how to fix this.

## SSH Access

Here, we enable SSH access to the host after it has booted.
We want a password-less connection
and also to pre-validate the host key of the host.
This means we won't let the host generate its own host key,
we will generate it ourselves and add it to a known hosts
file upon installation.

This last step is often neglected for convenience reasons
but it is important to make sure we connect to the correct
host from the start. [This section](#host-key) goes into
details on how it's done.

For non-initrd ssh access, we add the ssh public key
to the `authorizedKeys` file of the user:

```nix
users.users.${config.skarabox.username} = {
  openssh.authorizedKeys.keyFiles = [
    config.skarabox.sshAuthorizedKeyFile
  ];
};
```

For the initrd ssh access, to decrypt the root partition,
the configuration is similar although here the user is `root`:

```nix
boot.initrd.network = {
  ssh.authorizedKeyFiles = [
    config.skarabox.sshAuthorizedKeyFile
  ];
};
```

For the firmware, we use nixos-facter to figure it out.

## Erase your darlings

The idea here is to explicitly list which directories one wants
to save. The rest will be lost on reboots.
I learned about it from Graham Christensen
and recommend [their blog post][eyd] to understand the motivation.

[eyd]: https://grahamc.com/blog/erase-your-darlings/

We implement this by creating a root dataset mounted at `/`
which will get rolled back on every boot:

```nix
disko.devices.zpool.${cfg.rootPool}.datasets."local/root" = {
  type = "zfs_fs";
  mountpoint = "/";
  options.mountpoint = "legacy";
  postCreateHook = ''
    zfs list -t snapshot -H -o name \
      | grep -E '^${cfg.rootPool}/local/root@blank$' \
      || zfs snapshot ${cfg.rootPool}/local/root@blank
  '';
};
```

The `postCreateHook` creates a new zfs snapshot during the installation
process. The `grep` part is to make sure we only create one such
snapshot, in case we run the installation process multiple times.
This snapshot is thus empty.

Now, we revert back to the snapshot upon every boot with:

```nix
boot.initrd.postResumeCommands = lib.mkAfter ''
  zfs rollback -r ${cfg.rootPool}/local/root@blank
'';
```

To save a directory, we must create a dataset and mount it:

```nix
disko.devices.zpool.${cfg.rootPool}.datasets."local/nix" = {
  type = "zfs_fs";
  mountpoint = "/nix";
  options.mountpoint = "legacy";
};
```

## Host Key

By default, upon starting, the sshd systemd service
will generate some host keys under `/etc/ssh` if that
folder is empty.

When connecting through ssh for the first time,
the ssh client will prompt about verifying the host
key of the server.

Providing the host key ourselves allows us to skip
this test since we know the host key in advance
and can generate the relevant `known_hosts` file.

The config for this is simply to copy the `host_key`
in some temporary location by (ab)using the 
`disk-encryption-keys` flag for `nixos-anywhere`:

```bash
--disk-encryption-keys /tmp/host_key <location of host_key file>
```

Then, we copy the host_key in a _not encrypted_ location.
This is necessary otherwise we can't use it in the initrd phase. 

```nix
disko.devices.disk."root" = {
  type = "disk";
  content = {
    type = "gpt";
    partitions = {
      ESP = {
        type = "EF00";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
          postMountHook = ''
            cp /tmp/host_key /mnt/boot/host_key
          '';
        };
      };
    };
  };
};
```

The only relevant configuration is the `postMountHook` but
I included the rest here to give some context.

Then, we use that key from this new location in the initrd ssh daemon:

```nix
boot.initrd.network.ssh.hostKeys = lib.mkForce [ "/boot/host_key" ];
```

We override the whole list with `mkForce` to avoid the default
behavior of a list option which is to merge.
Here, we don't want any of the default automatic generation.

For the non-initrd ssh daemon,
we force an empty list so the nix module does not generate any ssh key
and we instead tell the location of our host key:


```nix
services.openssh = {
  hostKeys = lib.mkForce [];
  extraConfig = ''
    HostKey /boot/host_key
  '';
};
```

## SOPS

To store the secrets, we use [sops-nix][] which stores the secrets
encrypted in the repository, here in a `./secrets.yaml` file.
It's creation and update is governed by the `./.sops.yaml` file.

The process to create this SOPS file is quite involved
but is fully automatic, so that's nice.

[sops-nix]: https://github.com/Mic92/sops-nix

We must allow us, the user, to decrypt this `./secrets.yaml` file
as well as allow the target host to decrypt it.
This means we need to encrypt the file with two keys.

The user's SOPS private key is generated in [gen-initial.nix][] with:
```bash
age-keygen -o sops.key
```

[gen-initial.nix]: ../lib/gen-initial.nix

and get the associated SOPS public key with:

```bash
age-keygen -y sops.key
```

By the way, we add that file to `.gitignore` to ensure
we don't store the private file in the repo.

The hosts' SOPS public key is derived from the host' public ssh key
we generated [earlier](#host-key) in `./host_key.pub` with:

```bash
cat host_key.pub | ssh-to-age
```

We then use those two SOPS public keys to create the configuration
file `.sops.yaml`:

```yaml

keys:
  - &me age1sz...
  - &server age1ys...
creation_rules:
  - path_regex: secrets\.yaml$
    key_groups:
    - age:
      - *me
      - *server
```

And finally we encrypt the `secrets.yaml` file with:

```bash
SOPS_AGE_KEY_FILE=sops.key sops encrypt -i secrets.yaml
```

Note the `./secrets.yaml` cannot be empty to be encrypted,
that's a limitation of SOPS itself.

We only add secrets to the `./secrets.yaml` file
after it has been encrypted, as an added precaution.
This is done by using the `set` [subcommand][set] of the `sops` command.

Similarly, we can decrypt one value with the `decrypt --extract` [option][extract].

[set]: https://github.com/getsops/sops?tab=readme-ov-file#set-a-sub-part-in-a-document-tree
[extract]: https://github.com/getsops/sops?tab=readme-ov-file#45extract-a-sub-part-of-a-document-tree

## hostid

The `hostid` must be unique and not change during the lifetime of the server.
It is only used by ZFS which refuses to import the pools if the `hostid` changes.

The configuration for it is pretty simple:

```nix
networking.hostId = lib.trim (builtins.readFile ./hostid);
```

## ZFS settings

I wrote a [blog post][] about these.
I'm not an expert on ZFS,
I mostly did some extensive research.

[blog post]: https://blog.tiserbox.com/posts/2024-02-09-zfs-on-nix-os.html

## Principles

I'm trying to follow these principles as I implement features.
I find they tend to lead to a polished experience
and a maintainable code base.

- Less manual steps possible.

  Generate secrets automatically, create values with good defaults.

- All commands should be locked in the template's flake.

  For example, instead of instructing the user to run a command with:
  
  ```bash
  nix run nixpkgs#openssh
  ```
  
  we add the package to the flake:
  
  ```nix
  {
    inputs.nixpkgs = ...;

    outputs = { nixpkgs, ... }: {
      packages.x86_64-linux = {
        inherit (nixpkgs) openssh;
      };
    };
  }
  ```
  
  then instruct the user to use that version of openssh:
  
  ```bash
  nix run .#openssh
  ```

  This makes sure that the versions of all commands
  match what we expect and avoids one class of problem.

- The template's flake.nix file should be as empty as possible
  and instead provide a small layer on top of Skarabox' flake.
  This way, updates are easier to handle by the user since
  they don't need to update their flake.nix file.

  Similarly, the template's flake.nix should provide
  sensible defaults on top of Skarabox' flake.
  For example, if Skarabox' flake provides a function
  to generate a file:
  
  ```nix
  mkFile = pkgs.writeShellScriptBin "mkFile" ''
    mkdir -p $1
    touch $1/$2
  '';
  ```
  
  The template's flake fills out the required arguments
  using the secrets in the template:

  
  ```nix
  mkFile = pkgs.writeShellScriptBin "mkFile" ''
    ${inputs'.skarabox.packages.mkFile}/bin/mkFile \
      ${builtins.readFile ./dir} \
      ${builtins.readFile ./file} \
  '';
  ```
