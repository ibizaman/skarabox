{
  inputs,
  pkgs,
  skarabox,
  system,
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
          ;
      }
      // args
    );
in
{
  # Distinct host ports allow the VM checks to run concurrently.
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
    sshBootPort = 3223;
  };

  twoOSnoData = templateTest {
    name = "twoOSnoData";
    rootDisk2 = true;
    dataPool = false;
    sshPort = 4222;
    sshBootPort = 4223;
  };

  twoOStwoData = templateTest {
    name = "twoOStwoData";
    rootDisk2 = true;
    dataPool = true;
    sshPort = 5222;
    sshBootPort = 5223;
  };

  legacyNixpkgs = templateTest {
    name = "legacyNixpkgs";
    rootDisk2 = false;
    dataPool = false;
    legacyNixpkgs = true;
    sshPort = 6222;
    sshBootPort = 6223;
  };
}
