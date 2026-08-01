{
  dataPool,
  inputs,
  legacyNixpkgs ? false,
  name,
  pkgs,
  rootDisk2,
  skarabox,
  sshBootPort ? 2223,
  sshPort ? 2222,
  staticNetwork ? null,
  system,
}:
let
  testFixture = import ./test-flake.nix {
    inherit
      dataPool
      inputs
      legacyNixpkgs
      rootDisk2
      skarabox
      sshBootPort
      sshPort
      staticNetwork
      system
      ;
  };
  testFlake = testFixture.flake;
  targetConfig = testFlake.nixosConfigurations.test.config;
  targetSystem = targetConfig.system.build.toplevel;
  diskoScript = targetConfig.system.build.diskoScript;
  hostPackages = testFlake.packages.${system};
  beaconVM = hostPackages.test-beacon-vm;
  getFacter = hostPackages.test-get-facter;
  genKnownHosts = hostPackages.test-gen-knownhosts-file;
  installOnBeacon = hostPackages.test-install-on-beacon;
  ssh = hostPackages.test-ssh;
  sshBeacon = hostPackages.test-ssh-beacon;
  unlock = hostPackages.test-unlock;

  # This fixed private key is deliberately public test data. Building the
  # target before boot requires its host and authorized keys during evaluation.
  sshPrivateKey = ./fixtures/insecure-test-ssh-key;
  # The generated wrapper supplies its flake first. Override it with an empty
  # final value so nixos-anywhere uses the prebuilt store paths instead.
  installCommand = pkgs.lib.escapeShellArgs [
    (pkgs.lib.getExe installOnBeacon)
    "--phases"
    "disko,install,reboot"
    "--flake"
    ""
    "--store-paths"
    diskoScript
    targetSystem
    "--no-substitute-on-destination"
  ];
