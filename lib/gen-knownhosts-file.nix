{
  pkgs
}:
# Generate knownhosts file.
#
# gen-knownhosts-file <pub_key> <ip> <port> [<port>...]
#
# One line will be generated per port given.
pkgs.writeShellScriptBin "gen-knownhosts-file" ''
  if [ -f "$1" ]; then
    pub=$(cat "$1" | ${pkgs.coreutils}/bin/cut -d' ' -f-2)
  else
    pub=$(echo "$1" | ${pkgs.coreutils}/bin/cut -d' ' -f-2)
  fi
  shift
  ip=$1
  shift

  for port in "$@"; do
    if [ "$port" = "22" ]; then
      # Port 22 is the default, so omit the port specification
      echo "$ip $pub"
    else
      echo "[$ip]:$port $pub"
    fi
  done
''
