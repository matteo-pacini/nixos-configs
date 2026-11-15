pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "queries.js" as Q

// What Bar.qml and Calendar.qml share: where the panel is open, the bar's
// clock on each monitor, and the calendar export, loaded once and kept in
// memory for the bar's next-event hint and the panel's month and day list.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    // Monitor name -> { icon, window }: the bar's clock on that monitor and
    // the PanelWindow it is in.
    property var icons: ({})

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

    function register(screen: string, icon: Item, window: PanelWindow): void {
        icons[screen] = {
            icon,
            window
        };
    }

    // Horizontal centre of the clock on `screen`, in that monitor's
    // coordinates, or -1 when no bar has registered one.
    function iconCentre(screen: string): real {
        const entry = icons[screen];
        if (!entry || !entry.icon || !entry.window)
            return -1;
        return entry.icon.mapToItem(null, entry.icon.width / 2, 0).x + entry.window.margins.left;
    }

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
