pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The applications a launcher lists, and searching them.
Singleton {
    id: root

    // Quickshell's DesktopEntries already leaves out Hidden and NoDisplay
    // entries, but not ones that OnlyShowIn/NotShowIn keep out of this
    // desktop, and it does not expose those keys.
    readonly property var entries: DesktopEntries.applications.values.filter(e => shown(e.id)).sort((a, b) => a.name.localeCompare(b.name))

    readonly property list<string> desktops: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").split(":")
    // The order Quickshell searches, highest priority first.
    readonly property list<string> dirs: [(Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/applications"].concat((Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":").filter(d => d).map(d => d + "/applications"))
    // Desktop file id -> { only: [...], not: [...] }, from the file that wins
    // for that id.
    property var showIn: ({})

    // https://specifications.freedesktop.org/menu-spec/latest/category-registry.html#main-category-registry
    readonly property list<string> mainCategories: ["AudioVideo", "Audio", "Video", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]

    function shown(id) {
        const rule = showIn[id];
        if (!rule)
            return true;
        if (rule.only.length > 0 && !rule.only.some(d => desktops.includes(d)))
            return false;
        return !rule.not.some(d => desktops.includes(d));
    }

    function mainCategory(entry) {
        return entry.categories.find(c => mainCategories.includes(c)) ?? "";
    }

    // Case-insensitive on the name: prefix matches, then substring matches
    // (earlier first), then subsequence matches; alphabetical within each.
    function search(query) {
        const q = query.trim().toLowerCase();
        if (q === "")
            return entries;
        const ranked = [];
        for (const entry of entries) {
            const name = entry.name.toLowerCase();
            const at = name.indexOf(q);
            let rank = at;
            if (at < 0) {
                let i = 0;
                for (const ch of name)
                    if (ch === q[i])
                        i++;
                if (i < q.length)
                    continue;
                rank = Number.MAX_SAFE_INTEGER;
            }
            ranked.push({ rank, entry });
        }
        return ranked.sort((a, b) => a.rank - b.rank || a.entry.name.localeCompare(b.entry.name)).map(r => r.entry);
    }

    function parseShowIn(text) {
        const result = {};
        const owner = {};
        for (const line of text.split("\n")) {
            const m = line.match(/^(.*\.desktop):(Type|OnlyShowIn|NotShowIn)=(.*)$/);
            if (!m)
                continue;
            const dir = dirs.find(d => m[1].startsWith(d + "/"));
            if (!dir)
                continue;
            const id = m[1].slice(dir.length + 1, -".desktop".length).replace(/\//g, "-");
            // The first directory to have an id owns it; later ones are
            // shadowed, as in Quickshell's own lookup.
            if (owner[id] === undefined)
                owner[id] = dir;
            if (owner[id] !== dir || m[2] === "Type")
                continue;
            if (!result[id])
                result[id] = { only: [], not: [] };
            result[id][m[2] === "OnlyShowIn" ? "only" : "not"] = m[3].split(";").filter(d => d);
        }
        return result;
    }

    function rescan() {
        if (scan.running)
            scan.again = true;
        else
            scan.running = true;
    }

    Process {
        id: scan

        property bool again: false

        // Type= is on every application entry, so it marks which file owns an
        // id even when that file has no OnlyShowIn/NotShowIn of its own.
        command: ["grep", "-RsE", "^(Type|OnlyShowIn|NotShowIn)="].concat(root.dirs)
        stdout: StdioCollector {
            onStreamFinished: root.showIn = root.parseShowIn(text)
        }
        onExited: {
            if (again) {
                again = false;
                running = true;
            }
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.rescan();
        }
    }

    Component.onCompleted: rescan()
}
