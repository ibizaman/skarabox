{
  dataPool,
  fullScenario ? true,
  inputs,
  knownHostsShowTrace ? true,
  legacyNixpkgs ? false,
  name,
  pkgs,
  rootDisk2,
  skarabox,
  sshBootPort ? 2223,
  sshPort ? 2222,
  staticNetwork ? null,
  system,
  templateSources,
}:
let
  fixture = import ./fixture.nix {
    inherit
      dataPool
      rootDisk2
      sshBootPort
      sshPort
      staticNetwork
      system
      ;
  };
  hostNixpkgs =
    if legacyNixpkgs then null else inputs.selfhostblocks.lib.${fixture.host.system}.patchedNixpkgs;
  testFlake = import ./test-flake.nix {
    inherit
      fixture
      hostNixpkgs
      inputs
      skarabox
      ;
  };
  targetConfig = testFlake.nixosConfigurations.${fixture.host.name}.config;
  targetSystem = targetConfig.system.build.toplevel;
  colmenaTargetSystem = testFlake.colmenaHive.nodes.${fixture.host.name}.config.system.build.toplevel;
  diskoScript = targetConfig.system.build.diskoScript;
  hostPackages = testFlake.packages.${fixture.host.system};
  beaconVM = hostPackages."${fixture.host.name}-beacon-vm";

  repository = "/tmp/codex/repository";
  hostDirectory = "${repository}/${fixture.host.name}";
  nix = "${pkgs.lib.getExe pkgs.nix} --allow-import-from-derivation --print-build-logs";
  # The test driver's shell has a TTY, unlike the previous CI invocation.
  # Keep nested tools noninteractive by giving each generated command non-TTY stdin.
  nixRun = package: "cd ${repository} && ${nix} run --offline .#${package} -- </dev/null";
  ssh = nixRun "${fixture.host.name}-ssh";
  unlock = nixRun "${fixture.host.name}-unlock";

  deploymentDependencies = [
    inputs.colmena.packages.${fixture.host.system}.colmena
    inputs.deploy-rs.packages.${fixture.host.system}.deploy-rs
    colmenaTargetSystem
  ]
  ++ map (check: check.inputDerivation) (builtins.attrValues testFlake.checks.${fixture.host.system});
