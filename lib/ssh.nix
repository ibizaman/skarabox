{
  pkgs
}:
# SSH into a host
#
#   <ip> [<port> [<user> [<command> ...]]]
#   192.168.1.10
#   192.168.1.10 22
#   192.168.1.10 22 nixos
#   192.168.1.10 22 nixos echo hello
pkgs.writeShellScriptBin "ssh" ''
  ip=$1
  shift
  port=$1
  shift
  user=$1
  shift

  ${pkgs.openssh}/bin/ssh \
    -p ''${port:-22} \
    ''${user:-skarabox}@''$ip \
    -o IdentitiesOnly=yes \
    $@
''
