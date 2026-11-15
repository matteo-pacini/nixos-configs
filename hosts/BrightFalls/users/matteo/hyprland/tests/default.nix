# desk-sync's, calendar-export's, the calendar panel's, the Bluetooth
# panel's and the tray menu's tests, as flake checks:
#   nix build .#checks.<system>.desk-sync
#   nix build .#checks.<system>.calendar-export
#   nix build .#checks.<system>.calendar-panel
#   nix build .#checks.<system>.bluetooth-panel
#   nix build .#checks.<system>.tray-panel
{ pkgs }:
let
  calendarExport = import ../calendar-export.nix { inherit pkgs; };
  # The work directory is only known at build time; substituted below.
  khalConfig = calendarExport.khalConfig {
    workDir = "@workDir@";
    timeZone = "Europe/London";
  };
in
{
  # The export of calendar/fixtures/ as of CALENDAR_NOW must equal
  # calendar/expected.jsonl. Regenerating it: README.md, "Calendar events".
  calendar-export =
    pkgs.runCommand "calendar-export-tests"
      {
        nativeBuildInputs = [ pkgs.diffutils ];
        LANG = "C.UTF-8";
        CALENDAR_NOW = "2026-11-15T10:00:00+00:00";
      }
      ''
        export HOME=$PWD
        substitute ${khalConfig} khal.conf --replace-fail @workDir@ "$PWD/work"
        ${pkgs.lib.getExe calendarExport.package} \
          ${./calendar/fixtures} "$PWD/work" khal.conf "$PWD/events.jsonl"
        diff -u ${./calendar/expected.jsonl} events.jsonl
        touch $out
      '';

  # The panel's query library (quickshell/calendar/queries.js) against
  # invented events in calendar/panel/; the dates it asserts are London's.
  calendar-panel =
    pkgs.runCommand "calendar-panel-tests"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
        TZ = "Europe/London";
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      }
      ''
        node ${./calendar/panel}/test-calendar.js \
          ${../user/quickshell/calendar/queries.js}
        touch $out
      '';

  # The panel's libraries (quickshell/bluetooth/services.js, devices.js)
  # against invented devices and links.
  bluetooth-panel =
    pkgs.runCommand "bluetooth-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node ${./bluetooth/test-bluetooth.js} ${../user/quickshell/bluetooth}
        touch $out
      '';

  # The tray menu's library (quickshell/tray/menu.js): the header's name and
  # the entries' marks.
  tray-panel = pkgs.runCommand "tray-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./tray/test-tray.js} ${../user/quickshell/tray}
    touch $out
  '';

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
