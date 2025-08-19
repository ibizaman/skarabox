{
  config,
  lib,
  inputs,
  ...
}:
let
  topLevelConfig = config;
  cfg = config.skarabox;

  inherit (lib) concatMapAttrs;
in
{
  config = {
    perSystem = { self', inputs', config, pkgs, system, ... }: {
      apps = {
        inherit (inputs'.deploy-rs.apps) deploy-rs;
      };
    };

    flake = flakeInputs: let
      mkFlake = name: cfg': {
        # Debug eval errors with `nix eval --json .#deploy --show-trace`
        deploy.nodes = let
          pkgs' = import inputs.nixpkgs {
            inherit (cfg') system;
          };
          # Use deploy-rs from nixpkgs to take advantage of the binary cache.
          # https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
          deployPkgs = import inputs.nixpkgs {
            inherit (cfg') system;
            overlays = [
              inputs.deploy-rs.overlays.default
              (self: super: {
                deploy-rs = {
                  inherit (pkgs') deploy-rs;
                  lib = super.deploy-rs.lib;
                };
              })
            ];
          };

          mkNode = name: cfg': let
            hostCfg = topLevelConfig.flake.nixosConfigurations.${name}.config;
          in {
            ${name} = {
              hostname = cfg'.ip;
              sshUser = topLevelConfig.flake.nixosConfigurations.${name}.config.skarabox.username;
              # What out, adding --ssh-opts on the command line will override these args.
              # For example, running `nix run .#deploy-rs -- -s --ssh-opts -v` will result in only the -v flag.
              sshOpts = [
                "-o" "IdentitiesOnly=yes"
                "-o" "UserKnownHostsFile=${cfg'.knownHosts}"
                "-o" "ConnectTimeout=10"
                "-p" (toString hostCfg.skarabox.sshPort)
              ] ++ lib.optionals (cfg'.sshPrivateKeyPath != null) [ "-i" cfg'.sshPrivateKeyPath ];
              profiles = {
                system = {
                  user = "root";
                  path = deployPkgs.deploy-rs.lib.activate.nixos topLevelConfig.flake.nixosConfigurations.${name};
                };
              };
            };
          };
          in
            concatMapAttrs mkNode cfg.hosts;
      };

      common = {
        # From https://github.com/serokell/deploy-rs?tab=readme-ov-file#overall-usage
        checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks topLevelConfig.flake.deploy) inputs.deploy-rs.lib;
      };
    in
      common // (concatMapAttrs mkFlake cfg.hosts);
  };
}