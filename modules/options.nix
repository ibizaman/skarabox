{ lib, ... }:
let
  inherit (lib) mkOption types;

  readAndTrim = f: lib.strings.trim (builtins.readFile f);
  readAsStr = v: if lib.isPath v then readAndTrim v else v;
  readAsListOfStr = v: if lib.isList v then map readAsStr v else [ (readAsStr v) ];
in
{
  options.skarabox = {
    hostname = mkOption {
      description = "Hostname to give to the server.";
      type = types.str;
      default = "skarabox";
    };

    username = mkOption {
      description = "Name given to the admin user on the server.";
      type = types.str;
      default = "skarabox";
    };

    hashedPasswordFile = mkOption {
      description = "Contains hashed password for the admin user.";
      type = types.str;
    };

    facter-config = lib.mkOption {
      description = ''
        nixos-facter config file.
      '';
      type = lib.types.path;
    };

    hostId = mkOption {
      type = types.str;
      description = ''
        8 characters unique identifier for this server. Generate with `uuidgen | head -c 8`.
      '';
    };

    sshPort = mkOption {
      type = types.int;
      default = 2222;
      description = ''
        Port the SSH daemon listens to.
      '';
    };

    sshAuthorizedKey = mkOption {
      type =
        with types;
        let
          t = oneOf [
            str
            path
          ];
        in
        oneOf [
          t
          (listOf t)
        ];
      description = ''
        Public SSH key(s) used to connect on boot to decrypt the root pool.
      '';
      apply = readAsListOfStr;
    };
  };
}
