import QtQuick
import Quickshell
import Quickshell.Io
import "queries.js" as Q

// What a calendar view does besides drawing: R's sync, O's web calendar, the
// footer's flash text and whether a sync is running. One per view (the
// drop-down and the big view); `active` is whether that view is open. Opening
// clears the flash and asks once whether the service is syncing; the poll
// runs only while open.
Scope {
    id: root

    property bool active: false

    // A message for the footer, cleared after a few seconds, or "".
    property string flash: ""
    // A sync started here is running.
    property bool syncing: false
    // The sync service is running, whoever started it.
    property bool timerSyncing: false

    // ~/.local/share/desk/calendar/source.json names the file holding the
    // CalDAV base; that address is a secret, read only when O is pressed.
    readonly property string sourcePath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/calendar/source.json"

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function sync(): void {
        if (syncing)
            return;
        syncing = true;
        syncProc.running = true;
    }

    // Opens `day` in the Nextcloud web calendar.
    function openWeb(day: date): void {
        sourceFile.reload();
        let urlFile = "";
        try {
            urlFile = JSON.parse(sourceFile.text()).url_file ?? "";
        } catch (e) {}
        if (typeof urlFile !== "string" || urlFile === "") {
            say("No calendar server is set up yet.");
            return;
        }
        webProc.day = day;
        webProc.command = ["head", "-n", "1", urlFile];
        webProc.running = true;
    }

    onActiveChanged: {
        if (!active)
            return;
        flash = "";
        activeQuery.running = true;
    }

    Timer {
        id: flashTimer

        interval: 3500
        onTriggered: root.flash = ""
    }

    // Catches syncs the service's timer starts while the view is open.
    Timer {
        interval: 3000
        running: root.active
        repeat: true
        onTriggered: activeQuery.running = true
    }

    Process {
        id: activeQuery

        command: ["systemctl", "--user", "is-active", "calendar-sync.service"]
        stdout: StdioCollector {
            onStreamFinished: root.timerSyncing = text.trim() === "activating"
        }
    }

    // A oneshot: start returns when the sync and the export have finished.
    Process {
        id: syncProc

        command: ["systemctl", "--user", "start", "calendar-sync.service"]
        onExited: code => {
            root.syncing = false;
            if (code === 5)
                root.say("Calendar sync is not installed yet.");
            else if (code !== 0)
                root.say("Sync failed: journalctl --user -u calendar-sync says why.");
        }
    }

    Process {
        id: webProc

        property date day

        // SplitParser, not StdioCollector: the address is used once and not
        // kept in a property.
        stdout: SplitParser {
            onRead: line => {
                const url = Q.webUrl(line, webProc.day);
                if (url === "")
                    root.say("The calendar server address is not a Nextcloud one.");
                else
                    Quickshell.execDetached(["uwsm", "app", "--", "xdg-open", url]);
            }
        }
        onExited: code => {
            if (code !== 0)
                root.say("The calendar server address cannot be read.");
        }
    }

    FileView {
        id: sourceFile

        path: root.sourcePath
        printErrors: false
        blockLoading: true
    }
}
