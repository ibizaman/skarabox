# Taken nearly verbatim from https://github.com/nix-community/home-manager/pull/4673
# Read these docs online at https://shb.skarabox.com.
{ pkgs
, buildPackages
, lib
, nmdsrc
, stdenv
, documentation-highlighter
, nixos-render-docs

, release
, skaraboxModules
, beaconModules
, flakeModuleModules
}:

let
  shbPath = toString ./..;

  gitHubDeclaration = user: repo: subpath:
    let urlRef = "main";
        end = if subpath == "" then "" else "/" + subpath;
    in {
      url = "https://github.com/${user}/${repo}/blob/${urlRef}${end}";
      name = "<${repo}${end}>";
    };

  ghRoot = (gitHubDeclaration "ibizaman" "skarabox" "").url;

  buildOptionsDocs = args@{ modules, ... }:
    let
      config = {
        _module.check = false;
        _module.args = {};
        system.stateVersion = "22.11";
      };

      utils = import "${pkgs.path}/nixos/lib/utils.nix" {
        inherit config lib;
        pkgs = null;
      };

      eval = lib.evalModules {
        inherit modules;

        specialArgs = {
          inherit utils;
        };
      };

      options = lib.filterAttrs (name: v: name == "skarabox") eval.options;
    in buildPackages.nixosOptionsDoc ({
      inherit options;

      transformOptions = opt:
        opt // {
          # Clean up declaration sites to not refer to the Home Manager
          # source tree.
          declarations = map (decl:
            gitHubDeclaration "ibizaman" "skarabox"
              (lib.removePrefix "/" (lib.removePrefix shbPath (toString decl)))) opt.declarations;
        };
    } // builtins.removeAttrs args [ "modules" "includeModuleSystemOptions" ]);

  scrubbedModule = {
    _module.args.pkgs = lib.mkForce (nmd.scrubDerivations "pkgs" pkgs);
    _module.check = false;
  };

  mkOptionsDocs = modules: (buildOptionsDocs {
    modules = modules ++ [ scrubbedModule ];
    variablelistId = "skarabox-options";
  }).optionsJSON;

  nmd = import nmdsrc {
    inherit lib;
    # The DocBook output of `nixos-render-docs` doesn't have the change
    # `nmd` uses to work around the broken stylesheets in
    # `docbook-xsl-ns`, so we restore the patched version here.
    pkgs = pkgs // {
      docbook-xsl-ns =
        pkgs.docbook-xsl-ns.override { withManOptDedupPatch = true; };
    };
  };

  outputPath = "share/doc/skarabox";

  manpage-urls = pkgs.writeText "manpage-urls.json" ''{}'';
in stdenv.mkDerivation {
  name = "skarabox-manual";

  nativeBuildInputs = [ nixos-render-docs ];

  # We include the parent so we get the documentation inside the root
  # modules/ folders.
  src = ./..;

  buildPhase = ''
    cd docs

    cp -t . -r ../modules

    mkdir -p out/media
    mkdir -p out/highlightjs
    mkdir -p out/static

    cp -t out/highlightjs \
      ${documentation-highlighter}/highlight.pack.js \
      ${documentation-highlighter}/LICENSE \
      ${documentation-highlighter}/mono-blue.css \
      ${documentation-highlighter}/loader.js

    cp -t out/static \
      ${nmdsrc}/static/style.css \
      ${nmdsrc}/static/highlightjs/tomorrow-night.min.css \
      ${nmdsrc}/static/highlightjs/highlight.min.js \
      ${nmdsrc}/static/highlightjs/highlight.load.js

    substituteInPlace ./manual.md \
      --replace-fail \
        '@VERSION@' \
        ${builtins.readFile ../VERSION}

    substituteInPlace ./installation.md \
      --replace-fail \
        '@VERSION@' \
        ${builtins.readFile ../VERSION}

    substituteInPlace ./normal-operations.md \
      --replace-fail \
        '@VERSION@' \
        ${builtins.readFile ../VERSION}

    substituteInPlace ./options.md \
      --replace-fail \
        '@SKARABOX_OPTIONS_JSON@' \
        ${mkOptionsDocs skaraboxModules}/share/doc/nixos/options.json

    substituteInPlace ./options.md \
      --replace-fail \
        '@BEACON_OPTIONS_JSON@' \
        ${mkOptionsDocs beaconModules}/share/doc/nixos/options.json

    substituteInPlace ./options.md \
      --replace-fail \
        '@FLAKE_MODULE_OPTIONS_JSON@' \
        ${mkOptionsDocs flakeModuleModules}/share/doc/nixos/options.json

    find . -name "*.md" -print0 | \
      while IFS= read -r -d ''' f; do
        substituteInPlace "''${f}" \
          --replace-warn \
            '@REPO@' \
            "${ghRoot}" 2>/dev/null
      done

    nixos-render-docs manual html \
      --manpage-urls ${manpage-urls} \
      --media-dir media \
      --revision ${lib.trivial.revisionWithDefault release} \
      --stylesheet static/style.css \
      --stylesheet static/tomorrow-night.min.css \
      --script static/highlight.min.js \
      --script static/highlight.load.js \
      --toc-depth 1 \
      --section-toc-depth 1 \
      manual.md \
      out/index.html
  '';

  installPhase = ''
    dest="$out/${outputPath}"
    mkdir -p "$(dirname "$dest")"
    mv out "$dest"
    mkdir -p $out/nix-support/
    echo "doc manual $dest index.html" >> $out/nix-support/hydra-build-products
  '';
}