in
pkgs.testers.runNixOSTest {
  inherit name;

  nodes.installer = {
    nix.settings.experimental-features = [
      "flakes"
      "nix-command"
    ];
    environment.systemPackages = [
      pkgs.git
      pkgs.jq
    ];
    virtualisation = {
      additionalPaths = [
        diskoScript
        hostPackages."${fixture.host.name}-install-on-beacon".inputDerivation
        skarabox.packages.${fixture.host.system}.init
        targetSystem
      ]
      ++ templateSources
      ++ pkgs.lib.optional (hostNixpkgs != null) hostNixpkgs
      ++ pkgs.lib.optionals fullScenario deploymentDependencies;
      # Nested Nix needs 2 GiB RAM; deploy-rs also needs 2 GiB disk and 4 GiB RAM.
      diskSize = if fullScenario then 2 * 1024 else 1024;
      memorySize = if fullScenario then 4096 else 2048;
      # Installation reads a large closure from the host store over 9p.
      msize = 32 * 1024;
      writableStoreUseTmpfs = false;
    };
  };

  testScript = ''
    ${pkgs.lib.optionalString fullScenario "import shlex"}
    import time

    def retry_shell(command: str) -> str:
        return f"until {command}; do sleep 5; done"

    # qemuBinary uses a host-dependent -cpu max. QEMU honors the final -cpu
    # option, so use a stable model that matches the prebuilt facter fixture.
    beacon = create_machine(
        start_command="exec ${pkgs.lib.getExe beaconVM} -cpu qemu64,-svm",
        name="beacon",
    )
    driver.machines_qemu.append(beacon)
    installer.start()

    with subtest("initialize template"):
        installer.succeed("mkdir -p ${repository}")
        installer.succeed(
            "cd ${repository} && printf 'skarabox1234\\n' | "
            "${nix} run --offline path:${skarabox.outPath}#init -- -v -y -s"
        )
        installer.fail(
            "grep -R \"I'm empty and in plain text right now\" ${repository}"
        )

        # The beacon and target are built before this test runs, so replace the
        # generated identities and secrets with their public test fixtures.
        installer.succeed(
            "install -m 0600 ${fixture.files.clientPrivateKey} ${hostDirectory}/ssh && "
            "install -m 0644 ${fixture.files.clientPublicKey} ${hostDirectory}/ssh.pub && "
            "install -m 0600 ${fixture.files.hostPrivateKey} ${hostDirectory}/host_key && "
            "install -m 0644 ${fixture.files.hostPublicKey} ${hostDirectory}/host_key.pub && "
            "install -m 0600 ${fixture.files.sopsPrivateKey} ${repository}/sops.key && "
            "install -m 0644 ${fixture.files.secrets} ${hostDirectory}/secrets.yaml"
        )
        installer.succeed(
            "sed -i 's/ip = \"192.168.1.30\"/ip = \"${fixture.host.ip}\"/' "
            "${repository}/flake.nix && "
            "sed -i 's/system = \"x86_64-linux\"/system = \"${fixture.host.system}\"/' "
            "${repository}/flake.nix && "
            "sed -i 's/skarabox.sshPort = 2222/skarabox.sshPort = ${toString fixture.host.sshPort}/' "
            "${hostDirectory}/configuration.nix && "
            "sed -i 's/skarabox.boot.sshPort = 2223/"
            "skarabox.boot.sshPort = ${toString fixture.host.sshBootPort}/' "
            "${hostDirectory}/configuration.nix && "
            "sed -i 's/skarabox.hostId = \"[^\"]*\"/"
            "skarabox.hostId = \"${fixture.host.hostId}\"/' "
            "${hostDirectory}/configuration.nix && "
            "sed -i 's/skarabox.machineId = \"[^\"]*\"/"
            "skarabox.machineId = \"${fixture.host.machineId}\"/' "
            "${hostDirectory}/configuration.nix"
        )
        ${pkgs.lib.optionalString legacyNixpkgs ''
          installer.succeed(
              "sed -i 's/nixpkgs = inputs.selfhostblocks.lib.''${system}.patchedNixpkgs;/"
              "nixpkgs = null;/' ${repository}/flake.nix && "
              "sed -i '/inputs.selfhostblocks.nixosModules.default$/d' "
              "${repository}/flake.nix"
          )
        ''}
        installer.succeed(
            "cd ${repository} && "
            "git init && "
            "printf '.skarabox-tmp\\n' > .gitignore && "
            "git config user.name skarabox && "
            "git config user.email skarabox@skarabox.com && "
            "git add . && "
            "git commit -m 'init repository'"
        )
        installer.succeed(
            "cd ${repository} && "
            "${nix} flake update --offline --override-input "
            "skarabox path:${skarabox.outPath} skarabox && "
            "git add flake.lock && "
            "git commit -m 'use local skarabox input'"
        )
        installer.succeed(
            "${nixRun "${fixture.host.name}-gen-knownhosts-file"}"
            "${pkgs.lib.optionalString knownHostsShowTrace " --show-trace"} && "
            "cd ${repository} && "
            "git add ${fixture.host.name}/known_hosts && "
            "git commit -m 'generate known hosts'"
        )

    ${pkgs.lib.optionalString (!fixture.disks.dataPool.enable) ''
      installer.succeed(
          "sed -i 's/enable = true/enable = false/' "
          "${hostDirectory}/configuration.nix"
      )
    ''}
    ${pkgs.lib.optionalString (fixture.disks.rootPool.disk2 != null) ''
      installer.succeed(
          "sed -i 's-disk2 = null-disk2 = \"${fixture.disks.rootPool.disk2}\"-' "
          "${hostDirectory}/configuration.nix"
      )
    ''}
    ${pkgs.lib.optionalString (fixture.host.staticNetwork != null) ''
      installer.succeed(
          "sed -i 's-staticNetwork = null-staticNetwork = "
          "{ ip=\"${fixture.host.staticNetwork.ip}\"; "
          "gateway=\"${fixture.host.staticNetwork.gateway}\"; }-' "
          "${hostDirectory}/configuration.nix"
      )
    ''}

    with subtest("show generated flake"):
        installer.succeed(
            "cd ${repository} && ${nix} flake show --offline"
        )

    beacon.start(allow_reboot=True)
    time.sleep(10)

    with subtest("connect to beacon"):
        installer.succeed(retry_shell(
            "${ssh} -F none -o CheckHostIP=no "
            "-o StrictHostKeyChecking=no echo connected"
        ))

    with subtest("generate hardware configuration"):
        installer.succeed(
            "${nixRun "${fixture.host.name}-get-facter"} > "
            "${hostDirectory}/facter.json"
        )
        installer.succeed("jq < ${hostDirectory}/facter.json")
        installer.succeed(
            "cd ${repository} && "
            "git add ${fixture.host.name}/facter.json && "
            "git commit -m 'generate hardware config'"
        )
        actual_target = installer.succeed(
            "cd ${repository} && ${nix} eval --raw "
            ".#nixosConfigurations.${fixture.host.name}.config.system.build.toplevel.outPath"
        ).strip()
        assert actual_target == "${targetSystem}", (
            "generated target does not match the prebuilt QEMU fixture: "
            + actual_target
        )

    with subtest("install system"):
        installer.succeed(
            "${nixRun "${fixture.host.name}-install-on-beacon"} "
            "--no-substitute-on-destination"
        )

    with subtest("unlock and connect to installed system"):
        installer.succeed("${unlock} -F none")
        installer.succeed(retry_shell("${ssh} -F none echo connected"))

    ${pkgs.lib.optionalString fullScenario ''
      with subtest("check password and persistent user maps"):
          hashed_password = installer.succeed(
              "${nixRun "sops"} decrypt --extract "
              "'[\"${fixture.host.name}\"][\"user\"][\"hashedPassword\"]' "
              "${hostDirectory}/secrets.yaml"
          ).strip()
          installer.succeed(
              "${ssh} -F none sudo cat /etc/shadow | "
              "grep " + shlex.quote(hashed_password)
          )
          uid_map = installer.succeed(
              "${ssh} -F none sudo cat /var/lib/nixos/uid-map"
          )
          gid_map = installer.succeed(
              "${ssh} -F none sudo cat /var/lib/nixos/gid-map"
          )
          assert uid_map, "No uid map found"
          assert gid_map, "No gid map found"

      with subtest("reboot and recheck persistent state"):
          installer.succeed(
              "${ssh} -F none \"(sleep 2 && sudo reboot)&\""
          )
          installer.succeed("${unlock} -F none")
          installer.succeed(retry_shell("${ssh} -F none echo connected"))
          installer.succeed(
              "${ssh} -F none sudo cat /etc/shadow | "
              "grep " + shlex.quote(hashed_password)
          )
          assert installer.succeed(
              "${ssh} -F none sudo cat /var/lib/nixos/uid-map"
          ) == uid_map
          assert installer.succeed(
              "${ssh} -F none sudo cat /var/lib/nixos/gid-map"
          ) == gid_map

      with subtest("deploy with deploy-rs"):
          installer.succeed(
              "sed -i 's/inputs.skarabox.flakeModules.colmena/"
              "# inputs.skarabox.flakeModules.colmena/' ${repository}/flake.nix"
          )
          installer.succeed(
              "${nixRun "deploy-rs"} --debug-logs --temp-path .tmp"
          )
          installer.succeed(
              "sed -i 's/# inputs.skarabox.flakeModules.colmena/"
              "inputs.skarabox.flakeModules.colmena/' ${repository}/flake.nix"
          )

      with subtest("deploy with Colmena"):
          installer.succeed(
              "sed -i 's/inputs.skarabox.flakeModules.deploy-rs/"
              "# inputs.skarabox.flakeModules.deploy-rs/' ${repository}/flake.nix"
          )
          installer.succeed(
              "${nixRun "colmena"} apply --show-trace"
          )
          installer.succeed(
              "sed -i 's/# inputs.skarabox.flakeModules.deploy-rs/"
              "inputs.skarabox.flakeModules.deploy-rs/' ${repository}/flake.nix"
          )

      with subtest("password survives deployment"):
          installer.succeed(
              "${ssh} -F none sudo cat /etc/shadow | "
              "grep " + shlex.quote(hashed_password)
          )

      with subtest("shut down through SSH"):
          installer.succeed("${ssh} -F none sudo shutdown")
    ''}
  '';
}
