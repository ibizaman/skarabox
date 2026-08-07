{
  inputs,
  pkgs,
  skarabox,
  system,
}:
{
  staticIP = import ./scenario.nix {
    inherit
      inputs
      pkgs
      skarabox
      system
      ;
    name = "staticIP";
    dataPool = false;
    rootDisk2 = false;
    # Keep host forwards distinct from the other VM checks.
    sshPort = 7222;
    sshBootPort = 7223;
    staticNetwork = {
      ip = "10.0.2.15";
      gateway = "10.0.2.2";
    };
  };
}
