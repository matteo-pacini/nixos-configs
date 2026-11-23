import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.tunes
import "tunes/tunes.js" as T

// The tunes panel, hanging under the bar's tunes item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call tunes toggle
// The genre playing, the tune with its dot waveform, the controls and the
// music model's well; or the model's download, the genre chooser, or why
// there is nothing to show. The music itself is the desk-tunes service's
// and carries on with the panel closed. tunes.js decides everything drawn
// and what each key and click does; this file draws its views and passes
// keys and clicks on.
Scope {
    id: root

    readonly property bool open: TunesShared.open
    readonly property int panelWidth: 420

    // The view as a JSON string first: a string property notifies only when
    // it changes, so the one-second tick redraws only what moved.
    readonly property string viewJson: open && TunesShared.ui ? JSON.stringify(T.view(TunesShared.st, TunesShared.ui)) : ""
    readonly property var v: viewJson !== "" ? JSON.parse(viewJson) : null
    readonly property var setup: v ? v.setup : null
    readonly property var chooser: v ? v.chooser : null
    readonly property var player: v ? v.player : null
    readonly property string hintsJson: open && TunesShared.ui ? JSON.stringify(T.hints(TunesShared.st, TunesShared.ui)) : "[]"
    readonly property var hints: JSON.parse(hintsJson)

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            play: "\u{f040a}",
            pause: "\u{f03e4}",
            next: "\u{f04ad}",
            grid: "\u{f0570}"
        })

    // tunes.js's tone names.
    function tone(name: string): color {
        switch (name) {
        case "soft":
            return Style.soft;
        case "dim":
            return Theme.comment;
        case "cyan":
            return Theme.cyan;
        case "green":
            return Theme.green;
        case "orange":
            return Theme.orange;
        case "red":
            return Theme.red;
        case "purple":
            return Theme.purple;
        default:
            return Theme.foreground;
        }
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("tunes");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        TunesShared.screen = window.screen.name;
    }

    function close(): void {
        TunesShared.screen = "";
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const always = {
            [Qt.Key_Escape]: "Esc",
            [Qt.Key_Left]: "Left",
            [Qt.Key_Right]: "Right",
            [Qt.Key_Up]: "Up",
            [Qt.Key_Down]: "Down",
            [Qt.Key_Return]: "Enter",
            [Qt.Key_Enter]: "Enter"
        };
        const letters = {
            [Qt.Key_Space]: "Space",
            [Qt.Key_N]: "N",
            [Qt.Key_G]: "G",
            [Qt.Key_U]: "U",
            [Qt.Key_R]: "R",
            [Qt.Key_C]: "C"
        };
        const name = always[event.key] ?? (plain ? letters[event.key] : undefined);
        if (name === undefined)
            return false;
        if (TunesShared.key(name, event.isAutoRepeat) === "close")
            close();
        return true;
    }

    Component.onCompleted: Dropdowns.add("tunes", TunesShared)

    Connections {
        target: TunesShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "tunes"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
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
        WlrLayershell.namespace: "desk-tunes"
        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // A click off the panel closes it, the bar's item included.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                if (root.key(event))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("tunes", TunesShared.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // The link, the download, the device: a title, a line and
                // label-value rows.
                Column {
                    visible: root.setup !== null
                    x: 14
                    width: parent.width - 28
                    topPadding: 16
                    bottomPadding: 14
                    spacing: 8

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.setup ? root.setup.title : ""
                        textFormat: Text.PlainText
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: text !== ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: root.setup ? root.setup.detail : ""
                        textFormat: Text.PlainText
                        color: Style.soft
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    Rectangle {
                        visible: root.setup !== null && root.setup.bar !== null
                        width: parent.width
                        height: 5
                        radius: 2.5
                        color: Style.track

                        Rectangle {
                            width: root.setup && root.setup.bar !== null ? Math.max(height, root.setup.bar * parent.width) : 0
                            height: parent.height
                            radius: 2.5
                            color: Theme.purple
                        }
                    }

                    Column {
                        visible: root.setup !== null && root.setup.rows.length > 0
                        width: parent.width
                        topPadding: 4
                        spacing: 2

                        Repeater {
                            model: root.setup ? root.setup.rows : []

                            Item {
                                id: row

                                required property var modelData

                                width: parent.width
                                height: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

                                Text {
                                    id: rowLabel

                                    text: row.modelData[0]
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                    lineHeight: 1.25
                                }

                                Text {
                                    id: rowValue

                                    anchors.right: parent.right
                                    width: Math.min(implicitWidth, parent.width - rowLabel.implicitWidth - 12)
                                    horizontalAlignment: Text.AlignRight
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    text: row.modelData[1]
                                    textFormat: Text.PlainText
                                    color: Style.soft
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                    lineHeight: 1.25
                                }
                            }
                        }
                    }
                }

                // The genre chooser.
                Column {
                    visible: root.chooser !== null
                    width: parent.width

                    Text {
                        x: 14
                        width: parent.width - 28
                        topPadding: 14
                        wrapMode: Text.Wrap
                        text: root.chooser ? root.chooser.title : ""
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Column {
                        visible: root.chooser !== null && root.chooser.strip !== null
                        width: parent.width
                        topPadding: 10

                        Strip {
                            ink: root.chooser && root.chooser.strip ? root.tone(root.chooser.strip.tone) : Theme.orange
                            text: root.chooser && root.chooser.strip ? root.chooser.strip.text : ""
                        }
                    }

                    Text {
                        visible: text !== ""
                        x: 14
                        width: parent.width - 28
                        topPadding: 10
                        bottomPadding: 12
                        wrapMode: Text.Wrap
                        text: root.chooser ? root.chooser.empty : ""
                        textFormat: Text.PlainText
                        color: Style.soft
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    Item {
                        visible: root.chooser !== null && root.chooser.empty === ""
                        width: parent.width
                        height: cells.implicitHeight + 14

                        Grid {
                            id: cells

                            readonly property real cellWidth: (width - 2 * spacing) / 3

                            x: 8
                            y: 4
                            width: parent.width - 16
                            columns: 3
                            spacing: 4

                            Repeater {
                                model: root.chooser ? root.chooser.cells : []

                                Rectangle {
                                    id: cell

                                    required property var modelData
                                    required property int index

                                    width: cells.cellWidth
                                    height: cellText.implicitHeight + 16
                                    radius: 6
                                    color: modelData.sel ? Theme.currentLine : cellArea.containsMouse ? Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.5) : "transparent"

                                    Column {
                                        id: cellText

                                        x: 8
                                        y: 8
                                        width: parent.width - 16
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: cell.modelData.name
                                            textFormat: Text.PlainText
                                            color: Theme.foreground
                                            font.family: Theme.fontUi
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            width: parent.width
                                            wrapMode: Text.Wrap
                                            text: cell.modelData.sub
                                            color: Theme.comment
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                        }
                                    }

                                    MouseArea {
                                        id: cellArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: TunesShared.pick(cell.index)
                                    }
                                }
                            }
                        }
                    }
                }

                // The player.
                Column {
                    visible: root.player !== null
                    width: parent.width

                    Item {
                        width: parent.width
                        height: genreText.implicitHeight + 14

                        Text {
                            id: genreText

                            x: 14
                            y: 14
                            width: parent.width - 28 - chip.width - 10
                            elide: Text.ElideRight
                            text: root.player ? root.player.genre : ""
                            textFormat: Text.PlainText
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            id: chip

                            // On the title's baseline.
                            x: parent.width - 14 - width
                            y: genreText.y + genreText.baselineOffset - chipText.y - chipText.baselineOffset
                            width: chipText.implicitWidth + 12
                            height: chipText.implicitHeight + 2
                            radius: 5
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.currentLine

                            Text {
                                id: chipText

                                anchors.centerIn: parent
                                text: root.player ? root.player.chip : ""
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }
                    }

                    Column {
                        visible: root.player !== null && root.player.strip !== null
                        width: parent.width
                        topPadding: 10

                        Strip {
                            ink: root.player && root.player.strip ? root.tone(root.player.strip.tone) : Theme.orange
                            text: root.player && root.player.strip ? root.player.strip.text : ""
                        }
                    }

                    Text {
                        x: 14
                        width: parent.width - 28
                        topPadding: 6
                        elide: Text.ElideRight
                        text: root.player ? root.player.name : ""
                        textFormat: Text.PlainText
                        color: root.player ? root.tone(root.player.nameTone) : Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }

                    Text {
                        visible: text !== ""
                        x: 14
                        width: parent.width - 28
                        topPadding: 2
                        wrapMode: Text.Wrap
                        text: root.player ? root.player.meta : ""
                        textFormat: Text.PlainText
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    // The waveform; a click seeks to that point.
                    Item {
                        visible: root.player !== null && root.player.wave !== null
                        width: parent.width
                        height: wave.implicitHeight + 16

                        DotWave {
                            id: wave

                            x: 14
                            y: 12
                            width: implicitWidth
                            height: implicitHeight
                            cols: root.player && root.player.wave ? root.player.wave.cols : []
                            played: root.player && root.player.wave ? root.player.wave.played : 0
                            forming: root.player && root.player.wave ? root.player.wave.forming : false

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.player !== null && root.player.wave !== null && !root.player.wave.forming
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: mouse => TunesShared.seek(mouse.x / width)
                            }
                        }
                    }

                    Item {
                        visible: root.player !== null && root.player.right !== null
                        x: 14
                        width: parent.width - 28
                        height: leftTime.implicitHeight

                        Text {
                            id: leftTime

                            text: root.player ? root.player.left : ""
                            color: root.player ? root.tone(root.player.leftTone) : Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.right: parent.right
                            text: root.player && root.player.right !== null ? root.player.right : ""
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    // Genres, play or pause, next: the keys G, Space and N.
                    Item {
                        width: parent.width
                        height: 36 + 22

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            spacing: 18

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.glyph.grid
                                color: gridArea.containsMouse ? Theme.foreground : Style.soft
                                font.family: Theme.fontMono
                                font.pixelSize: 18

                                MouseArea {
                                    id: gridArea

                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: TunesShared.key("G", false)
                                }
                            }

                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                color: root.player && root.player.mainLit ? Theme.purple : Theme.currentLine

                                Text {
                                    anchors.centerIn: parent
                                    text: root.player && root.player.main === "pause" ? root.glyph.pause : root.glyph.play
                                    color: root.player && root.player.mainLit ? Theme.background : Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 18
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: TunesShared.key("Space", false)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.glyph.next
                                opacity: root.player && root.player.nextLit ? 1 : 0.4
                                color: nextArea.containsMouse && root.player && root.player.nextLit ? Theme.foreground : Style.soft
                                font.family: Theme.fontMono
                                font.pixelSize: 18

                                MouseArea {
                                    id: nextArea

                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: TunesShared.key("N", false)
                                }
                            }
                        }
                    }

                    // The music model: what it is, where it runs, what it
                    // does and holds now.
                    Item {
                        width: parent.width
                        height: well.height + 12

                        Rectangle {
                            id: well

                            readonly property var w: root.player ? root.player.well : null

                            x: 12
                            width: parent.width - 24
                            height: wellText.implicitHeight + 14
                            radius: 6
                            color: Qt.darker(Theme.background, 1.15)

                            Column {
                                id: wellText

                                x: 9
                                y: 7
                                width: parent.width - 18
                                spacing: 5

                                Item {
                                    width: parent.width
                                    height: Math.max(wellName.implicitHeight, wellStatus.implicitHeight)

                                    Flow {
                                        id: wellName

                                        width: parent.width - wellStatus.implicitWidth - 8

                                        Text {
                                            text: well.w ? well.w.name : ""
                                            textFormat: Text.PlainText
                                            color: Style.soft
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            visible: well.w !== null && well.w.sub !== ""
                                            text: well.w ? " · " + well.w.sub : ""
                                            textFormat: Text.PlainText
                                            color: Theme.comment
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        id: wellStatus

                                        anchors.right: parent.right
                                        text: well.w ? well.w.status : ""
                                        color: well.w ? root.tone(well.w.statusTone) : Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: Math.max(wellLine.implicitHeight, wellRam.implicitHeight)

                                    Text {
                                        id: wellLine

                                        width: parent.width - (wellRam.implicitWidth > 0 ? wellRam.implicitWidth + 8 : 0)
                                        wrapMode: Text.Wrap
                                        text: well.w ? well.w.line : ""
                                        color: Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        id: wellRam

                                        anchors.right: parent.right
                                        text: well.w ? well.w.ram : ""
                                        color: Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }

                KeyHints {
                    keys: root.hints
                }
            }
        }
    }
}
