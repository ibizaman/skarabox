# Skarabox

This repository originates from https://github.com/ibizaman/skarabox.

## Bootstrap

Follow the steps outlined at https://github.com/ibizaman/skarabox?tab=readme-ov-file#installation once.

## Normal Operations

1. Decrypt root pool after boot

2. Login

```bash
$ ssh -p 22 skarabox@<ip> -o IdentitiesOnly=yes -i ssh_skarabox
```

3. Reboot

```bash
$ ssh -p 22 skarabox@<ip> -o IdentitiesOnly=yes -i ssh_skarabox reboot
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
but instead of using the IP address, use the domain name:

```bash
$ ssh -p 22 skarabox@<domainname> -o IdentitiesOnly=yes -i ssh_skarabox
```

### Add Services

I do recommend using the sibling project [Self Host Blocks](https://github.com/ibizaman/selfhostblocks) to setup services like Vaultwarden, Nextcloud and others.
