{ lib, ... }:
let
  inherit (lib) mkOption types;

  isNonEmptySingleLine = v: v != "" && !(lib.hasInfix "\n" v);
  isNonEmptySingleLineFile = v:
    let
      lines = lib.splitString "\n" (builtins.readFile v);
    in
    (builtins.length lines == 1 && builtins.elemAt lines 0 != "")
    || (builtins.length lines == 2 && builtins.elemAt lines 0 != "" && builtins.elemAt lines 1 == "");
  readAsStr = v: if lib.isPath v then lib.removeSuffix "\n" (builtins.readFile v) else v;
  readAsListOfStr = v: if lib.isList v then map readAsStr v else [ (readAsStr v) ];
in
{
  imports = [
    (lib.mkChangedOptionModule
      [ "skarabox" "sshAuthorizedKey" ]
      [ "skarabox" "sshAuthorizedKeys" ]
      (config: readAsListOfStr config.skarabox.sshAuthorizedKey))
  ];

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

    machineId = mkOption {
      type = types.str;
      description = ''
        Unique identifier. Generate with `uuidgen -r | tr -d -`.

        This must be persisted https://nixos.org/manual/nixos/stable/#sec-machine-id
      '';
    };

    sshPort = mkOption {
      type = types.port;
      default = 2222;
      description = ''
        Port the SSH daemon listens to.
      '';
    };

    sshAuthorizedKeys = mkOption {
      type =
        with types;
        let
          keyString = addCheck str isNonEmptySingleLine // {
            description = "non-empty single-line SSH public key string";
          };
          keyPath = addCheck path isNonEmptySingleLineFile // {
            description = "path to a non-empty single-line SSH public key file";
          };
          t = oneOf [
            keyString
            keyPath
          ];
        in
        listOf t;
      description = ''
        Public SSH key(s) used to connect on boot to decrypt the root pool.
      '';
      apply = readAsListOfStr;
    };
  };
}
