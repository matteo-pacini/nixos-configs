// desk-nest's root: any subset of shell.qml's components, from one panel to
// the whole shell. desk-nest copies it to the root of its copy of
// user/quickshell and runs it as its own config (`qs -p <copy>/dev.qml`), so
// `qs.*` imports resolve as they do for shell.qml; a lowercase name keeps it
// out of the synthesised qmldir.
//
// Which components load comes from $NEST_STATE/harness.json:
//   {"components": ["Bar", "Weather", ...]}
// Missing, unreadable or without a list: every component in `safe`. The
// file is watched; a change loads and unloads components in place, without
// a reload. A singleton stays once something has used it, so a helper it
// runs (desk-weather, desk-mqtt, desk-fleet) keeps running after its panel
// is unloaded, until the next reload.

// Read at startup only, as in shell.qml.
//@ pragma IconTheme Adwaita

import QtQuick
import Quickshell
import Quickshell.Io
import qs.calendar
import qs.tray

ShellRoot {
    id: root

    // desk-nest reloads over IPC after it syncs a save into the copy, so a
    // .js counts like a .qml and a save reloads once.
    settings.watchFiles: false

    // shell.qml's components, in its order; the nest-commands check holds
    // this list to it.
    readonly property list<string> all: ["Launcher", "Bar", "Notifications", "Osd", "Cheatsheet", "SessionMenu", "Polkit", "Network", "Audio", "Calendar", "CalendarFull", "System", "BluetoothPanel", "Office", "Fleet", "Tailscale", "Tokens", "Weather", "TrayMenu", "Reminders", "Lockscreen"]
    // All but System, which reads the machine's own sensors (sysfs and
    // procfs, absolute paths); the bar still reads its temperatures.
    readonly property list<string> safe: all.filter(n => n !== "System")
    // Empty until harness.json is read, so nothing starts a helper only to
    // be unloaded a moment later.
    property var chosen: []

    function want(name: string): bool {
        return chosen.includes(name);
    }

    // The same target and answer as shell.qml's.
    IpcHandler {
        target: "shell"

        function reload(): string {
            Quickshell.reload(false);
            return "reloaded";
        }
    }

    IpcHandler {
        target: "harness"

        function components(): string {
            return root.chosen.join(" ");
        }
    }

    FileView {
        path: (Quickshell.env("NEST_STATE") || "/nonexistent") + "/harness.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let list = null;
            try {
                list = JSON.parse(text()).components;
            } catch (e) {
                console.warn("harness.json:", e.message);
            }
            if (!Array.isArray(list)) {
                root.chosen = root.safe;
            } else {
                const unknown = list.filter(n => !root.all.includes(n));
                if (unknown.length > 0)
                    console.warn("harness: no such component:", unknown.join(" "));
                root.chosen = list.filter(n => root.all.includes(n));
            }
            console.info("harness: components", root.chosen.join(" "));
        }
        onLoadFailed: {
            root.chosen = root.safe;
            console.info("harness: components", root.chosen.join(" "));
        }
    }

    LazyLoader {
        active: root.want("Launcher")
        Launcher {}
    }
    LazyLoader {
        active: root.want("Bar")
        Bar {}
    }
    LazyLoader {
        active: root.want("Notifications")
        Notifications {}
    }
    LazyLoader {
        active: root.want("Osd")
        Osd {}
    }
    LazyLoader {
        active: root.want("Cheatsheet")
        Cheatsheet {}
    }
    LazyLoader {
        active: root.want("SessionMenu")
        SessionMenu {}
    }
    LazyLoader {
        active: root.want("Polkit")
        Polkit {}
    }
    LazyLoader {
        active: root.want("Network")
        Network {}
    }
    LazyLoader {
        active: root.want("Audio")
        Audio {}
    }
    LazyLoader {
        active: root.want("Calendar")
        Calendar {}
    }
    LazyLoader {
        active: root.want("CalendarFull")
        CalendarFull {}
    }
    LazyLoader {
        active: root.want("System")
        System {}
    }
    LazyLoader {
        active: root.want("BluetoothPanel")
        BluetoothPanel {}
    }
    LazyLoader {
        active: root.want("Office")
        Office {}
    }
    LazyLoader {
        active: root.want("Fleet")
        Fleet {}
    }
    LazyLoader {
        active: root.want("Tailscale")
        Tailscale {}
    }
    LazyLoader {
        active: root.want("Tokens")
        Tokens {}
    }
    LazyLoader {
        active: root.want("Weather")
        Weather {}
    }
    LazyLoader {
        active: root.want("TrayMenu")
        TrayMenu {}
    }
    LazyLoader {
        active: root.want("Reminders")
        Reminders {}
    }
    LazyLoader {
        active: root.want("Lockscreen")
        Lockscreen {}
    }
}
