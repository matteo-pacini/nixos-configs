pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "weather.js" as W

// What Bar.qml and Weather.qml share: where the panel is open, the weather
// as weather.js keeps it from `desk-weather` (desk-weather.py in
// nixos-configs describes the protocol), the open panel's ui, and the coast
// outline for the radar map.
//
// The helper runs for as long as the shell does, since the bar shows its
// temperature, and is started again if it exits. While the panel is closed
// only the helper and a minute tick run (the bar's ages and warnings depend
// on the time); the second tick runs only while the panel is open.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    readonly property bool open: screen !== ""

    // weather.js's state, and the open panel's ui (null while closed).
    property var st: W.initial()
    property var ui: null
    // Unix seconds, as weather.js takes it.
    property real now: Date.now() / 1000

    // The generated coast file's rings, [] until it loads.
    property var coast: []

    readonly property string configPath: "/run/agenix/brightfalls/weather"
    readonly property string coastPath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/weather/coast.json"

    // The current helper process has started.
    property bool started: false

    // Asks Weather.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)

    // Writes one command to the helper; dropped while it is not running.
    function send(cmd: var): void {
        if (proc.running)
            proc.write(JSON.stringify(cmd) + "\n");
    }

    // A key name from W.KEY_NAMES pressed in the open panel. Returns the
    // effect's kind for Weather.qml, which performs "close".
    function key(name: string, repeat: bool): string {
        if (!ui)
            return "none";
        const r = W.key(ui, st, name, repeat);
        ui = r.ui;
        const e = r.effect;
        if (e.kind === "refresh")
            send({
                cmd: "refresh"
            });
        else if (e.kind === "radarOn")
            send({
                cmd: "radar",
                on: true
            });
        else if (e.kind === "radarOff")
            send({
                cmd: "radar",
                on: false
            });
        else if (e.kind === "openLink" && e.url !== "")
            Quickshell.execDetached(["uwsm", "app", "--", "xdg-open", e.url]);
        return e.kind;
    }

    function tick(): void {
        now = Date.now() / 1000;
        if (ui)
            ui = W.tick(ui, st, now).ui;
    }

    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            console.warn("weather helper:", line);
            return;
        }
        now = Date.now() / 1000;
        st = W.apply(st, ev, now);
        if (W.healthy(ev))
            restart.interval = 2000;
        if (ev && ev.event === "config" && ev.state !== "ok")
            console.warn("weather helper: config", ev.state, ev.key ?? "");
    }

    // However the panel closes (Esc, a click outside, another panel), the
    // radar stops with it.
    onOpenChanged: {
        now = Date.now() / 1000;
        if (open) {
            ui = W.initialUi(now);
        } else {
            if (ui && ui.page === "radar")
                send({
                    cmd: "radar",
                    on: false
                });
            ui = null;
        }
    }

    Process {
        id: proc

        command: ["desk-weather", "--config", root.configPath]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("weather helper:", line)
        }
        onStarted: {
            root.started = true;
            if (root.st.helper !== "running") {
                root.st = W.helperLost(root.st, "back", 0);
                console.info("weather helper: running again");
            }
            // A helper started again while the radar page is open.
            if (root.ui && root.ui.page === "radar")
                root.send({
                    cmd: "radar",
                    on: true
                });
        }
        onExited: code => console.warn("weather helper exited with", code)
        // Without `started` first, the binary could not be run.
        onRunningChanged: {
            if (running)
                return;
            const why = root.started ? "stopped" : "missing";
            root.started = false;
            root.st = W.helperLost(root.st, why, restart.interval / 1000);
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing; back to 2 s once
    // the helper has written a line weather.js counts as healthy.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }

    // While open: the panel's clock, the footer's expiry and the radar loop
    // (whose frames step every 0.5 s).
    Timer {
        interval: root.ui && root.ui.playing ? 250 : 1000
        running: root.open
        repeat: true
        onTriggered: root.tick()
    }

    // Always: the bar's view changes with the time alone (a sensor going
    // silent, a warning coming into force).
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.tick()
    }

    FileView {
        path: root.coastPath
        printErrors: false
        onLoaded: {
            try {
                const rings = JSON.parse(text());
                root.coast = Array.isArray(rings) ? rings : [];
            } catch (e) {
                console.warn("weather coast:", e.message);
                root.coast = [];
            }
        }
        onLoadFailed: root.coast = []
    }
}
