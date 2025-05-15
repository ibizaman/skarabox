{
  pkgs
}:
# Generate knownhosts file.
#
# gen-knownhosts-file <pub_key> <ip> <port> [<port>...]
#
# One line will be generated per port given.
pkgs.writeShellScriptBin "gen-knownhosts-file" ''
  pub=$(cat $1 | ${pkgs.coreutils}/bin/cut -d' ' -f-2)
  shift
  ip=$1
  shift

  for port in "$@"; do
    echo "[$ip]:$port $pub"
  done
''
