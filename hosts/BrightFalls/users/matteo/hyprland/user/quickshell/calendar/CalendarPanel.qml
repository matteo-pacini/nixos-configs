pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "queries.js" as Q

// What Bar.qml and Calendar.qml share: where the panel is open, and the
// calendar export, loaded once and kept in memory for the bar's next-event
// hint and the panel's month and day list.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""

    // Written by the calendar-sync user service after each good sync.
    readonly property string defaultPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/desk/calendar/events.jsonl"
    property string exportPath: defaultPath

    // Queries.parse's result, or null while there is no readable export.
    property var data: null
    readonly property bool present: data !== null
    readonly property date now: clock.date
    // "2 events at 11:00", or "".
    readonly property string hint: Q.hint(data, now)

    // Asks Calendar.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
    // Asks Calendar.qml to open the panel on `screen`, if closed, with
    // `day` ("YYYY-MM-DD") selected.
    signal showRequested(string screen, string day)

    function reload(): void {
        exportFile.reload();
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // The sync service replaces the file by rename; FileView watches the
    // directory too and re-adds the new file, so that reaches onFileChanged.
    FileView {
        id: exportFile

        path: root.exportPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = Q.parse(text());
            } catch (e) {
                console.warn("calendar: export:", e.message);
                root.data = null;
            }
        }
        onLoadFailed: root.data = null
    }
}
