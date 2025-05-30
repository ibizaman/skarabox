{
  pkgs
}:
pkgs.writeShellApplication {
  name = "sops-create-main-key";

  runtimeInputs = [
    pkgs.age
  ];

  text = ''
    sops_key=''${1:-sops.key}
    age-keygen -o "$sops_key"
  '';
}
