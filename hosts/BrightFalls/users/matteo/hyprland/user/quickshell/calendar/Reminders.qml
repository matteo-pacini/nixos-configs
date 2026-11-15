import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import "queries.js" as Q

// Calendar reminders and the morning digest, as desktop notifications.
// Queries.plan decides what is due, held and sent; this runs it each minute
// and whenever fullscreen ends, keeps its state in
// ~/.local/state/desk/calendar-reminders.json so reloads and reboots do not
// repeat anything, and sends the cards over D-Bus to Notifications.qml.
//
// Held while any monitor's shown workspace has a fullscreen window (mode 2:
// a game, or a video a browser or player made fullscreen). A maximised window
// does not hold.
Scope {
    id: root

    readonly property var data: CalendarPanel.data
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/desk/calendar-reminders.json"

    // Hyprland's hasfullscreen is also true for a maximised window; the
    // toplevel's mode tells the two apart.
    readonly property var fullscreenWorkspaces: Hyprland.monitors.values.map(m => m.activeWorkspace).filter(w => w !== null && w.hasFullscreen)
    readonly property bool hyprFullscreen: Hyprland.toplevels.values.some(t => fullscreenWorkspaces.includes(t.workspace) && t.lastIpcObject.fullscreen === 2)
    // The lock screen holds them the same way, until the session is unlocked.
    readonly property bool fullscreen: hyprFullscreen || LockState.held

    // Notifications not yet sent, in order; one gdbus call at a time.
    property var queue: []

    function readState(): var {
        try {
            const s = JSON.parse(stateFile.text());
            return s && typeof s === "object" ? s : {};
        } catch (e) {
            return {};
        }
    }

    function run(): void {
        if (data === null || !settle.done)
            return;
        const before = stateFile.text();
        const result = Q.plan(data, readState(), CalendarPanel.now, fullscreen, !persist.started);
        persist.started = true;
        const after = JSON.stringify(result.state);
        if (after !== before)
            stateFile.setText(after);
        if (result.send.length > 0) {
            queue = queue.concat(result.send);
            sendNext();
        }
        closeDue();
    }

    // GVariant text for a string, so gdbus never reads a title as syntax.
    function gv(s: string): string {
        return "'" + s.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\n/g, "\\n") + "'";
    }

    function cardsNow(): var {
        try {
            return JSON.parse(persist.cards);
        } catch (e) {
            return {};
        }
    }

    function sendNext(): void {
        if (sender.running || queue.length === 0)
            return;
        const note = queue[0];
        queue = queue.slice(1);
        const cards = cardsNow();
        const old = note.key === "" ? undefined : Object.keys(cards).find(id => cards[id].key === note.key);
        sender.note = note;
        // expire 0: until dismissed or closed below; the digest expires
        // like any other.
        sender.command = ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", gv("Calendar"), "uint32 " + (old ?? 0), gv("x-office-calendar"), gv(note.summary), gv(note.body), "['open', 'Open']", "{'urgency': <byte 1>}", note.closeAt ? "int32 0" : "int32 -1"];
        sender.running = true;
    }

    function closeDue(): void {
        const cards = cardsNow();
        const now = CalendarPanel.now.getTime();
        let changed = false;
        for (const id of Object.keys(cards)) {
            if (cards[id].closeAt !== null && cards[id].closeAt <= now) {
                Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.CloseNotification", "uint32 " + id]);
                delete cards[id];
                changed = true;
            }
        }
        if (changed)
            persist.cards = JSON.stringify(cards);
    }

    function forget(id: string): void {
        const cards = cardsNow();
        if (cards[id] === undefined)
            return;
        delete cards[id];
        persist.cards = JSON.stringify(cards);
    }

    onFullscreenWorkspacesChanged: if (fullscreenWorkspaces.length > 0)
        Hyprland.refreshToplevels()
    onFullscreenChanged: if (!fullscreen)
        run()
    onDataChanged: run()

    Connections {
        target: CalendarPanel

        function onNowChanged() {
            // A window that went fullscreen from maximised sends no
            // hasfullscreen change; this catches it within a minute.
            if (root.fullscreenWorkspaces.length > 0)
                Hyprland.refreshToplevels();
            root.run();
        }
    }

    // The toplevels' fullscreen modes arrive a moment after the shell
    // (re)loads; until then a fullscreen game would read as none.
    Timer {
        id: settle

        property bool done: false

        interval: 3000
        running: true
        onTriggered: {
            done = true;
            root.run();
        }
        Component.onCompleted: Hyprland.refreshToplevels()
    }

    PersistentProperties {
        id: persist

        reloadableId: "calendar-reminders"

        // False until the first run in this process: the digest goes out at
        // shell start, not at every reload.
        property bool started: false
        // Cards on screen: id -> { key, day, closeAt (ms or null) }. Ids
        // restart with the process, so they are not kept on disk.
        property string cards: "{}"
    }

    FileView {
        id: stateFile

        path: root.statePath
        blockLoading: true
        printErrors: false
    }

    Process {
        id: sender

        property var note

        stdout: StdioCollector {
            onStreamFinished: {
                const id = text.match(/uint32 (\d+)/)?.[1];
                if (id !== undefined) {
                    const cards = root.cardsNow();
                    cards[id] = {
                        key: sender.note.key,
                        day: sender.note.day,
                        closeAt: sender.note.closeAt ? sender.note.closeAt.getTime() : null
                    };
                    persist.cards = JSON.stringify(cards);
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                console.warn("calendar reminders: notify failed with", code);
            root.sendNext();
        }
    }

    // While cards are up: "Open" on one, and cards closing.
    Process {
        running: persist.cards !== "{}"
        command: ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications"]
        stdout: SplitParser {
            onRead: line => {
                const action = line.match(/\.ActionInvoked \(uint32 (\d+), '([^']*)'\)/);
                if (action && action[2] === "open") {
                    const card = root.cardsNow()[action[1]];
                    if (card)
                        CalendarPanel.showRequested(Hyprland.focusedMonitor?.name ?? "", card.day);
                }
                const closed = line.match(/\.NotificationClosed \(uint32 (\d+),/);
                if (closed)
                    root.forget(closed[1]);
            }
        }
    }
}
