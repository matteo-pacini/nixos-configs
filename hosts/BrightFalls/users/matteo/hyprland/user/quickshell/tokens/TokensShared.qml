pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "tokens.js" as T

// What Bar.qml and Tokens.qml share: where the panel is open, the plan-limits
// reading, and the panel's state as tokens.js keeps it from `desk-tokens`
// (desk-tokens.py in nixos-configs describes the protocol).
//
// The helper runs only while the panel is open: started on open, stopped
// with SIGTERM on close, started again with a back-off if it exits while the
// panel is open. While the panel is closed only two things run: the watch on
// the limits file, and a minute tick while a reading exists (its staleness
// and its reset depend on the time).
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    readonly property bool open: screen !== ""

    // tokens.js's panel state.
    property var st: T.initial()

    // The limits file's text, "" while it is missing or unreadable.
    property string limitsText: ""
    // Epoch seconds, for the limits reading only.
    property real now: Date.now() / 1000
    readonly property var limits: T.limits(limitsText, now)

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string limitsPath: runtimeDir !== "" ? runtimeDir + "/desk/claude-limits.json" : ""

    // The current helper process has started; until then requests wait in
    // `pending`.
    property bool alive: false
    // A stop asked for by close() is under way; its exit is not a failure.
    property bool stopping: false
    property bool started: false
    property var pending: []

    // Asks Tokens.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)

    // A key name from T.KEY_NAMES pressed in the open panel. Returns whether
    // the panel used it.
    function key(name: string): bool {
        const r = T.key(st, name);
        run(r);
        return r.handled;
    }

    // Keeps a tokens.js result's state and performs its effects in order.
    function run(r: var): void {
        st = r.state;
        for (const e of r.effects) {
            if (e.do === "send")
                send(JSON.stringify(e.req) + "\n");
            else if (e.do === "close")
                screen = "";
        }
    }

    function send(line: string): void {
        if (alive)
            proc.write(line);
        else
            pending = pending.concat([line]);
    }

    function stop(): void {
        restart.stop();
        restart.interval = 2000;
        alive = false;
        pending = [];
        if (proc.running) {
            stopping = true;
            proc.running = false;
        }
    }

    onOpenChanged: {
        if (open) {
            now = Date.now() / 1000;
            run(T.opened(st));
            proc.running = true;
        } else {
            stop();
            st = T.closed(st);
        }
    }

    Process {
        id: proc

        command: ["desk-tokens"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                restart.interval = 2000;
                root.run(T.event(root.st, line));
            }
        }
        onStarted: {
            root.started = true;
            root.alive = true;
            const lines = root.pending;
            root.pending = [];
            for (const l of lines)
                proc.write(l);
            root.run(T.helper(root.st, "running"));
            console.info("tokens helper: running");
        }
        // Without `started` first, the binary could not be run.
        onRunningChanged: {
            if (running)
                return;
            const was = root.started;
            root.started = false;
            root.alive = false;
            // A panel reopened during the stop has its requests waiting for
            // the next process.
            if (root.stopping) {
                root.stopping = false;
                return;
            }
            root.pending = [];
            if (!root.open)
                return;
            const status = was ? "stopped" : "missing";
            console.info("tokens helper:", status);
            root.run(T.helper(root.st, status));
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing; back to 2 s once
    // the helper has written a line.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            if (!root.open)
                return;
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.limits.reading !== null
        onTriggered: root.now = Date.now() / 1000
    }

    // The status line replaces the file by rename on each write; the watch
    // follows the path, not the inode.
    FileView {
        id: limitsFile

        path: root.limitsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.now = Date.now() / 1000;
            root.limitsText = text();
        }
        onLoadFailed: root.limitsText = ""
    }

    // FileView watches its file and that file's directory, and neither can
    // be watched before it exists. Before the first session there is no
    // directory either, so its parent is watched for it here; a reload then
    // sets up the file's watch again.
    FileView {
        path: root.limitsPath !== "" ? root.limitsPath.slice(0, root.limitsPath.lastIndexOf("/")) : ""
        preload: false
        watchChanges: root.limitsText === ""
        printErrors: false
        onFileChanged: limitsFile.reload()
    }
}
