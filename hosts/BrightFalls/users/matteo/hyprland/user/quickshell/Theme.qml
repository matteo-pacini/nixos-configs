pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop palette: ~/.config/desk/theme.json over the built-in Dracula
// values, re-read when the file changes. A missing or unparsable file, a
// missing key, or a value of the wrong form gives the built-in value for that
// key, the same rule as ~/.local/share/desk/hypr/theme.lua.
Singleton {
    id: root

    readonly property var builtin: ({
            background: "#282a36",
            current_line: "#44475a",
            foreground: "#f8f8f2",
            comment: "#6272a4",
            cyan: "#8be9fd",
            green: "#50fa7b",
            orange: "#ffb86c",
            pink: "#ff79c6",
            purple: "#bd93f9",
            red: "#ff5555",
            yellow: "#f1fa8c",
            font_ui: "Fira Sans",
            font_mono: "FiraCode Nerd Font"
        })
    property var file: ({})

    readonly property color background: pick("background")
    readonly property color currentLine: pick("current_line")
    readonly property color foreground: pick("foreground")
    readonly property color comment: pick("comment")
    readonly property color cyan: pick("cyan")
    readonly property color green: pick("green")
    readonly property color orange: pick("orange")
    readonly property color pink: pick("pink")
    readonly property color purple: pick("purple")
    readonly property color red: pick("red")
    readonly property color yellow: pick("yellow")
    readonly property string fontUi: pick("font_ui")
    readonly property string fontMono: pick("font_mono")

    function pick(key) {
        const value = file[key];
        if (typeof value !== "string")
            return builtin[key];
        // Six digits only: QML reads eight as #aarrggbb, Hyprland as
        // rrggbbaa, so an alpha would mean different things to each.
        const valid = key.startsWith("font_") ? /\S/.test(value) : /^#[0-9a-fA-F]{6}$/.test(value);
        return valid ? value : builtin[key];
    }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/desk/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.file = parsed !== null && typeof parsed === "object" ? parsed : {};
            } catch (e) {
                console.warn("theme.json:", e.message, "- using the built-in palette");
                root.file = {};
            }
        }
        onLoadFailed: root.file = {}
    }
}
