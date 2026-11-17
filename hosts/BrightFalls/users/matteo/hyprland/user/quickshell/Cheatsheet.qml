import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// The keybinding cheat sheet, on the focused monitor. Toggled over IPC:
//   qs ipc call cheatsheet toggle
// Lists the running Hyprland's binds that have a description, read with
// `hyprctl -j binds` when it opens and after each config reload. The text of
// a description before the first ": " is its group, else the group is
// "Other"; binds with the same description share a row.
Scope {
    id: root

    property bool open: false
    // `hyprctl -j binds` output, parsed.
    property var binds: []
    readonly property var groups: grouped(binds)
    readonly property var shown: filtered(groups, input.text)
    readonly property int rowCount: groups.reduce((n, g) => n + g.rows.length, 0)
    readonly property int shownCount: shown.reduce((n, g) => n + g.rows.length, 0)

    readonly property int columnCount: 3
    readonly property int columnGap: 26
    readonly property int headingHeight: 19
    readonly property int rowHeight: 27
    readonly property int groupGap: 16
    readonly property color soft: Style.soft
    readonly property color keyFill: Qt.tint(Theme.background, Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.45))

    readonly property var keyNames: ({
            space: "Space",
            return: "Return",
            escape: "Esc",
            print: "Print",
            comma: ",",
            period: ".",
            tab: "Tab",
            left: "←",
            right: "→",
            up: "↑",
            down: "↓",
            xf86audioraisevolume: "Vol +",
            xf86audiolowervolume: "Vol −",
            xf86audiomute: "Mute",
            xf86audiomicmute: "Mic mute",
            // One cap for both: they run the same play-pause in
            // hypr/bindings.lua, and a fourth cap crowds out the row's text.
            xf86audioplay: "Play",
            xf86audiopause: "Play",
            xf86audionext: "Next",
            xf86audioprev: "Prev"
        })

    function modifierNames(mask) {
        return [[64, "Super"], [1, "Shift"], [4, "Ctrl"], [8, "Alt"]].filter(m => mask & m[0]).map(m => m[1]);
    }

    function keyName(bind) {
        const key = bind.key;
        if (bind.mouse && key === "mouse:272")
            return "Left drag";
        if (bind.mouse && key === "mouse:273")
            return "Right drag";
        const known = keyNames[key.toLowerCase()];
        if (known !== undefined)
            return known;
        if (key.length === 1)
            return key.toUpperCase();
        if (key === key.toUpperCase())
            return key[0] + key.slice(1).toLowerCase();
        return key.replace(/^XF86/, "");
    }

    // The keycaps of one row: shared modifiers, then the keys, with the full
    // digit row and the four arrows each shown as one run.
    function keycaps(rowBinds) {
        const mask = rowBinds[0].modmask;
        if (rowBinds.some(b => b.modmask !== mask))
            return rowBinds.map(b => modifierNames(b.modmask).concat(keyName(b)).join("+"));
        const keys = rowBinds.map(b => b.key.toLowerCase()).sort().join(" ");
        let tail;
        if (keys === "0 1 2 3 4 5 6 7 8 9")
            tail = ["1 … 0"];
        else if (keys === "down left right up")
            tail = ["← ↑ ↓ →"];
        else
            tail = rowBinds.map(keyName).filter((k, i, all) => all.indexOf(k) === i);
        return modifierNames(mask).concat(tail);
    }

    function grouped(list) {
        const groups = [];
        const rows = {};
        for (const bind of list) {
            if (!bind.has_description || bind.description === "")
                continue;
            if (rows[bind.description] === undefined) {
                const split = bind.description.indexOf(": ");
                const name = split < 0 ? "Other" : bind.description.slice(0, split);
                let group = groups.find(g => g.name === name);
                if (group === undefined) {
                    group = {
                        name: name,
                        rows: []
                    };
                    groups.push(group);
                }
                rows[bind.description] = {
                    text: split < 0 ? bind.description : bind.description.slice(split + 2),
                    binds: []
                };
                group.rows.push(rows[bind.description]);
            }
            rows[bind.description].binds.push(bind);
        }
        return groups.map(g => ({
                    name: g.name,
                    rows: g.rows.map(r => ({
                                text: r.text,
                                keys: keycaps(r.binds)
                            }))
                }));
    }

    function filtered(groups, query) {
        const q = query.trim().toLowerCase();
        if (q === "")
            return groups;
        return groups.map(g => ({
                    name: g.name,
                    rows: g.rows.filter(r => (g.name + " " + r.text + " " + r.keys.join(" ")).toLowerCase().includes(q))
                })).filter(g => g.rows.length > 0);
    }

    function groupHeight(group) {
        return headingHeight + group.rows.length * rowHeight + groupGap;
    }

    // Splits the groups, in order, into the columns with the lowest tallest
    // column; groups are never split across columns.
    function balanced(groups) {
        const heights = groups.map(groupHeight);
        const sum = (from, to) => heights.slice(from, to).reduce((a, b) => a + b, 0);
        const n = groups.length;
        let best = [0, 0];
        let bestHeight = Infinity;
        for (let i = 0; i <= n; i++) {
            for (let j = i; j <= n; j++) {
                const tallest = Math.max(sum(0, i), sum(i, j), sum(j, n));
                if (tallest < bestHeight) {
                    bestHeight = tallest;
                    best = [i, j];
                }
            }
        }
        return [groups.slice(0, best[0]), groups.slice(best[0], best[1]), groups.slice(best[1])];
    }

    Process {
        id: query

        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.binds = JSON.parse(text);
                } catch (e) {
                    console.warn("cheatsheet: hyprctl binds:", e.message);
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded")
                query.running = true;
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            if (!root.open) {
                const name = Hyprland.focusedMonitor?.name;
                window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
                input.text = "";
                query.running = true;
            }
            root.open = !root.open;
        }
    }

    PanelWindow {
        id: window

        visible: root.open
        color: Style.scrim
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "desk-cheatsheet"

        onVisibleChanged: if (visible)
            input.forceActiveFocus()

        // The window is the scrim: a click anywhere off the box closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        RectangularShadow {
            anchors.fill: box
            radius: box.radius
            offset.y: 18
            blur: 50
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Rectangle {
            id: box

            anchors.centerIn: parent
            width: Math.min(980, parent.width - 28)
            height: column.implicitHeight + 2
            radius: Style.radius
            color: Style.surface
            border.width: 1
            border.color: Theme.purple

            // Keeps clicks on the box from reaching the close area behind it.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                x: 1
                y: 1
                width: parent.width - 2

                Row {
                    id: title

                    x: 16
                    topPadding: 12
                    spacing: 12

                    Text {
                        id: heading

                        text: "Keybindings"
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.baseline: heading.baseline
                        text: "from the running Hyprland config"
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                Item {
                    id: fieldArea

                    width: parent.width
                    height: field.height + 10

                    Rectangle {
                        id: field

                        x: 12
                        y: 10
                        width: parent.width - 24
                        height: input.implicitHeight + 16
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.currentLine

                        Text {
                            id: prompt

                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: ">"
                            color: Theme.pink
                            font.family: Theme.fontMono
                            font.pixelSize: 15
                            font.weight: Font.Medium
                        }

                        TextInput {
                            id: input

                            anchors.left: prompt.right
                            anchors.leftMargin: 10
                            anchors.right: count.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.foreground
                            selectionColor: Theme.currentLine
                            selectedTextColor: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            clip: true
                            focus: true
                            cursorDelegate: Rectangle {
                                width: 1
                                color: Theme.pink
                            }

                            Keys.onPressed: event => {
                                if (event.key !== Qt.Key_Escape || event.isAutoRepeat)
                                    return;
                                if (input.text !== "")
                                    input.text = "";
                                else
                                    root.open = false;
                                event.accepted = true;
                            }

                            Text {
                                visible: input.text === ""
                                text: "Filter"
                                color: Theme.comment
                                font: input.font
                            }
                        }

                        Text {
                            id: count

                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.shownCount + " of " + root.rowCount
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }

                Flickable {
                    id: body

                    readonly property int columnWidth: (width - 32 - (root.columnCount - 1) * root.columnGap) / root.columnCount
                    // Room left on the monitor once the modal keeps 18 px
                    // above and below and the other rows take theirs.
                    readonly property int room: window.height - 36 - 2 - title.height - fieldArea.height - hintsArea.height

                    width: parent.width
                    height: Math.min(contentHeight, room)
                    // The last group's gap stands in for the bottom padding.
                    contentHeight: root.shownCount > 0 ? columns.height + 14 : empty.implicitHeight + 26
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: empty

                        visible: root.shownCount === 0
                        x: 16
                        y: 14
                        text: "No keybinding matches"
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Row {
                        id: columns

                        x: 16
                        y: 14
                        spacing: root.columnGap

                        Repeater {
                            model: root.balanced(root.shown)

                            Column {
                                required property var modelData

                                width: body.columnWidth

                                Repeater {
                                    model: parent.modelData

                                    Column {
                                        id: group

                                        required property var modelData

                                        width: body.columnWidth
                                        bottomPadding: root.groupGap

                                        Text {
                                            height: root.headingHeight
                                            text: group.modelData.name
                                            color: Theme.purple
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            font.letterSpacing: 0.88
                                            font.capitalization: Font.AllUppercase
                                        }

                                        Repeater {
                                            model: group.modelData.rows

                                            Item {
                                                id: row

                                                required property var modelData

                                                width: body.columnWidth
                                                height: root.rowHeight

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.right: keys.left
                                                    anchors.rightMargin: 10
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: row.modelData.text
                                                    elide: Text.ElideRight
                                                    color: root.soft
                                                    font.family: Theme.fontUi
                                                    font.pixelSize: 14
                                                }

                                                Row {
                                                    id: keys

                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 4

                                                    Repeater {
                                                        model: row.modelData.keys

                                                        // A keycap: the border colour shows 1 px
                                                        // round the fill and 2 px under it.
                                                        Rectangle {
                                                            required property string modelData

                                                            width: cap.implicitWidth + 14
                                                            height: cap.implicitHeight + 5
                                                            radius: 5
                                                            color: Theme.currentLine

                                                            Rectangle {
                                                                anchors.fill: parent
                                                                anchors.margins: 1
                                                                anchors.bottomMargin: 2
                                                                radius: 4
                                                                color: root.keyFill
                                                            }

                                                            Text {
                                                                id: cap

                                                                x: 7
                                                                y: 2
                                                                text: parent.modelData
                                                                color: Theme.foreground
                                                                font.family: Theme.fontMono
                                                                font.pixelSize: 11
                                                                font.weight: Font.Medium
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.currentLine
                }

                Row {
                    id: hintsArea

                    x: 14
                    topPadding: 8
                    bottomPadding: 8
                    spacing: 14

                    Repeater {
                        model: [["Type", "filter"], ["Esc", "close"]]

                        Row {
                            required property var modelData

                            spacing: 7

                            Text {
                                text: parent.modelData[0]
                                color: Theme.cyan
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            Text {
                                text: parent.modelData[1]
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
