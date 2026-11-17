import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.common
import qs.launcher

// The app launcher, on the focused monitor. Toggled over IPC:
//   qs ipc call launcher toggle
// A query starting with "=" is a calculation and one starting with ":" an
// emoji search; the prefix turns into a chip, and Backspace on an empty
// query goes back to apps.
Scope {
    id: root

    property bool open: false
    // "apps", "calc" or "emoji".
    property string mode: "apps"
    property var results: mode === "calc" ? [Calc.evaluate(input.text)] : mode === "emoji" ? Emoji.search(input.text) : Apps.search(input.text)

    onModeChanged: if (mode === "emoji")
        Emoji.load()

    readonly property int rowHeight: 42
    readonly property int rowSpacing: 2
    readonly property int rowsShown: 7
    // Last pointer position over the list, in window coordinates.
    property point pointer: Qt.point(-1, -1)

    function select(index) {
        list.currentIndex = index;
        list.positionViewAtIndex(index, ListView.Contain);
    }

    function launch(entry) {
        // uwsm app puts the app in its own systemd scope and expands the
        // entry's Exec, field codes and Terminal= itself.
        const command = ["uwsm", "app", "--", entry.id + ".desktop"];
        console.info("launch:", JSON.stringify(command));
        Quickshell.execDetached(command);
        open = false;
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
        open = false;
    }

    function activate(result) {
        if (mode === "apps")
            launch(result);
        else if (mode === "emoji")
            copy(result.char);
        else if (result.ok)
            copy(result.text);
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (!root.open) {
                // Picked once per open, so the launcher stays put if the
                // pointer crosses to another monitor while it is up.
                const name = Hyprland.focusedMonitor?.name;
                window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
                input.text = "";
                root.mode = "apps";
                root.select(0);
                root.pointer = Qt.point(-1, -1);
            }
            root.open = !root.open;
        }
    }

    PanelWindow {
        id: window

        visible: root.open
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "desk-launcher"

        onVisibleChanged: if (visible)
            input.forceActiveFocus()

        // The window covers the monitor: a click anywhere off the box closes.
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

            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.15)
            width: 640
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

                Item {
                    width: parent.width
                    height: input.implicitHeight + 24

                    Text {
                        id: prompt

                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: ">"
                        color: Theme.pink
                        font.family: Theme.fontMono
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        id: chip

                        visible: root.mode !== "apps"
                        anchors.left: prompt.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: chipText.implicitWidth + 14
                        height: chipText.implicitHeight + 2
                        radius: 4
                        color: Theme.cyan

                        Text {
                            id: chipText

                            anchors.centerIn: parent
                            text: root.mode
                            color: Theme.background
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    TextInput {
                        id: input

                        anchors.left: chip.visible ? chip.right : prompt.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.foreground
                        selectionColor: Theme.currentLine
                        selectedTextColor: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 16
                        clip: true
                        focus: true
                        cursorDelegate: Rectangle {
                            width: 1
                            color: Theme.pink
                        }

                        onTextChanged: {
                            const prefixed = { "=": "calc", ":": "emoji" }[text[0]];
                            if (root.mode === "apps" && prefixed) {
                                root.mode = prefixed;
                                text = text.slice(1);
                            }
                            root.select(0);
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const count = root.results.length;
                            // A held Esc or Enter acts once; the rest repeat.
                            if (event.isAutoRepeat && [Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Escape) {
                                root.open = false;
                            } else if (event.key === Qt.Key_Backspace && text === "" && root.mode !== "apps") {
                                root.mode = "apps";
                                root.select(0);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (count > 0)
                                    root.activate(root.results[list.currentIndex]);
                            } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                                if (count > 0)
                                    root.select((list.currentIndex + 1) % count);
                            } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                                if (count > 0)
                                    root.select((list.currentIndex + count - 1) % count);
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }

                        Text {
                            visible: input.text === ""
                            text: ({ apps: "Search apps", calc: "Type an expression", emoji: "Search emoji by name" })[root.mode]
                            color: Theme.comment
                            font: input.font
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.currentLine
                }

                Item {
                    width: parent.width
                    height: (root.results.length > 0 ? list.height : empty.implicitHeight) + 12

                    Text {
                        id: empty

                        visible: root.results.length === 0
                        x: 14
                        y: 6
                        topPadding: 8
                        bottomPadding: 8
                        text: root.mode === "emoji" ? "No emoji matches" : "No app matches"
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    ListView {
                        id: list

                        x: 6
                        y: 6
                        width: parent.width - 12
                        height: Math.min(root.results.length, root.rowsShown) * (root.rowHeight + root.rowSpacing) - root.rowSpacing
                        spacing: root.rowSpacing
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.results

                        delegate: Rectangle {
                            id: row

                            required property var modelData
                            required property int index
                            // From the row's own data, not root.mode: the mode
                            // changes a moment before the model does.
                            readonly property string mode: modelData.char !== undefined ? "emoji" : modelData.ok !== undefined ? "calc" : "apps"
                            readonly property bool hint: mode === "calc" && !modelData.ok
                            readonly property bool selected: ListView.isCurrentItem && !hint

                            width: ListView.view.width
                            height: root.rowHeight
                            radius: 6
                            color: selected ? Theme.currentLine : "transparent"

                            Item {
                                id: icon

                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28

                                IconImage {
                                    visible: row.mode === "apps"
                                    implicitSize: 28
                                    source: row.mode === "apps" ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
                                }

                                Text {
                                    visible: row.mode === "emoji"
                                    anchors.centerIn: parent
                                    text: row.mode === "emoji" ? row.modelData.char : ""
                                    font.pixelSize: 22
                                }

                                Rectangle {
                                    visible: row.mode === "calc"
                                    anchors.fill: parent
                                    radius: 7
                                    color: row.hint ? Theme.currentLine : Theme.green

                                    Text {
                                        anchors.centerIn: parent
                                        text: "="
                                        color: row.hint ? Theme.comment : Theme.background
                                        font.family: Theme.fontUi
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                readonly property bool result: row.mode === "calc" && !row.hint

                                anchors.left: icon.right
                                anchors.leftMargin: 12
                                anchors.right: meta.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.mode !== "calc" ? row.modelData.name : row.hint ? row.modelData.hint : row.modelData.text
                                elide: Text.ElideRight
                                color: row.hint ? Theme.comment : Theme.foreground
                                font.family: result ? Theme.fontMono : Theme.fontUi
                                font.pixelSize: result ? 20 : row.hint ? 14 : 15
                                font.weight: result ? Font.DemiBold : row.selected ? Font.Medium : Font.Normal
                            }

                            Text {
                                id: meta

                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.mode === "apps" ? Apps.mainCategory(row.modelData) : row.selected ? "Enter copies" : ""
                                color: row.selected ? Theme.purple : Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.activate(row.modelData)
                                // Hover selects only when the pointer itself
                                // moves: Qt also sends hover events when rows
                                // open, filter or scroll under a still pointer.
                                onPositionChanged: mouse => {
                                    const p = mapToItem(null, mouse.x, mouse.y);
                                    if (root.pointer.x >= 0 && (p.x !== root.pointer.x || p.y !== root.pointer.y))
                                        list.currentIndex = row.index;
                                    root.pointer = p;
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
                    x: 14
                    topPadding: 8
                    bottomPadding: 8
                    spacing: 14

                    Repeater {
                        model: ({
                                apps: [["Enter", "launch"], ["↑ ↓", "move"], ["Esc", "close"]],
                                calc: [["Enter", "copy result"], ["Esc", "close"]],
                                emoji: [["Enter", "copy"], ["↑ ↓", "move"], ["Esc", "close"]]
                            })[root.mode]

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
