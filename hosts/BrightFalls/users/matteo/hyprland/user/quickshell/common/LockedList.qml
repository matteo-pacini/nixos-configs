import QtQuick
import Quickshell
import Quickshell.Io

// The settings Nix fixes for one panel's area, from
// ~/.local/share/desk/<area>/locked.json, which desktop-hyprland.nix
// generates: an array of rows, each with at least a `label` and the `file`
// that sets it. Read when created and on reload().
FileView {
    id: root

    // "network", "audio", "bluetooth"…: the directory under desk/.
    required property string area
    // The rows that have a label; [] while there is no readable file.
    property var entries: []
    // False while the file is missing or does not parse.
    property bool present: false

    path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/" + area + "/locked.json"
    printErrors: false
    blockLoading: true
    onLoaded: {
        try {
            const parsed = JSON.parse(text());
            entries = Array.isArray(parsed) ? parsed.filter(r => typeof r.label === "string") : [];
            present = true;
        } catch (e) {
            console.warn(area + ": locked.json:", e.message);
            entries = [];
            present = false;
        }
    }
    onLoadFailed: {
        entries = [];
        present = false;
    }
}
