pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "tunes.js" as T
import "../common/notify.js" as Notify

// What Bar.qml and Tunes.qml share: where the panel is open, and the tunes
// service's state as tunes.js keeps it from `desk-tunes attach` (desk-tunes.py
// in nixos-configs describes the protocol).
//
// The music is the desk-tunes user service's, not the shell's: this file runs
// only its thin client, for as long as the shell does, since the bar shows
// what plays. The client is started again if it exits. While the panel is
// closed nothing else runs but the bar note's flash, once, after a global
// scrap; while it is open a one-second tick runs only when tunes.js says the
// panel shows something that moves with the clock.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    readonly property bool open: screen !== ""

    // tunes.js's state, and the open panel's ui (null while closed).
    property var st: T.initial()
    property var ui: null

    // The current client process has started.
    property bool started: false
    // The bar's note flashes after a global scrap.
    property bool flashing: false
    property int exitCode: -1
    property string lastStderr: ""

    // Asks Tunes.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)

    // Writes one command to the service; dropped while the client is not
    // running.
    function send(cmd: var): void {
        if (proc.running)
            proc.write(JSON.stringify(cmd) + "\n");
    }

    // Performs a tunes.js result: keeps its ui and runs its effect. Returns
    // the effect's kind for Tunes.qml, which performs "close" and leaves a
    // "pass" key to the editor's field.
    function run(r: var): string {
        ui = r.ui;
        const e = r.effect;
        if (e.kind === "send")
            send(e.cmd);
        else if (e.kind === "reattach")
            reattach();
        return e.kind;
    }

    // A key name from T.KEY_NAMES pressed in the open panel.
    function key(name: string, repeat: bool): string {
        if (!ui)
            return "none";
        return run(T.key(ui, st, name, repeat));
    }

    // The chooser's genre cell `index` clicked.
    function pick(index: int): void {
        if (ui)
            run(T.pick(ui, st, index));
    }

    // The genre editor's field `field` (one of T.FIELDS) now holds `text`.
    function typed(field: string, text: string): void {
        const u = ui ? T.typed(ui, field, text) : null;
        if (u !== ui)
            ui = u;
    }

    // The genre editor's field `field` took the keyboard.
    function focusField(field: string): void {
        const u = ui ? T.focus(ui, field) : null;
        if (u !== ui)
            ui = u;
    }

    // The waveform clicked `fraction` of the way across.
    function seek(fraction: real): void {
        const cmd = T.seek(st, fraction);
        if (cmd)
            send(cmd);
    }

    // The global scrap: an undo while one is offered or a scrap just sent is
    // unanswered, else a scrap of the playing tune and the note's flash, and
    // one notification naming the tune; nothing when there is nothing to act
    // on.
    function scrapPlaying(): void {
        const r = T.globalScrap(st, Date.now() / 1000);
        if (!r)
            return;
        st = r.st;
        send(r.cmd);
        if (r.flash) {
            flashing = true;
            flash.restart();
        }
        Quickshell.execDetached(Notify.command("Tunes", 0, "audio-x-generic", r.summary, r.body, "[]", "{}", "int32 -1"));
    }

    // R while the link is down: start the client now, back-off reset.
    function reattach(): void {
        if (proc.running)
            return;
        restart.stop();
        restart.interval = 2000;
        proc.running = true;
    }

    function tick(): void {
        if (ui)
            ui = Object.assign({}, ui, {
                now: Date.now() / 1000
            });
    }

    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            console.warn("tunes service:", line);
            return;
        }
        const now = Date.now() / 1000;
        st = T.apply(st, ev, now);
        if (ui) {
            const u = T.answer(ui, st, ev, now);
            if (u !== ui)
                ui = u;
        }
        if (T.healthy(ev))
            restart.interval = 2000;
        if (ev && ev.event === "error")
            console.warn("tunes service: error", ev.text ?? "");
    }

    onOpenChanged: {
        if (open) {
            ui = T.initialUi(st, Date.now() / 1000);
            send({
                cmd: "refresh"
            });
        } else {
            ui = null;
        }
    }

    Process {
        id: proc

        command: ["desk-tunes", "attach"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => {
                root.lastStderr = line;
                console.warn("tunes attach:", line);
            }
        }
        onStarted: {
            root.started = true;
            root.lastStderr = "";
            root.st = T.linkLost(root.st, "back");
        }
        // Quickshell emits exited before runningChanged, so the code is
        // known when the link is reported lost.
        onExited: code => {
            root.exitCode = code;
            console.warn("tunes attach exited with", code);
        }
        // Without `started` first, the binary could not be run.
        onRunningChanged: {
            if (running)
                return;
            const at = Date.now() / 1000 + restart.interval / 1000;
            if (root.started)
                root.st = T.linkLost(root.st, "exited", root.exitCode, root.lastStderr, at);
            else
                root.st = T.linkLost(root.st, "missing", null, "", at);
            root.started = false;
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing; back to 2 s once
    // the service has written a line tunes.js counts as healthy.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }

    // Runs once per global scrap, never while idle.
    Timer {
        id: flash

        interval: T.FLASH_MS
        onTriggered: root.flashing = false
    }

    Timer {
        interval: 1000
        running: root.ui !== null && T.needsTick(root.st, root.ui)
        repeat: true
        onTriggered: root.tick()
    }
}
