# desk-sync's tests, as a flake check:
#   nix build .#checks.<system>.desk-sync
{ pkgs }:
{
  desk-sync =
    pkgs.runCommand "desk-sync-tests"
      {
        nativeBuildInputs = with pkgs; [
          diffutils
          findutils
          gnugrep
          gnused
          git
        ];
      }
      ''
        bash ${./run.sh} ${../desk-sync.sh}
        touch $out
      '';
}
