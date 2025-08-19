{
  config,
  lib,
  inputs,
  ...
}:
let
  topLevelConfig = config;
  cfg = config.skarabox;

  inherit (lib) concatMapAttrs mapAttrs;
in
{
  config = {
    perSystem = { inputs', ... }: {
      apps = {
        inherit (inputs'.colmena.apps) colmena;
      };
    };

    flake = flakeInputs: let
      mkFlake = name: cfg': {
        colmenaHive = inputs.colmena.lib.makeHive ({
          meta.nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
          meta.nodeNixpkgs = mapAttrs (_: cfg': import cfg'.nixpkgs { inherit (cfg') system; }) cfg.hosts;
        } // (let
          mkNode = name: cfg': let
            hostCfg = topLevelConfig.flake.nixosConfigurations.${name}.config;
          in
            {
              deployment = {
                targetHost = cfg'.ip;
                targetPort = hostCfg.skarabox.sshPort;
                targetUser = topLevelConfig.flake.nixosConfigurations.${name}.config.skarabox.username;
                sshOptions = [
                  "-o" "IdentitiesOnly=yes"
                  "-o" "UserKnownHostsFile=${cfg'.knownHosts}"
                  "-o" "ConnectTimeout=10"
                ] ++ lib.optionals (cfg'.sshPrivateKeyPath != null) [ "-i" cfg'.sshPrivateKeyPath ];
              };

              imports = cfg'.modules ++ [
                inputs.skarabox.nixosModules.skarabox
              ];
            };
        in
          mapAttrs mkNode cfg.hosts
        ));
      };
    in
      (concatMapAttrs mkFlake cfg.hosts);
  };
}