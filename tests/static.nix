{
  inputs,
  pkgs,
  skarabox,
  system,
  templateSources,
}:
{
  staticIP = import ./scenario.nix {
    inherit
      inputs
      pkgs
      skarabox
      system
      templateSources
      ;
    name = "staticIP";
    dataPool = true;
    fullScenario = false;
    knownHostsShowTrace = false;
    rootDisk2 = false;
    staticNetwork = {
      ip = "10.0.2.15";
      gateway = "10.0.2.255";
    };
  };
}
