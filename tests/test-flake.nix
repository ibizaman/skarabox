{
  fixture,
  hostNixpkgs,
  inputs,
  skarabox,
}:
let
  testInputs = inputs // {
    self = testFlake;
    inherit skarabox;
  };
  testFlake =
    (testInputs.flake-parts.lib.mkFlake { inputs = testInputs; } {
      systems = [ fixture.host.system ];

      imports = [
        skarabox.flakeModules.default
        skarabox.flakeModules.colmena
        skarabox.flakeModules.deploy-rs
      ];

      skarabox.hosts.${fixture.host.name} = {
        nixpkgs = hostNixpkgs;
        inherit (fixture.host)
          ip
          sshBootPort
          sshPort
          system
          ;
        hostKeyPub = fixture.files.hostPublicKey;
        modules =
          inputs.nixpkgs.lib.optionals (hostNixpkgs != null) [
            inputs.selfhostblocks.nixosModules.default
          ]
          ++ [
            inputs.sops-nix.nixosModules.default
            (
              { config, ... }:
              {
                skarabox = {
                  boot.sshPort = fixture.host.sshBootPort;
                  hostname = fixture.host.name;
                  username = fixture.host.username;
                  hashedPasswordFile = config.sops.secrets."${fixture.host.name}/user/hashedPassword".path;
                  # The real report is collected during the test. This projection
                  # prebuilds the closure selected by that QEMU hardware.
                  facter-config = builtins.path {
                    name = "facter.json";
                    path = fixture.files.facter;
                  };
                  inherit (fixture.host) hostId machineId sshPort;
                  sshAuthorizedKeys = [
                    fixture.files.clientPublicKey
                  ];
                  staticNetwork = fixture.host.staticNetwork;
                  inherit (fixture) disks;
                };

                hardware.enableAllHardware = false;
                sops = {
                  defaultSopsFile = builtins.path {
                    name = "secrets.yaml";
                    path = fixture.files.secrets;
                  };
                  age.sshKeyPaths = [ "/boot/host_key" ];
                  secrets."${fixture.host.name}/user/hashedPassword".neededForUsers = true;
                };
              }
            )
          ];
      };
    })
    // {
      inputs = testInputs;
    };
in
testFlake
