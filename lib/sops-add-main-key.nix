{
  pkgs,
  add-sops-cfg,
}:
pkgs.writeShellApplication {
  name = "sops-add-main-key";

  runtimeInputs = [
    pkgs.age
    add-sops-cfg
  ];

  text = ''
    sops_key=''${1:-sops.key}
    sops_cfg=''${2:-.sops.yaml}
    main_age_key="$(age-keygen -y "$sops_key")"
    add-sops-cfg -o "$sops_cfg" alias main "$main_age_key"
  '';
}
