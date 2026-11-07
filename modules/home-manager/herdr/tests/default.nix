# The herdr module's tests, as flake checks:
#   nix build .#checks.<system>.herdr-layout   (or herdr-js, herdr-scripts)
{ pkgs }:
let
  inherit (pkgs) lib;
  # Symlinks in mods/ point into lib/, so both come along.
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
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

  herdr-js = pkgs.runCommand "herdr-js-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    cd ${src}/tests/js
    node --import ./hooks.mjs --test
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
