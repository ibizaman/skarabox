{
  dataPool ? false,
  deploymentModule ? null,
  inputs,
  legacyNixpkgs ? false,
  rootDisk2 ? false,
  skarabox,
  sshBootPort ? 2223,
  sshPort ? 2222,
  staticNetwork ? null,
  system,
}:
let
  testPasswordHash = "$6$skarabox$4ahWDg7R18sy6OpbSMoa6wUvfiFMYeiKkdDjkCbAMDZ3ZIRKF7ghQPX2oHUN.BgJPWsyFB2pQSRUqckf7a2aR1";
  testInputs = {
    self = testFlake;
    inherit skarabox;
    inherit (inputs)
      colmena
      deploy-rs
      flake-parts
      nixos-anywhere
      nixos-generators
      nixpkgs
      selfhostblocks
      ;
  };
  testFlake =
    (testInputs.flake-parts.lib.mkFlake { inputs = testInputs; } {
      systems = [ system ];

      imports = [
        skarabox.flakeModules.default
      ]
      ++ inputs.nixpkgs.lib.optional (deploymentModule == "colmena") skarabox.flakeModules.colmena
      ++ inputs.nixpkgs.lib.optionals (deploymentModule == "deploy-rs") [
        skarabox.flakeModules.deploy-rs
        {
          # Updating GRUB in the QEMU target takes longer than deploy-rs's
          # 30-second default confirmation timeout.
          flake.deploy.nodes.test.confirmTimeout = 600;
        }
      ];

      skarabox.sopsKeyPath = "/etc/scenario/sops-key";
      skarabox.hosts.test = {
        nixpkgs = if legacyNixpkgs then null else inputs.selfhostblocks.lib.${system}.patchedNixpkgs;
        inherit sshBootPort sshPort system;
        hostKeyPath = "/etc/scenario/ssh";
        hostKeyPub = ./fixtures/insecure-test-ssh-key.pub;
        ip = "10.0.2.2";
        knownHostsPath = "/tmp/codex/scenario/known-hosts";
        secretsFilePath = "/etc/scenario/secrets.yaml";
        sshPrivateKeyPath = "/etc/scenario/ssh";
        sshPublicKeyPath = null;
        modules =
          inputs.nixpkgs.lib.optionals (!legacyNixpkgs) [
            inputs.selfhostblocks.nixosModules.default
          ]
          ++ [
            (
              { lib, modulesPath, ... }:
              {
                imports = [
                  (modulesPath + "/profiles/qemu-guest.nix")
                ];

                # Preserve the DHCP lease while QEMU resets its virtual link during
                # the transition from initrd networkd to stage-2 networkd.
                systemd.network.networks."10-lan".networkConfig = lib.optionalAttrs (staticNetwork == null) {
                  KeepConfiguration = "dynamic";
                };
                boot.initrd.systemd.network.networks."10-lan".networkConfig =
                  lib.optionalAttrs (staticNetwork == null)
                    {
                      KeepConfiguration = "dynamic";
                    };
                boot.initrd.availableKernelModules = [
                  "ata_piix"
                  "e1000"
                  "nvme"
                  "sd_mod"
                ];
                skarabox = {
                  hostname = "test";
                  username = "skarabox";
                  sshPort = sshPort;
                  boot.sshPort = sshBootPort;
                  hashedPasswordFile = builtins.toFile "hashed-password" testPasswordHash;
                  facter-config = builtins.toFile "empty-facter.json" "";
                  hostId = "00000000";
                  machineId = "0123456789abcdef0123456789abcdef";
                  sshAuthorizedKeys = [ ./fixtures/insecure-test-ssh-key.pub ];
                  inherit staticNetwork;
                  disks = {
                    rootPool = {
                      disk1 = "/dev/nvme0n1";
                      disk2 = if rootDisk2 then "/dev/nvme1n1" else null;
                      reservation = "500M";
                      bootloader = "uefi";
                    };
                    dataPool = {
                      enable = dataPool;
                      disk1 = "/dev/sda";
                      disk2 = "/dev/sdb";
                      reservation = "1G";
                    };
                  };
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
{
  deploymentFlake =
    if deploymentModule == "colmena" then
      {
        apps.${system}.colmena = testFlake.apps.${system}.colmena;
        inherit (testFlake) colmenaHive;
      }
    else if deploymentModule == "deploy-rs" then
      {
        apps.${system}.deploy-rs = testFlake.apps.${system}.deploy-rs;
        checks.${system} = testFlake.checks.${system};
        inherit (testFlake) deploy;
      }
    else
      null;
  flake = testFlake;
  inherit testPasswordHash;
}
