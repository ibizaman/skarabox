{ inputs, pkgs }:
pkgs.testers.runNixOSTest {
  name = "vm";

  nodes.machine = {
    environment.systemPackages = [
      pkgs.nix
    ];

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    virtualisation.memorySize = 4096;
    virtualisation.writableStore = true;
  };

  testScript = ''
  # Equivalent to nix flake init --template github:ibizaman/skarabox
  machine.succeed("""
    cp -ar ${./..} /tmp/skarabox \
    && cd /tmp/skarabox \
    && nix flake update \
       --override-input nixpkgs ${inputs.nixpkgs} \
       --override-input flake-parts ${inputs.flake-parts} \
       --override-input nixos-anywhere ${inputs.nixos-anywhere} \
       --override-input nixos-generators ${inputs.nixos-generators} \
  """)
  machine.succeed("cd /tmp/skarabox && nix run .#beacon-vm >&2 &")
  machine.succeed("cd /tmp/skarabox && nix run .#install-on-beacon-vm >&2")
  '';
}
