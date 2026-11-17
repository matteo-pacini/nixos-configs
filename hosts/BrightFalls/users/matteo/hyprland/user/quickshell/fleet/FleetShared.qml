pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "fleet.js" as F

// What Bar.qml and Fleet.qml share: where the panel is open, and the fleet as
// `desk-fleet` reports it (desk-fleet.py in nixos-configs describes the
// protocol). The helper runs for as long as the shell does, probing every 5
// minutes while the panel is closed so the bar's number stays true, and is
// started again if it exits; `fleet` is fleet.js's state, rebuilt from its
// events.
Singleton {
    id: root

    // Starts the helper with --read-only: it then refuses switch, boot, mode
    // and reboot (they run nothing); probes, diff, ssh and attach work as
    // usual.
    readonly property bool readOnly: false

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    property var fleet: F.initial("starting")
    property int nextId: 1
    // Whether the current process attempt really started.
    property bool started: false

    // Asks Fleet.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
    // Something the footer should say for a moment.
    signal said(string text)
    // Asks Fleet.qml to close the panel, so a window the helper opened gets
    // the keyboard.
    signal closeRequested

    // Writes one command to the helper; `cmd` is a fleet.js command object.
    // Returns false when the helper is not running.
    function send(cmd: var): bool {
        if (!proc.running)
            return false;
        const id = nextId++;
        const line = Object.assign({
            id
        }, cmd);
        console.info("fleet helper: send", JSON.stringify(line));
        proc.write(JSON.stringify(line) + "\n");
        return true;
    }

    // Tells the helper whether the panel is shown, which sets how often it
    // probes.
    function shown(open: bool): void {
        if (proc.running)
            proc.write(JSON.stringify({
                cmd: open ? "open" : "closed"
            }) + "\n");
    }

    // One line from the helper.
    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            console.warn("fleet helper:", line);
            return;
        }
        fleet = F.apply(fleet, ev);
        const text = F.footer(ev);
        if (text !== "")
            said(text);
        if (F.closesPanel(ev))
            closeRequested();
        if (ev.event === "hello" && screen !== "")
            shown(true);
        if (ev.event === "action" && ev.state !== "running")
            console.info("fleet helper: action", ev.id, ev.host ?? "", ev.action ?? "", ev.state, ev.reason ?? "", ev.exit ?? "");
        else if (ev.event === "github" && ev.state !== "ok")
            console.info("fleet helper: github", ev.error);
        else if (ev.event === "bad-input")
            console.warn("fleet helper: bad input", ev.line);
    }

    onScreenChanged: shown(screen !== "")

    Process {
        id: proc

        command: root.readOnly ? ["desk-fleet", "--read-only"] : ["desk-fleet"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("fleet helper:", line)
        }
        onStarted: {
            root.started = true;
            root.fleet = F.initial("running");
        }
        onExited: code => console.warn("fleet helper exited with", code)
        // Without `started` first, the binary could not be run.
        onRunningChanged: {
            if (running)
                return;
            root.fleet = F.initial(root.started ? "stopped" : "missing");
            root.started = false;
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing; back to 2 s once
    // the helper has said hello.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }

    onFleetChanged: if (fleet.hello)
        restart.interval = 2000
}
