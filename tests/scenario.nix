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
  initPackage = skarabox.packages.${fixture.host.system}.init;
  installPackage = hostPackages."${fixture.host.name}-install-on-beacon";

  nix = "${pkgs.lib.getExe pkgs.nix} --extra-experimental-features 'nix-command flakes' --allow-import-from-derivation --print-build-logs";
  scenarioPackages = [
    initPackage
    hostPackages."${fixture.host.name}-gen-knownhosts-file"
    hostPackages."${fixture.host.name}-get-facter"
    installPackage
    hostPackages."${fixture.host.name}-ssh"
    hostPackages."${fixture.host.name}-unlock"
  ]
  ++ pkgs.lib.optionals fullScenario [
    inputs.colmena.packages.${fixture.host.system}.colmena
    inputs.deploy-rs.packages.${fixture.host.system}.deploy-rs
    hostPackages.sops
  ];
  hostTools = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.git
    pkgs.gnugrep
    pkgs.jq
    pkgs.nix
    pkgs.openssh
    pkgs.gnused
  ];
  deploymentInputs = map (check: check.inputDerivation) (
    builtins.attrValues testFlake.checks.${fixture.host.system}
  );
  scenarioClosure = pkgs.closureInfo {
    rootPaths = [
      beaconVM
      diskoScript
      skarabox.outPath
      targetSystem
    ]
    ++ hostTools
    ++ scenarioPackages
    ++ templateSources
    ++ pkgs.lib.optional (hostNixpkgs != null) hostNixpkgs
    ++ [
      initPackage.inputDerivation
      installPackage.inputDerivation
    ]
    ++ pkgs.lib.optionals fullScenario ([ colmenaTargetSystem ] ++ deploymentInputs);
  };
