# The BrightFalls desktop's tests, as flake checks; each says below what it
# covers. One check: nix build .#checks.x86_64-linux.<name>
# All but hypr-config, through one attribute (what CI builds):
#   nix build -L .#checks.x86_64-linux.brightfalls-tests
{ pkgs }:
let
  calendarExport = import ../calendar-export.nix { inherit pkgs; };
  # The work directory is only known at build time; substituted below.
  khalConfig = calendarExport.khalConfig {
    workDir = "@workDir@";
    timeZone = "Europe/London";
  };
in
pkgs.lib.fix (self: {
  # Every check in this set but hypr-config (and itself). hypr-config is run
  # by hand before a change to the Hyprland config: Hyprland --verify-config
  # crashes (exit 139) on the full hyprland.lua on GitHub's runners, cause
  # not known.
  brightfalls-tests = pkgs.linkFarm "brightfalls-tests" (
    builtins.removeAttrs self [
      "brightfalls-tests"
      "hypr-config"
    ]
  );

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

        # A second run into the same work directory after the calendars
        # change (a calendar gone, a file gone, two files edited, one of
        # them rewritten by the GMT fix), against a run from scratch.
        cp -r --no-preserve=mode ${./calendar/fixtures} vdir
        run() { # vdir, work, output
          mkdir -p "$2"
          substitute ${khalConfig} "$2.conf" --replace-fail @workDir@ "$2"
          ${pkgs.lib.getExe calendarExport.package} "$1" "$2" "$2.conf" "$3"
        }
        run vdir "$PWD/inc" first.jsonl
        diff -u ${./calendar/expected.jsonl} first.jsonl
        rm -r vdir/fixE vdir/fixA/weekly.ics
        sed -i 's/^SUMMARY:FX crosses midnight/SUMMARY:FX renamed/' vdir/fixB/midnight.ics
        sed -i 's/^SUMMARY:.*/SUMMARY:FX renamed GMT/' vdir/fixD/gmt-summer.ics
        run vdir "$PWD/inc" again.jsonl
        run vdir "$PWD/scratch" scratch.jsonl
        grep -q '"title": "FX renamed"' scratch.jsonl
        grep -q '"title": "FX renamed GMT"' scratch.jsonl
        if grep -q 'fx-weekly\|fx-alarm-' again.jsonl; then
          echo "a removed file or calendar is still exported"
          exit 1
        fi
        diff -u scratch.jsonl again.jsonl

        # A copy made by an older format is rebuilt.
        echo 0 >inc/vdir/.format
        run vdir "$PWD/inc" rebuilt.jsonl
        diff -u scratch.jsonl rebuilt.jsonl

        # khal rescans a calendar only when its directory's mtime changes:
        # a run with nothing changed leaves it alone, and an edit to a file
        # that is already copied changes it.
        before=$(stat -c %y inc/vdir/fixB)
        run vdir "$PWD/inc" same.jsonl
        [ "$(stat -c %y inc/vdir/fixB)" = "$before" ]
        sed -i 's/^SUMMARY:FX renamed$/SUMMARY:FX renamed twice/' vdir/fixB/midnight.ics
        run vdir "$PWD/inc" edited.jsonl
        grep -q '"title": "FX renamed twice"' edited.jsonl

        # A file that is not UTF-8 and one that is not iCalendar are left
        # out, counted on stderr without their names; the rest of their
        # calendar is exported as without them.
        mkdir good bad
        cp -r --no-preserve=mode ${./calendar/fixtures}/fixE good/
        cp -r good/fixE bad/
        printf 'BEGIN:VCALENDAR\r\nSUMMARY:caf\351\r\nEND:VCALENDAR\r\n' >bad/fixE/latin1.ics
        printf 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nBEGIN:VALARM\nno colon here\n' >bad/fixE/broken.ics
        run good "$PWD/good-work" good.jsonl
        run bad "$PWD/bad-work" bad.jsonl 2>bad.err || {
          cat bad.err
          exit 1
        }
        diff -u good.jsonl bad.jsonl
        grep -qx 'calendar-export: .ics files skipped (not UTF-8 or not iCalendar): 2' bad.err
        if grep -q 'latin1\|broken' bad.err; then
          echo "a skipped file is named on stderr"
          exit 1
        fi
        # A file already exported that turns unreadable drops out.
        grep -q '"uid": "fx-alarm-single"' bad.jsonl
        printf 'BEGIN:VCALENDAR\r\nSUMMARY:caf\351\r\nEND:VCALENDAR\r\n' >bad/fixE/single.ics
        run bad "$PWD/bad-work" bad2.jsonl 2>bad2.err
        grep -q 'skipped (not UTF-8 or not iCalendar): 3$' bad2.err
        if grep -q 'fx-alarm-single' bad2.jsonl; then
          echo "a file that turned unreadable is still exported"
          exit 1
        fi
        touch $out
      '';

  # The panel's query library (quickshell/calendar/queries.js) against
  # invented events in calendar/panel/; the dates it asserts are London's.
  calendar-panel =
    pkgs.runCommand "calendar-panel-tests"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      }
      ''
        # Set here: the builder's setup sets TZ=UTC over the derivation's own.
        export TZ=Europe/London
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

  # desk-bt-agent (the pairing agent) against private D-Bus daemons, with the
  # test playing BlueZ and PipeWire's telephony service.
  bluetooth-agent =
    pkgs.runCommand "bluetooth-agent-tests"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.dbus-fast ])) ];
      }
      ''
        mkdir work
        python3 -I ${./bluetooth/test-bt-agent.py} \
          ${pkgs.lib.getExe (pkgs.callPackage ../bt-agent.nix { })} \
          ${pkgs.lib.getExe' pkgs.dbus "dbus-daemon"} "$PWD/work"
        touch $out
      '';

  # The tray menu's library (quickshell/tray/menu.js): the header's name and
  # the entries' marks, by the installed Quickshell's button-type values.
  tray-panel = pkgs.runCommand "tray-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./tray/test-tray.js} ${../user/quickshell/tray} \
      ${pkgs.quickshell}/lib/qt-6/qml/Quickshell/quickshell-core.qmltypes
    touch $out
  '';

  # The shared notification sender (quickshell/common/notify.js): names that
  # gdbus would read as GVariant syntax reach the server unchanged.
  common-panel = pkgs.runCommand "common-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./common-panel/test-common.js} ${../user/quickshell/common}
    touch $out
  '';

  # The office panel's library (quickshell/office/office.js) against invented
  # helper events, inline and from office-panel/fixtures/.
  office-panel = pkgs.runCommand "office-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./office-panel}/test-office-panel.js ${../user/quickshell/office}
    touch $out
  '';

  # The fleet panel's library (quickshell/fleet/fleet.js) against desk-fleet
  # lines hand-written in the helper's format in fleet-panel/fixtures/, and
  # inline events.
  fleet-panel = pkgs.runCommand "fleet-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./fleet-panel}/test-fleet-panel.js ${../user/quickshell/fleet}
    touch $out
  '';

  # The Tailscale panel's library (quickshell/tailscale/tailscale.js) against
  # hand-made status answers in tailscale-panel/fixtures/.
  tailscale-panel =
    pkgs.runCommand "tailscale-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node ${./tailscale-panel}/test-tailscale-panel.js ${../user/quickshell/tailscale}
        touch $out
      '';

  # The Network panel's Wi-Fi library (quickshell/network/wifi.js) against
  # invented networks in wifi-panel/fixtures/ and Quickshell's enum names;
  # those names, and Network.qml's copies, against the installed Quickshell.
  wifi-panel = pkgs.runCommand "wifi-panel-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./wifi-panel}/test-wifi-panel.js ${../user/quickshell/network} \
      ${pkgs.quickshell}/lib/qt-6/qml/Quickshell/Networking/quickshell-network.qmltypes \
      ${../user/quickshell/Network.qml}
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
  # --verify-config.
  hypr-config = pkgs.runCommand "hypr-config-tests" { } ''
    bash ${./hypr/run.sh} verify ${pkgs.lib.getExe' pkgs.hyprland "Hyprland"} \
      ${../user} ${../defaults}
    touch $out
  '';

  # theme.lua's reading of theme.json, under Lua alone (no Hyprland).
  hypr-theme = pkgs.runCommand "hypr-theme-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
    # lua5_5: the Lua the Hyprland package embeds.
    bash ${./hypr/run.sh} theme ${pkgs.lib.getExe pkgs.lua5_5} ${../user} ${../defaults}
    touch $out
  '';

  # desk-unlock (the recovery when the lock screen dies) against fake
  # hyprctl, systemctl and pkill.
  desk-unlock = pkgs.runCommand "desk-unlock-tests" { } ''
    bash ${./desk-unlock/run.sh} ${../desk-unlock.sh}
    touch $out
  '';

  # audio-output-cycle (Super+Shift+O) built against fake pw-dump, wpctl and
  # notify-send; their protocol is at the top of the test.
  audio-output-cycle =
    let
      cycle = pkgs.callPackage ../../audio-output-cycle.nix {
        pipewire = pkgs.writeShellScriptBin "pw-dump" ''
          # One non-sink node, then the sinks.
          printf '[{"id":5,"info":{"props":{"media.class":"Audio/Source","node.name":"x","node.description":"x"}}}'
          while read -r id name desc; do
            printf ',{"id":%s,"info":{"props":{"media.class":"Audio/Sink","node.name":"%s","node.description":"%s"}}}' \
              "$id" "$name" "$desc"
          done <"$FAKE/sinks"
          printf ']\n'
        '';
        wireplumber = pkgs.writeShellScriptBin "wpctl" ''
          case "$1" in
          inspect) printf 'id 1, type PipeWire:Interface:Node\n    media.class = "Audio/Sink"\n  * node.name = "%s"\n' "$(cat "$FAKE/default")" ;;
          set-default) echo "wpctl $*" >>"$FAKE/log" ;;
          *) exit 9 ;;
          esac
        '';
        libnotify = pkgs.writeShellScriptBin "notify-send" ''
          echo "notify-send $*" >>"$FAKE/log"
          echo 7
        '';
      };
    in
    pkgs.runCommand "audio-output-cycle-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
      bash ${./audio-output-cycle/run.sh} ${pkgs.lib.getExe cycle}
      touch $out
    '';

  # desk-mqtt (the office panel's helper) against a Mosquitto on loopback,
  # with the test playing Zigbee2MQTT under invented device names. Takes
  # about 45 s: it waits out the 5 s confirmation and two 10 s reconnects.
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

  # desk-fleet (the fleet panel's helper): its state model against probe
  # fixtures (fleet/fixtures, and cases built in the test), then the built
  # helper against fake ssh, comin, comin-deploy, sudo, ghostty and gh. Takes
  # about 50 s: it follows a deploy until comin has been idle for 20 s.
  fleet-helper = pkgs.runCommand "fleet-helper-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir work
    python3 -I ${./fleet/test-desk-fleet.py} \
      ${pkgs.lib.getExe (pkgs.callPackage ../desk-fleet.nix { })} \
      ${../desk-fleet.py} ${./fleet/fixtures} "$PWD/work"
    touch $out
  '';

  # desk-tokens (the token panel's helper): its pure functions, then the
  # built helper against invented transcripts in temporary trees, with the
  # clock fixed and the time zone set per case.
  tokens-helper =
    pkgs.runCommand "tokens-helper-tests"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      }
      ''
        mkdir work
        python3 -I ${./tokens/test-desk-tokens.py} \
          ${pkgs.lib.getExe (pkgs.callPackage ../desk-tokens.nix { })} \
          ${../desk-tokens.py} ${../desk-tokens-prices.json} "$PWD/work"
        touch $out
      '';

  # The token panel's library (quickshell/tokens/tokens.js) against invented
  # desk-tokens answers in tokens-panel/fixtures/; the times it asserts are
  # New York's, and some cases cross its daylight-saving change.
  tokens-panel =
    pkgs.runCommand "tokens-panel-tests"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      }
      ''
        # Set here: the builder's setup sets TZ=UTC over the derivation's own.
        export TZ=America/New_York
        node ${./tokens-panel}/test-tokens-panel.js ${../user/quickshell/tokens}
        touch $out
      '';

  # desk-weather (the weather panel's helper): its pure functions against
  # weather/fixtures/ and PNG tiles built in the test, then the helper built
  # with testing = true (requests to a local server, timers scaled) against a
  # Mosquitto on loopback and that server. Takes about a minute.
  weather-helper =
    pkgs.runCommand "weather-helper-tests"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.paho-mqtt ])) ];
      }
      ''
        mkdir work
        python3 -I ${./weather/test-desk-weather.py} \
          ${pkgs.lib.getExe (pkgs.callPackage ../desk-weather.nix { testing = true; })} \
          ${../desk-weather.py} ${pkgs.lib.getExe' pkgs.mosquitto "mosquitto"} \
          ${./weather/fixtures} "$PWD/work"
        touch $out
      '';

  # The weather panel's library (quickshell/weather/weather.js) against
  # hand-written helper lines in weather-panel/; the times it asserts are
  # London's.
  weather-panel =
    pkgs.runCommand "weather-panel-tests"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      }
      ''
        # Set here: the builder's setup sets TZ=UTC over the derivation's own.
        export TZ=Europe/London
        node ${./weather-panel}/test-weather-panel.js ${../user/quickshell/weather/weather.js}
        touch $out
      '';

  # The weather drawings' geometry (quickshell/weather/paths.js): the radar
  # map's projection and the sky scene's layout for a seed.
  weather-art = pkgs.runCommand "weather-art-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${./weather-art}/test-weather-art.js ${../user/quickshell/weather/paths.js}
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

  quickshell-lint = import ./quickshell-lint { inherit pkgs; };
})
