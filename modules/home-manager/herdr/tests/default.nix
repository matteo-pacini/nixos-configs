# The herdr module's tests, as flake checks:
#   nix build .#checks.<system>.herdr-layout   (or herdr-js, herdr-scripts)
{ pkgs }:
let
  inherit (pkgs) lib;
  # Symlinks in mods/ point into lib/, so both come along. claude-mods/ holds
  # the logic the JS tests load.
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../claude-mods
      ../lib
      ../mods
      ../scripts
      ./.
    ];
  };
  layoutFailures = import ./layout.nix { inherit lib; };
in
{
  herdr-layout =
    pkgs.runCommand "herdr-layout-tests"
      {
        failures = builtins.toJSON layoutFailures;
        passAsFile = [ "failures" ];
      }
      ''
        if [ "$(cat "$failuresPath")" != "[]" ]; then
          echo "layout.nix tests failed:"
          ${lib.getExe pkgs.jq} . "$failuresPath"
          exit 1
        fi
        touch $out
      '';

  herdr-js =
    pkgs.runCommand "herdr-js-tests"
      {
        nativeBuildInputs = [
          pkgs.nodejs
          pkgs.git
        ];
      }
      ''
        cd ${src}/tests/js
        node --import ./hooks.mjs --test
        # The mods themselves load only in the app; this much is checked here:
        # that each parses.
        for mod in ${src}/mods/*/main.js; do
          cat "$mod" >"$TMPDIR/mod.mjs"
          node --check "$TMPDIR/mod.mjs"
        done
        touch $out
      '';

  herdr-scripts =
    pkgs.runCommand "herdr-script-tests"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.gnugrep
          pkgs.gnused
        ];
      }
      ''
        bash ${src}/tests/scripts/run.sh ${src}/scripts
        touch $out
      '';
}