in
pkgs.testers.runNixOSTest {
  inherit name;

  # No installer node is needed: commands run in the test derivation while the
  # custom beacon machine remains the only VM.
  nodes = { };

  testScript = ''
    import os
    import pathlib
    import shlex
    import subprocess
    import tempfile
    import time

    working_directory = pathlib.Path(tempfile.mkdtemp(prefix="skarabox-"))
    repository = working_directory / "repository"
    repository.mkdir()

    state_directory = working_directory / "nix-state"
    environment = os.environ.copy()
    environment.update({
        "HOME": str(working_directory / "home"),
        "NIX_CONFIG": "experimental-features = nix-command flakes",
        "NIX_LOG_DIR": str(state_directory / "log"),
        "NIX_REMOTE": "local",
        "NIX_STATE_DIR": str(state_directory),
        "PATH": "${pkgs.lib.makeBinPath hostTools}",
        "XDG_CACHE_HOME": str(working_directory / "cache"),
    })
    for directory in (
        pathlib.Path(environment["HOME"]),
        pathlib.Path(environment["XDG_CACHE_HOME"]),
    ):
        directory.mkdir(parents=True)

    # The sandbox can read these store paths but has no daemon or writable
    # system database, so register the complete, prebuilt scenario closure in a
    # private Nix database.
    with pathlib.Path("${scenarioClosure}/registration").open() as registration:
        subprocess.run(
            ["${pkgs.nix}/bin/nix-store", "--load-db"],
            check=True,
            env=environment,
            stdin=registration,
        )

    def run(
        *,
        script: str,
        capture_output: bool = False,
        input_text: str | None = None,
    ) -> str:
        print(f"$ {script}", flush=True)
        result = subprocess.run(
            ["${pkgs.runtimeShell}", "-euo", "pipefail", "-c", script],
            check=True,
            cwd=repository,
            env=environment,
            input=input_text,
            stdin=subprocess.DEVNULL if input_text is None else None,
            stdout=subprocess.PIPE if capture_output else None,
            text=True,
        )
        return result.stdout or ""

    def must_fail(*, script: str) -> None:
        try:
            run(script=script)
        except subprocess.CalledProcessError:
            return
        raise AssertionError(f"command unexpectedly succeeded: {script}")

    def nix_run(package: str) -> str:
        return f"${nix} run --offline .#{package} --"

    def retry_shell(command: str) -> str:
        return f"until {command}; do sleep 5; done"

    # qemuBinary uses a host-dependent -cpu max. QEMU honors the final -cpu
    # option, so use a stable model that matches the prebuilt facter fixture.
    beacon = create_machine(
        start_command=(
            "cd "
            + shlex.quote(str(repository))
            + " && exec ${pkgs.lib.getExe beaconVM} -cpu qemu64,-svm"
        ),
        name="beacon",
    )
    driver.machines_qemu.append(beacon)

    with subtest("initialize template"):
        run(
            script="${nix} run --offline path:${skarabox.outPath}#init -- -v -y -s",
            input_text="skarabox1234\\n",
        )
        must_fail(script="grep -R \"I'm empty and in plain text right now\" .")

        # The beacon and target are built before this test runs, so replace the
        # generated identities and secrets with their public test fixtures.
        run(
            script=(
                "install -m 0600 ${fixture.files.clientPrivateKey} ${fixture.host.name}/ssh && "
                "install -m 0644 ${fixture.files.clientPublicKey} ${fixture.host.name}/ssh.pub && "
                "install -m 0600 ${fixture.files.hostPrivateKey} ${fixture.host.name}/host_key && "
                "install -m 0644 ${fixture.files.hostPublicKey} ${fixture.host.name}/host_key.pub && "
                "install -m 0600 ${fixture.files.sopsPrivateKey} sops.key && "
                "install -m 0644 ${fixture.files.secrets} ${fixture.host.name}/secrets.yaml"
            )
        )
        run(
            script=(
                "sed -i 's/ip = \"192.168.1.30\"/ip = \"${fixture.host.ip}\"/' flake.nix && "
                "sed -i 's/system = \"x86_64-linux\"/system = \"${fixture.host.system}\"/' flake.nix && "
                "sed -i 's/skarabox.sshPort = 2222/skarabox.sshPort = ${toString fixture.host.sshPort}/' "
                "${fixture.host.name}/configuration.nix && "
                "sed -i 's/skarabox.boot.sshPort = 2223/"
                "skarabox.boot.sshPort = ${toString fixture.host.sshBootPort}/' "
                "${fixture.host.name}/configuration.nix && "
                "sed -i 's/skarabox.hostId = \"[^\"]*\"/"
                "skarabox.hostId = \"${fixture.host.hostId}\"/' "
                "${fixture.host.name}/configuration.nix && "
                "sed -i 's/skarabox.machineId = \"[^\"]*\"/"
                "skarabox.machineId = \"${fixture.host.machineId}\"/' "
                "${fixture.host.name}/configuration.nix"
            )
        )
        ${pkgs.lib.optionalString legacyNixpkgs ''
          run(
              script=(
                  "sed -i 's/nixpkgs = inputs.selfhostblocks.lib.''${system}.patchedNixpkgs;/"
                  "nixpkgs = null;/' flake.nix && "
                  "sed -i '/inputs.selfhostblocks.nixosModules.default$/d' flake.nix"
              )
          )
        ''}
        run(
            script=(
                "git init && "
                "printf '.skarabox-tmp\\n' > .gitignore && "
                "git config user.name skarabox && "
                "git config user.email skarabox@skarabox.com && "
                "git add . && "
                "git commit -m 'init repository'"
            )
        )
        run(
            script=(
                "${nix} flake update --offline --override-input "
                "skarabox path:${skarabox.outPath} skarabox && "
                "git add flake.lock && "
                "git commit -m 'use local skarabox input'"
            )
        )
        run(
            script=(
                nix_run("${fixture.host.name}-gen-knownhosts-file")
                + "${pkgs.lib.optionalString knownHostsShowTrace " --show-trace"} && "
                "git add ${fixture.host.name}/known_hosts && "
                "git commit -m 'generate known hosts'"
            )
        )

    ${pkgs.lib.optionalString (!fixture.disks.dataPool.enable) ''
      run(
          script="sed -i 's/enable = true/enable = false/' ${fixture.host.name}/configuration.nix"
      )
    ''}
    ${pkgs.lib.optionalString (fixture.disks.rootPool.disk2 != null) ''
      run(
          script=(
              "sed -i 's-disk2 = null-disk2 = \"${fixture.disks.rootPool.disk2}\"-' "
              "${fixture.host.name}/configuration.nix"
          )
      )
    ''}
    ${pkgs.lib.optionalString (fixture.host.staticNetwork != null) ''
      run(
          script=(
              "sed -i 's-staticNetwork = null-staticNetwork = "
              "{ ip=\"${fixture.host.staticNetwork.ip}\"; "
              "gateway=\"${fixture.host.staticNetwork.gateway}\"; }-' "
              "${fixture.host.name}/configuration.nix"
          )
      )
    ''}

    with subtest("show generated flake"):
        run(script="${nix} flake show --offline")

    beacon.start(allow_reboot=True)
    time.sleep(10)

    ssh = nix_run("${fixture.host.name}-ssh")
    unlock = nix_run("${fixture.host.name}-unlock")

    with subtest("connect to beacon"):
        run(
            script=retry_shell(
                f"{ssh} -F none -o CheckHostIP=no "
                "-o StrictHostKeyChecking=no echo connected"
            )
        )

    with subtest("generate hardware configuration"):
        run(
            script=(
                nix_run("${fixture.host.name}-get-facter")
                + " > ${fixture.host.name}/facter.json"
            )
        )
        run(script="jq < ${fixture.host.name}/facter.json")
        run(
            script=(
                "git add ${fixture.host.name}/facter.json && "
                "git commit -m 'generate hardware config'"
            )
        )
        actual_target = run(
            script=(
                "${nix} eval --raw "
                ".#nixosConfigurations.${fixture.host.name}.config.system.build.toplevel.outPath"
            ),
            capture_output=True,
        ).strip()
        assert actual_target == "${targetSystem}", (
            "generated target does not match the prebuilt QEMU fixture: "
            + actual_target
        )

    with subtest("install system"):
        run(
            script=(
                nix_run("${fixture.host.name}-install-on-beacon")
                + " --no-substitute-on-destination"
            )
        )

    with subtest("unlock and connect to installed system"):
        run(script=retry_shell(f"{unlock} -F none"))
        run(script=retry_shell(f"{ssh} -F none echo connected"))

    ${pkgs.lib.optionalString fullScenario ''
      with subtest("check password and persistent user maps"):
          hashed_password = run(
              script=(
                  nix_run("sops")
                  + " decrypt --extract "
                  "'[\"${fixture.host.name}\"][\"user\"][\"hashedPassword\"]' "
                  "${fixture.host.name}/secrets.yaml"
              ),
              capture_output=True,
          ).strip()
          run(
              script=(
                  f"{ssh} -F none sudo cat /etc/shadow | grep "
                  + shlex.quote(hashed_password)
              )
          )
          uid_map = run(
              script=f"{ssh} -F none sudo cat /var/lib/nixos/uid-map",
              capture_output=True,
          )
          gid_map = run(
              script=f"{ssh} -F none sudo cat /var/lib/nixos/gid-map",
              capture_output=True,
          )
          assert uid_map, "No uid map found"
          assert gid_map, "No gid map found"

      with subtest("reboot and recheck persistent state"):
          run(script=f'{ssh} -F none "(sleep 2 && sudo reboot)&"')
          run(script=retry_shell(f"{unlock} -F none"))
          run(script=retry_shell(f"{ssh} -F none echo connected"))
          run(
              script=(
                  f"{ssh} -F none sudo cat /etc/shadow | grep "
                  + shlex.quote(hashed_password)
              )
          )
          assert run(
              script=f"{ssh} -F none sudo cat /var/lib/nixos/uid-map",
              capture_output=True,
          ) == uid_map
          assert run(
              script=f"{ssh} -F none sudo cat /var/lib/nixos/gid-map",
              capture_output=True,
          ) == gid_map

      with subtest("deploy with deploy-rs"):
          run(
              script=(
                  "sed -i 's/inputs.skarabox.flakeModules.colmena/"
                  "# inputs.skarabox.flakeModules.colmena/' flake.nix"
              )
          )
          run(script=nix_run("deploy-rs") + " --debug-logs --temp-path .tmp")
          run(
              script=(
                  "sed -i 's/# inputs.skarabox.flakeModules.colmena/"
                  "inputs.skarabox.flakeModules.colmena/' flake.nix"
              )
          )

      with subtest("deploy with Colmena"):
          run(
              script=(
                  "sed -i 's/inputs.skarabox.flakeModules.deploy-rs/"
                  "# inputs.skarabox.flakeModules.deploy-rs/' flake.nix"
              )
          )
          run(script=nix_run("colmena") + " apply --show-trace")
          run(
              script=(
                  "sed -i 's/# inputs.skarabox.flakeModules.deploy-rs/"
                  "inputs.skarabox.flakeModules.deploy-rs/' flake.nix"
              )
          )

      with subtest("password survives deployment"):
          run(
              script=(
                  f"{ssh} -F none sudo cat /etc/shadow | grep "
                  + shlex.quote(hashed_password)
              )
          )

      with subtest("shut down through SSH"):
          run(script=f"{ssh} -F none sudo shutdown")
    ''}
  '';
}
