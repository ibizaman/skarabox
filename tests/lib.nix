{
  pkgs,
  ...
}:
let
  add-sops-cfg = pkgs.callPackage ../lib/add-sops-cfg.nix {};

  exec = {
    name,
    cmd,
    init ? ""
  }: builtins.readFile ((pkgs.callPackage ({ runCommand }: runCommand name {
    nativeBuildInputs = [
      add-sops-cfg
    ];
  } (let
    initFile = pkgs.writeText "init-sops" init;
  in ''
    mkdir $out
    ${if init != "" then "cat ${initFile} > $out/.sops.yaml" else ""}
    add-sops-cfg -o $out/.sops.yaml ${cmd}
  '')) {}) + "/.sops.yaml");
in
{
  testAddSopsCfg_new_alias = {
    expected = ''
      keys:
      - &a ASOPSKEY
    '';

    expr = exec {
      name = "testAddSopsCfg_new_alias";
      cmd = "alias a ASOPSKEY";
    };
  };

  testAddSopsCfg_new_path_regex = {
    expected = ''
      keys:
      - &a ASOPSKEY
      creation_rules:
      - path_regex: a/b.yaml$
        key_groups:
        - age:
          - *a
    '';

    expr = exec {
      name = "testAddSopsCfg_new_path_regex";
      init = ''
        keys:
        - &a ASOPSKEY
      '';
      cmd = "path-regex a a/b.yaml$";
    };
  };

  testAddSopsCfg_update_alias = {
    expected = ''
      keys:
      - &a ASOPSKEY
      - &b BSOPSKEY
      creation_rules:
      - path_regex: a/b.yaml$
        key_groups:
        - age:
          - *a
    '';

    expr = exec {
      name = "testAddSopsCfg_update_alias";
      init = ''
        keys:
        - &a ASOPSKEY
        creation_rules:
        - path_regex: a/b.yaml$
          key_groups:
          - age:
            - *a
      '';
      cmd = "alias b BSOPSKEY";
    };
  };

  testAddSopsCfg_update_path_regex = {
    expected = ''
      keys:
      - &a ASOPSKEY
      - &b BSOPSKEY
      creation_rules:
      - path_regex: a/b.yaml$
        key_groups:
        - age:
          - *a
          - *b
    '';

    expr = exec {
      name = "testAddSopsCfg_update_path_regex";
      init = ''
        keys:
        - &a ASOPSKEY
        - &b BSOPSKEY
        creation_rules:
        - path_regex: a/b.yaml$
          key_groups:
          - age:
            - *a
      '';
      cmd = "path-regex b a/b.yaml$";
    };
  };

  testAddSopsCfg_append = {
    expected = ''
      keys:
      - &a ASOPSKEY
      creation_rules:
      - path_regex: a/b.yaml$
        key_groups:
        - age:
          - *a
      - path_regex: b/b.yaml$
        key_groups:
        - age:
          - *a
      '';

    expr = exec {
      name = "testAddSopsCfg_append";
      init = ''
        keys:
        - &a ASOPSKEY
        creation_rules:
        - path_regex: a/b.yaml$
          key_groups:
          - age:
            - *a
        '';
      cmd = "path-regex a b/b.yaml$";
    };
  };

  testAddSopsCfg_replace = {
    expected = ''
      keys:
      - &a OTHERSOPSKEY
      '';

    expr = exec {
      name = "testAddSopsCfg_replace";
      init = ''
        keys:
        - &a ASOPSKEY
        '';
      cmd = "alias a OTHERSOPSKEY";
    };
  };

  testAddSopsCfg_replace_with_reference = {
    expected = ''
      keys:
      - &b BSOPSKEY
      - &a OTHERSOPSKEY
      creation_rules:
      - path_regex: a/b.yaml$
        key_groups:
        - age:
          - *a
      - path_regex: b/b.yaml$
        key_groups:
        - age:
          - *b
      '';

    expr = exec {
      name = "testAddSopsCfg_replace";
      init = ''
        keys:
        - &a ASOPSKEY
        - &b BSOPSKEY
        creation_rules:
        - path_regex: a/b.yaml$
          key_groups:
          - age:
            - *a
        - path_regex: b/b.yaml$
          key_groups:
          - age:
            - *b
        '';
      cmd = "alias a OTHERSOPSKEY";
    };
  };

  testMultiHostSameArch = let
    # Create minimal test flake using the actual skarabox flakeModule
    dummy = pkgs.writeText "dummy" "";
    testFlake = import ../flakeModules/default.nix {
      inherit (pkgs) lib;
      config = {
        skarabox.hosts = {
          server1 = {
            system = "aarch64-linux";
            hostKeyPub = dummy;
            sshAuthorizedKey = dummy;
            knownHosts = dummy;
          };
          server2 = {
            system = "aarch64-linux";
            hostKeyPub = dummy;
            sshAuthorizedKey = dummy;
            knownHosts = dummy;
          };
          server3 = {
            system = "x86_64-linux";
            hostKeyPub = dummy;
            sshAuthorizedKey = dummy;
            knownHosts = dummy;
          };
        };
      };
      inputs = {
        skarabox.nixosModules.skarabox = {};
      };
    };

    # Get the flake outputs
    flakeOutputs = testFlake.config.flake {};

    # Check nixosConfigurations (all three should be present)
    configNames = builtins.sort builtins.lessThan (builtins.attrNames flakeOutputs.nixosConfigurations);

    # Check packages for aarch64-linux (both aarch64 hosts should appear)
    # Filter to just the base host packages (not the -debug-* variants)
    aarch64Packages = builtins.sort builtins.lessThan
      (builtins.filter (name: !(pkgs.lib.hasInfix "-debug-" name))
        (builtins.attrNames (flakeOutputs.packages."aarch64-linux" or {})));

    # Check packages for x86_64-linux (the x86_64 host should appear)
    x86Packages = builtins.sort builtins.lessThan
      (builtins.filter (name: !(pkgs.lib.hasInfix "-debug-" name))
        (builtins.attrNames (flakeOutputs.packages."x86_64-linux" or {})));
  in {
    expected = {
      configs = [ "server1" "server2" "server3" ];
      aarch64Packages = [ "server1" "server2" ];
      x86Packages = [ "server3" ];
    };
    expr = {
      configs = configNames;
      aarch64Packages = aarch64Packages;
      x86Packages = x86Packages;
    };
  };
}
