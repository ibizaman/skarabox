# Recovery {#recovery}

If the system becomes unbootable,
recovering it amounts to the following steps.
You might be able to skip some steps, but follow them in order.

1. Boot on beacon

    Follow steps at [Install on a Real Server](usage.html#on-premise).

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
    follow step [Run the installer](usage.html#run-installer).

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

    [matrix]: https://matrix.to/#/#selfhostblocks:matrix.org
    [issue]: https://github.com/ibizaman/skarabox/issues
