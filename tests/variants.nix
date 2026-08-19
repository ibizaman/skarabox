{
  inputs,
  pkgs,
  skarabox,
  system,
  templateSources,
}:
let
  templateTest =
    args:
    import ./scenario.nix (
      {
        inherit
          inputs
          pkgs
          skarabox
          system
          templateSources
          ;
      }
      // args
    );
in
{
  oneOSnoData = templateTest {
    name = "oneOSnoData";
    rootDisk2 = false;
    dataPool = false;
  };

  oneOStwoData = templateTest {
    name = "oneOStwoData";
    rootDisk2 = false;
    dataPool = true;
    sshPort = 3222;
  };

  twoOSnoData = templateTest {
    name = "twoOSnoData";
    rootDisk2 = true;
    dataPool = false;
    sshBootPort = 3223;
  };

  twoOStwoData = templateTest {
    name = "twoOStwoData";
    rootDisk2 = true;
    dataPool = true;
    sshPort = 3222;
    sshBootPort = 3223;
  };

  legacyNixpkgs = templateTest {
    name = "legacyNixpkgs";
    rootDisk2 = false;
    dataPool = false;
    legacyNixpkgs = true;
  };
}
