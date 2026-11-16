import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common

// The session menu, on the focused monitor. Toggled over IPC:
//   qs ipc call session toggle
// Reboot and Shut down act on a second activation; moving to another row
// disarms them.
Scope {
    id: root

    property bool open: false
    property int current: 0
    // Index of the row waiting for its second activation, or -1.
    property int armed: -1
    // Last pointer position over the rows, in window coordinates.
    property point pointer: Qt.point(-1, -1)

    readonly property color keyFill: Qt.tint(Theme.background, Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.45))

    // Glyphs are Font Awesome code points in the Nerd Font.
    readonly property var entries: [
        {
            label: "Lock",
            glyph: "",
            key: "L",
            enabled: true,
            command: LockState.command
        },
        {
            label: "Log out",
            glyph: "",
            key: "O",
            enabled: true,
            // As the rescue bind: UWSM stops the session's units in order.
            command: ["uwsm", "stop"]
        },
        {
            label: "Reboot",
            glyph: "",
            key: "R",
            enabled: true,
            danger: true,
            command: ["systemctl", "reboot"]
        },
        {
            label: "Shut down",
            glyph: "",
            key: "S",
            enabled: true,
            danger: true,
            command: ["systemctl", "poweroff"]
        }
    ]

    function select(index) {
        if (index !== current)
            armed = -1;
        current = index;
    }

    // Selects the next enabled row after `current` in `direction` (1 or -1),
    // wrapping.
    function step(direction) {
        let index = current;
        do {
            index = (index + direction + entries.length) % entries.length;
        } while (!entries[index].enabled);
        select(index);
    }

    function activate(index) {
        const entry = entries[index];
        if (!entry.enabled)
            return;
        select(index);
        if (entry.danger && armed !== index) {
            armed = index;
            return;
        }
        console.info("session:", JSON.stringify(entry.command));
        Quickshell.execDetached(entry.command);
        open = false;
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            if (!root.open) {
                const name = Hyprland.focusedMonitor?.name;
                window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
                root.current = root.entries.findIndex(e => e.enabled);
                root.armed = -1;
                root.pointer = Qt.point(-1, -1);
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
        WlrLayershell.namespace: "desk-session"

        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // The window is the scrim: a click anywhere off the box closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                const letter = root.entries.findIndex(e => e.key.charCodeAt(0) === event.key);
                if (event.key === Qt.Key_Escape)
                    root.open = false;
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    root.activate(root.current);
                else if (event.key === Qt.Key_Down)
                    root.step(1);
                else if (event.key === Qt.Key_Up)
                    root.step(-1);
                else if (letter >= 0 && (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier)
                    root.activate(letter);
                else
                    return;
                event.accepted = true;
            }
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
            width: 300
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

                Text {
                    leftPadding: 16
                    topPadding: 10
                    bottomPadding: 2
                    text: "SESSION"
                    color: Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: 0.88
                }

                Column {
                    x: 6
                    width: parent.width - 12
                    topPadding: 6
                    bottomPadding: 6
                    spacing: 2

                    Repeater {
                        model: root.entries

                        Rectangle {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property bool selected: root.current === index
                            readonly property bool isArmed: root.armed === index

                            width: parent.width
                            height: 40
                            radius: 6
                            color: selected ? Theme.currentLine : "transparent"

                            Text {
                                id: glyph

                                x: 10
                                width: 18
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: row.modelData.glyph
                                color: !row.modelData.enabled ? Theme.comment : !row.selected ? Theme.foreground : row.modelData.danger ? Theme.red : Theme.purple
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            Text {
                                anchors.left: glyph.right
                                anchors.leftMargin: 12
                                anchors.right: keycap.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.label + (row.isArmed ? " · press again" : "")
                                elide: Text.ElideRight
                                color: row.modelData.enabled ? Theme.foreground : Theme.comment
                                font.family: Theme.fontUi
                                font.pixelSize: 15
                            }

                            // A keycap: the border colour shows 1 px round
                            // the fill and 2 px under it.
                            Rectangle {
                                id: keycap

                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: cap.implicitWidth + 14
                                height: cap.implicitHeight + 5
                                radius: 5
                                color: Theme.currentLine
                                opacity: row.modelData.enabled ? 1 : 0.5

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
                                    text: row.modelData.key
                                    color: Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.activate(row.index)
                                // Hover selects only when the pointer itself
                                // moves, so a still pointer does not take the
                                // selection when the menu opens under it.
                                onPositionChanged: mouse => {
                                    const p = mapToItem(null, mouse.x, mouse.y);
                                    if (row.modelData.enabled && root.pointer.x >= 0 && (p.x !== root.pointer.x || p.y !== root.pointer.y))
                                        root.select(row.index);
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
                        model: [["Enter", "select"], ["Esc", "close"]]

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
