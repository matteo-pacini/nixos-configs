# The BrightFalls desktop's tests, as flake checks (each says below what it
# covers):
#   nix build .#checks.<system>.desk-sync
#   nix build .#checks.<system>.calendar-export
#   nix build .#checks.<system>.calendar-panel
#   nix build .#checks.<system>.bluetooth-panel
#   nix build .#checks.<system>.tray-panel
#   nix build .#checks.<system>.office-panel
#   nix build .#checks.<system>.office-helper
#   nix build .#checks.<system>.system-panel
#   nix build .#checks.<system>.display-layout
#   nix build .#checks.<system>.hypr-config
#   nix build .#checks.<system>.desk-unlock
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

  # The office panel's library (quickshell/office/office.js) against invented
  # helper events, inline and from office-panel/fixtures/.
  office-panel = pkgs.runCommand "office-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./office-panel}/test-office-panel.js ${../user/quickshell/office}
    touch $out
  '';

  # The system panel's library (quickshell/system/decode.js) against invented
  # gpu_metrics blobs and /proc, sysfs, df and LACT texts.
  system-panel = pkgs.runCommand "system-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./system/test-system.js} ${../user/quickshell/system}
    touch $out
  '';

  # display-layout (single-monitor and the restore bind) against a fake
  # hyprctl.
  display-layout =
    pkgs.runCommand "display-layout-tests"
      {
        nativeBuildInputs = with pkgs; [
          gnugrep
          gnused
          jq
        ];
      }
      ''
        bash ${./display-layout/run.sh} ${../../../../display-layout.sh} \
          ${../user/hypr/monitors.lua}
        touch $out
      '';

  # The Hyprland config, laid out as installed, through Hyprland
  # --verify-config, and theme.lua's reading of theme.json.
  hypr-config =
    pkgs.runCommand "hypr-config-tests"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        # lua5_5: the Lua the Hyprland package embeds.
        bash ${./hypr/run.sh} ${pkgs.lib.getExe' pkgs.hyprland "Hyprland"} \
          ${pkgs.lib.getExe pkgs.lua5_5} ${../user} ${../defaults}
        touch $out
      '';

  # desk-unlock (the recovery when the lock screen dies) against fake
  # hyprctl, systemctl and pkill.
  desk-unlock = pkgs.runCommand "desk-unlock-tests" { } ''
    bash ${./desk-unlock/run.sh} ${../desk-unlock.sh}
    touch $out
  '';

  # desk-mqtt (the office panel's helper) against a Mosquitto on loopback,
  # with the test playing Zigbee2MQTT under invented device names. Takes
  # about 40 s: it waits out the 5 s confirmation and two 10 s reconnects.
  office-helper =
    pkgs.runCommand "office-helper-tests"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.paho-mqtt ])) ];
      }
      ''
        mkdir work
        python3 -I ${./office/test-desk-mqtt.py} \
          ${pkgs.lib.getExe (pkgs.callPackage ../desk-mqtt.nix { })} \
          ${pkgs.lib.getExe' pkgs.mosquitto "mosquitto"} "$PWD/work"
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
