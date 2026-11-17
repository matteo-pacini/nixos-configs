pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "tailscale.js" as T

// What Bar.qml and Tailscale.qml share: where the panel is open, the last
// answer of `tailscale status --json` as tailscale.js reads it, and the mesh
// hosts. While the panel is closed a light call (`--peers=false`) runs at
// start and every 30 s for the bar; while it is open a full call runs on
// open, every 5 s and on refresh(). Only one call runs at a time; a call
// still running after 10 s is stopped.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    readonly property bool open: screen !== ""
    // tailscale.js's answer; holds everything the panel and bar draw.
    property var answer: T.initial()
    // The parsed ~/.local/share/desk/tailscale/hosts.json, or null while it
    // is missing or does not parse.
    property var mesh: null

    // Whether the running call is the light one.
    property bool light: false
    property bool timedOut: false
    property bool exitSeen: false
    // A full call asked for (open, refresh) while another call ran; it
    // runs as soon as that one ends.
    property bool fullWanted: false

    // Asks Tailscale.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)

    // Starts a full call now, unless one is running (then right after it).
    function refresh(): void {
        poll(false);
    }

    function poll(light: bool): void {
        if (proc.running) {
            if (!light)
                fullWanted = true;
            return;
        }
        fullWanted = false;
        root.light = light;
        timedOut = false;
        exitSeen = false;
        proc.command = light ? ["tailscale", "status", "--json", "--peers=false"] : ["tailscale", "status", "--json"];
        proc.running = true;
        watchdog.restart();
    }

    function finish(exit: int, stdout: string, stderr: string): void {
        watchdog.stop();
        kill.stop();
        const before = answer.state;
        answer = T.read({
            stdout,
            exit,
            stderr,
            timedOut: root.timedOut,
            light: root.light
        }, answer, Date.now());
        if (answer.state !== before && answer.state >= 2 && answer.state <= 5)
            console.info("tailscale: status call gave state", answer.state, "exit", answer.exit, answer.stderr);
        if (fullWanted && open)
            Qt.callLater(() => poll(false));
    }

    onOpenChanged: {
        if (open) {
            meshFile.reload();
            poll(false);
        }
    }

    Component.onCompleted: poll(true)

    Process {
        id: proc

        stdout: StdioCollector {
            id: out
        }
        stderr: StdioCollector {
            id: err
        }
        // The collectors have their whole stream by the time this runs.
        onExited: code => {
            root.exitSeen = true;
            root.finish(code, out.text, err.text);
        }
        // Without an exit, the command could not be started at all.
        onRunningChanged: {
            if (!running && !root.exitSeen)
                root.finish(127, "", "could not start tailscale");
        }
    }

    // Process sends SIGTERM when `running` goes false; SIGKILL follows if
    // that is not enough.
    Timer {
        id: watchdog

        interval: 10000
        onTriggered: {
            if (!proc.running)
                return;
            console.info("tailscale: status call still running after 10 s; stopping it");
            root.timedOut = true;
            proc.running = false;
            kill.restart();
        }
    }

    Timer {
        id: kill

        interval: 2000
        onTriggered: if (proc.running)
            proc.signal(9)
    }

    Timer {
        interval: 30000
        running: !root.open
        repeat: true
        onTriggered: root.poll(true)
    }

    Timer {
        interval: 5000
        running: root.open
        repeat: true
        onTriggered: if (!proc.running)
            root.poll(false)
    }

    FileView {
        id: meshFile

        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/tailscale/hosts.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                root.mesh = JSON.parse(text());
            } catch (e) {
                console.warn("tailscale: hosts.json:", e.message);
                root.mesh = null;
            }
        }
        onLoadFailed: root.mesh = null
    }
}
