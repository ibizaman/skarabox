{
  gen-new-host,
  pkgs,
  sops-add-main-key,
  sops-create-main-key,
}:
let
  # gen-initial discovers the template through the flake containing its source
  # file. Use the real script and template with a dependency-free flake wrapper
  # so the build sandbox never needs to fetch inputs from the network.
  testSource = pkgs.runCommand "skarabox-template-test-source" { } ''
    mkdir -p "$out/lib"
    cp ${../lib/gen-initial.nix} "$out/lib/gen-initial.nix"
    cp -r ${../template} "$out/template"
    cat > "$out/flake.nix" <<'EOF'
    {
      outputs = { self }: {
        templates = {
          skarabox = {
            path = ./template;
            description = "Skarabox template";
          };
          default = self.templates.skarabox;
        };
      };
    }
    EOF
  '';
  init = import "${testSource}/lib/gen-initial.nix" {
    inherit
      gen-new-host
      pkgs
      sops-add-main-key
      sops-create-main-key
      ;
  };
in
pkgs.testers.runNixOSTest {
  name = "template";

  nodes.installer = {
    environment.systemPackages = [
      init
      pkgs.sops
    ];
    nix.settings.experimental-features = [
      "flakes"
      "nix-command"
    ];
  };

  testScript = ''
    installer.start()
    installer.succeed("mkdir -p /tmp/codex/template")
    installer.succeed(
        "cd /tmp/codex/template && printf 'skarabox1234\\n' | gen-initial -v -y -s",
        timeout=300,
    )
    installer.succeed("test -f /tmp/codex/template/flake.nix")
    installer.succeed("test -f /tmp/codex/template/myskarabox/configuration.nix")
    installer.succeed("test -s /tmp/codex/template/myskarabox/secrets.yaml")
    installer.succeed("test -s /tmp/codex/template/sops.key")
    installer.succeed(
        "cd /tmp/codex/template && "
        "SOPS_AGE_KEY_FILE=./sops.key "
        "sops decrypt --extract "
        "'[\"myskarabox\"][\"user\"][\"hashedPassword\"]' "
        "./myskarabox/secrets.yaml | grep -q '^\\$'"
    )
    installer.fail(
        "grep -R \"I'm empty and in plain text right now\" /tmp/codex/template"
    )
  '';
}
