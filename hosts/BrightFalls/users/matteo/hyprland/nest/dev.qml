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
import qs.system

ShellRoot {
    id: root

    // desk-nest reloads over IPC after it syncs a save into the copy, so a
    // .js counts like a .qml and a save reloads once.
    settings.watchFiles: false

    // shell.qml's components, in its order; the nest-commands check holds
    // this list to it.
    readonly property list<string> all: ["Launcher", "Bar", "Notifications", "Osd", "Cheatsheet", "SessionMenu", "Polkit", "Network", "Audio", "Calendar", "CalendarFull", "System", "BluetoothPanel", "Office", "Fleet", "Tailscale", "Tokens", "Weather", "TrayMenu", "Reminders", "Lockscreen"]
    // All but System, which reads the machine's own sensors (sysfs and
    // procfs, absolute paths); the bar still reads its temperatures. A
    // --demo nest (NEST_DEMO set) has an invented machine bound over those
    // paths, so all of them.
    readonly property list<string> safe: Quickshell.env("NEST_DEMO") ? all : all.filter(n => n !== "System")
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

        // What the system item and panel have read, for desk-nest up --demo
        // and record to wait on: the CPU's and the eGPU's temperatures and
        // what discovery found. Touches Sensors, so a call starts its reads.
        function sensors(): string {
            const t = Sensors.topo;
            return JSON.stringify({
                cpuTemp: Sensors.s.cpuTemp ?? null,
                egpuJunction: Sensors.s.egpuJunction ?? null,
                k10: t?.k10 ?? null,
                egpu: t?.egpu?.path ?? null,
                igpu: t?.igpu?.path ?? null
            });
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