in
pkgs.testers.runNixOSTest {
  inherit name;

  nodes.installer = {
    environment.systemPackages = [
      pkgs.jq
      pkgs.openssh
    ];
    # Make the prebuilt install artifacts available in the installer VM's store.
    system.extraDependencies = [
      diskoScript
      targetSystem
    ];
    environment.etc = {
      # These fixed SOPS files are deliberately public test data used by the
      # generated install and unlock wrappers.
      "scenario/secrets.yaml".source = ./fixtures/insecure-test-secrets.yaml;
      "scenario/sops-key" = {
        source = ./fixtures/insecure-test-sops-key;
        mode = "0600";
      };
      "scenario/ssh" = {
        source = sshPrivateKey;
        mode = "0600";
      };
    };
    virtualisation = {
      cores = 2;
      diskSize = 20 * 1024;
      memorySize = 4096;
    };
  };

  testScript = ''
    import shlex

    # Running the beacon inside the installer VM would require nested virtualization.
    # QEMU defaults to one vCPU, which makes installation dominate CI runtime.
    beacon = create_machine(
        start_command="exec ${pkgs.lib.getExe beaconVM} -smp 2",
        name="beacon",
    )
    driver.machines_qemu.append(beacon)
    beacon.start(allow_reboot=True)
    installer.start()

    with subtest("generate final host known_hosts"):
        installer.succeed("mkdir -p /tmp/codex/scenario")
        installer.succeed("${pkgs.lib.getExe genKnownHosts}")
        installer.succeed(
            "ssh-keygen -F 10.0.2.2 -f /tmp/codex/scenario/known-hosts"
        )
        installer.succeed(
            "ssh-keygen -F '[10.0.2.2]:${toString sshPort}' "
            "-f /tmp/codex/scenario/known-hosts"
        )
        installer.succeed(
            "ssh-keygen -F '[10.0.2.2]:${toString sshBootPort}' "
            "-f /tmp/codex/scenario/known-hosts"
        )

    with subtest("beacon is reachable"):
        installer.wait_until_succeeds(
            "${pkgs.lib.getExe sshBeacon} "
            "'test \"$(hostname)\" = test-beacon'",
            timeout=300,
        )

    with subtest("collect hardware configuration"):
        installer.succeed(
            "${pkgs.lib.getExe getFacter} > /tmp/codex/facter.json",
            timeout=300,
        )
        installer.succeed("jq -e 'type == \"object\"' /tmp/codex/facter.json")

    with subtest("install prebuilt system"):
        # Keep installation independent from the synchronous backdoor command
        # while nixos-anywhere replaces and reboots the target.
        installer.succeed(
            "systemd-run --unit=skarabox-install "
            "--setenv=HOME=/root "
            "--property=StandardOutput=append:/tmp/codex/skarabox-install.log "
            "--property=StandardError=append:/tmp/codex/skarabox-install.log "
            "${installCommand}",
        )
        installer.wait_until_succeeds(
            "state=$(systemctl show -p ActiveState --value skarabox-install); "
            "test \"$state\" = inactive || test \"$state\" = failed",
            timeout=1200,
        )
        installer.succeed(
            "test \"$(systemctl show -p Result --value "
            "skarabox-install)\" = success "
            "|| { cat /tmp/codex/skarabox-install.log; false; }"
        )

    unlock_command = "${pkgs.lib.getExe unlock}"
    def target_command(*, command: str) -> str:
        return "${pkgs.lib.getExe ssh} " + shlex.quote(command)

    def target_password_hash() -> str:
        return installer.succeed(
            target_command(
                command="sudo getent shadow skarabox | cut -d: -f2"
            )
        ).strip()

    with subtest("unlock and boot installed system"):
        installer.wait_until_succeeds(unlock_command, timeout=300)
        installer.wait_until_succeeds(
            target_command(command="test \"$(hostname)\" = test"),
            timeout=300,
        )

    with subtest("storage topology is correct"):
        installer.succeed(
            target_command(
                command="sudo zpool status -LP root | grep -F /dev/nvme0n1p2"
            )
        )
        ${
          if rootDisk2 then
            ''
              installer.succeed(
                  target_command(
                      command="sudo zpool status -LP root | grep -F /dev/nvme1n1p2"
                  )
              )
            ''
          else
            ''
              installer.fail(
                  target_command(
                      command="sudo zpool status -LP root | grep -F /dev/nvme1n1p2"
                  )
              )
            ''
        }
        ${
          if dataPool then
            ''
              installer.succeed(
                  target_command(
                      command="sudo zpool status -LP zdata | grep -F /dev/sda1"
                  )
              )
              installer.succeed(
                  target_command(
                      command="sudo zpool status -LP zdata | grep -F /dev/sdb1"
                  )
              )
            ''
          else
            ''
              installer.fail(target_command(command="sudo zpool status zdata"))
            ''
        }

    with subtest("password and persistent user maps are populated"):
        password_hash = target_password_hash()
        assert password_hash == "${testFixture.testPasswordHash}"
        uid_map = installer.succeed(
            target_command(command="sudo cat /var/lib/nixos/uid-map")
        ).strip()
        gid_map = installer.succeed(
            target_command(command="sudo cat /var/lib/nixos/gid-map")
        ).strip()
        assert uid_map, "No uid map found"
        assert gid_map, "No gid map found"

    with subtest("state survives a reboot"):
        installer.succeed(
            target_command(
                command="(sleep 1 && sudo reboot) >/dev/null 2>&1 &"
            )
        )
        installer.wait_until_succeeds(unlock_command, timeout=300)
        installer.wait_until_succeeds(
            target_command(command="true"),
            timeout=300,
        )
        assert installer.succeed(
            target_command(command="sudo cat /var/lib/nixos/uid-map")
        ).strip() == uid_map
        assert installer.succeed(
            target_command(command="sudo cat /var/lib/nixos/gid-map")
        ).strip() == gid_map
        assert target_password_hash() == password_hash

    with subtest("shut down through SSH"):
        installer.succeed(
            target_command(command="sudo systemctl poweroff --no-block")
        )
        beacon.wait_for_shutdown()
  '';
}
