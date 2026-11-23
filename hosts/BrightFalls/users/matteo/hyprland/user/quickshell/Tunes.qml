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
// and the playing tune scrapped (or the last scrap undone) from anywhere:
//   qs ipc call tunes scrap
// Three sections: now playing, up next (the queue and the tune being
// composed) and the composer's switch and well; or the model's download, the
// genre chooser, or why there is nothing to show. The music itself is the
// desk-tunes service's and carries on with the panel closed. tunes.js
// decides everything drawn and what each key and click does; this file
// draws its views and passes keys and clicks on.
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
    readonly property var hints: JSON.parse(hintsJson).map(h => [esc(h[0]), esc(h[1])])
    readonly property string undoLine: open && TunesShared.ui ? T.undoLine(TunesShared.st, TunesShared.ui) : ""

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            play: "\u{f040a}",
            pause: "\u{f03e4}",
            next: "\u{f04ad}"
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

    // For outside text placed inside styled text.
    function esc(text: string): string {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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
            [Qt.Key_C]: "C",
            [Qt.Key_X]: "X",
            [Qt.Key_Z]: "Z",
            [Qt.Key_R]: "R"
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

        function scrap(): void {
            TunesShared.scrapPlaying();
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

                // The genre chooser: the genre selected outlined.
                Column {
                    visible: root.chooser !== null
                    width: parent.width

                    Item {
                        width: parent.width
                        height: chooserTitle.implicitHeight + 14

                        Text {
                            id: chooserTitle

                            x: 14
                            y: 14
                            text: root.chooser ? root.chooser.title : ""
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            // On the title's baseline.
                            x: parent.width - 14 - width
                            y: chooserTitle.y + chooserTitle.baselineOffset - chipText.y - chipText.baselineOffset
                            width: chipText.implicitWidth + 12
                            height: chipText.implicitHeight + 2
                            radius: 5
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.currentLine

                            Text {
                                id: chipText

                                anchors.centerIn: parent
                                text: root.chooser ? root.chooser.chip : ""
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }
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
                        height: cells.implicitHeight + 18

                        Grid {
                            id: cells

                            readonly property real cellWidth: (width - 2 * spacing) / 3

                            x: 8
                            y: 8
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
                                    border.width: 1
                                    border.color: modelData.cur ? Theme.purple : "transparent"

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
                                            color: cell.modelData.cur ? Theme.purple : Theme.comment
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

                // The player: now playing, up next, the composer.
                Column {
                    id: playerColumn

                    readonly property var now: root.player ? root.player.now : null
                    readonly property var next: root.player ? root.player.next : null
                    readonly property var composer: root.player ? root.player.composer : null

                    visible: root.player !== null
                    width: parent.width

                    Column {
                        visible: root.player !== null && root.player.strip !== null
                        width: parent.width
                        topPadding: 10

                        Strip {
                            ink: root.player && root.player.strip ? root.tone(root.player.strip.tone) : Theme.orange
                            text: root.player && root.player.strip ? root.player.strip.text : ""
                        }
                    }

                    SecHead {
                        title: "NOW PLAYING"
                        side: playerColumn.now ? playerColumn.now.head : ""
                    }

                    Text {
                        x: 14
                        width: parent.width - 28
                        topPadding: 4
                        elide: Text.ElideRight
                        text: playerColumn.now ? playerColumn.now.name : ""
                        textFormat: Text.PlainText
                        color: playerColumn.now ? root.tone(playerColumn.now.nameTone) : Theme.foreground
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
                        text: playerColumn.now ? playerColumn.now.meta : ""
                        textFormat: Text.PlainText
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    // The waveform; a click seeks to that point.
                    Item {
                        visible: playerColumn.now !== null && playerColumn.now.wave !== null
                        width: parent.width
                        height: wave.implicitHeight + 14

                        DotWave {
                            id: wave

                            x: 14
                            y: 10
                            width: implicitWidth
                            height: implicitHeight
                            cols: playerColumn.now && playerColumn.now.wave ? playerColumn.now.wave.cols : []
                            played: playerColumn.now && playerColumn.now.wave ? playerColumn.now.wave.played : 0

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => TunesShared.seek(mouse.x / width)
                            }
                        }
                    }

                    Item {
                        visible: playerColumn.now !== null && playerColumn.now.time !== null
                        x: 14
                        width: parent.width - 28
                        height: leftTime.implicitHeight

                        Text {
                            id: leftTime

                            text: playerColumn.now && playerColumn.now.time ? playerColumn.now.time.left : ""
                            color: playerColumn.now && playerColumn.now.time ? root.tone(playerColumn.now.time.leftTone) : Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }

                        Text {
                            anchors.right: parent.right
                            text: playerColumn.now && playerColumn.now.time ? playerColumn.now.time.right : ""
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    // Play or pause, next: the keys Space and N.
                    Item {
                        width: parent.width
                        height: 36 + 18

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            spacing: 18

                            Rectangle {
                                width: 36
                                height: 36
                                radius: 18
                                color: playerColumn.now && playerColumn.now.mainLit ? Theme.purple : Theme.currentLine

                                Text {
                                    anchors.centerIn: parent
                                    text: playerColumn.now && playerColumn.now.main === "pause" ? root.glyph.pause : root.glyph.play
                                    color: playerColumn.now && playerColumn.now.mainLit ? Theme.background : Theme.comment
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
                                opacity: playerColumn.now && playerColumn.now.nextLit ? 1 : 0.35
                                color: nextArea.containsMouse && playerColumn.now && playerColumn.now.nextLit ? Theme.foreground : Style.soft
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

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.currentLine
                    }

                    SecHead {
                        title: "UP NEXT"
                        side: playerColumn.next ? playerColumn.next.head : ""
                    }

                    // The queue: ready tunes, the one being composed, and
                    // the places still to fill.
                    Column {
                        x: 6
                        width: parent.width - 12
                        bottomPadding: 4
                        spacing: 2

                        Repeater {
                            model: playerColumn.next ? playerColumn.next.rows : []

                            Rectangle {
                                id: qrow

                                required property var modelData

                                width: parent.width
                                height: qbody.implicitHeight + 12
                                radius: 6
                                color: modelData.sel ? Theme.currentLine : "transparent"

                                Text {
                                    x: 8
                                    width: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: qrow.modelData.n
                                    color: root.tone(qrow.modelData.nTone)
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }

                                Column {
                                    id: qbody

                                    x: 32
                                    y: 6
                                    width: parent.width - 32 - 8 - qright.implicitWidth - (qright.implicitWidth > 0 ? 10 : 0)
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: qrow.modelData.name
                                        textFormat: Text.PlainText
                                        color: root.tone(qrow.modelData.nameTone)
                                        font.family: Theme.fontUi
                                        font.pixelSize: 14
                                        font.weight: qrow.modelData.kind === "tune" ? Font.Medium : Font.Normal
                                    }

                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        text: qrow.modelData.sub
                                        textFormat: Text.PlainText
                                        color: Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }

                                    Item {
                                        visible: qrow.modelData.bar !== null
                                        width: parent.width
                                        height: 7

                                        Rectangle {
                                            y: 4
                                            width: parent.width
                                            height: 3
                                            radius: 1.5
                                            color: Style.track

                                            Rectangle {
                                                width: qrow.modelData.bar !== null ? qrow.modelData.bar * parent.width : 0
                                                height: parent.height
                                                radius: 1.5
                                                color: Theme.cyan
                                            }
                                        }
                                    }
                                }

                                Text {
                                    id: qright

                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qrow.modelData.right
                                    color: root.tone(qrow.modelData.rightTone)
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.currentLine
                    }

                    SecHead {
                        title: "COMPOSER"
                        toggle: true
                        on: playerColumn.composer !== null && playerColumn.composer.on
                        side: playerColumn.composer ? playerColumn.composer.label : ""
                        sideColor: playerColumn.composer ? root.tone(playerColumn.composer.labelTone) : Theme.comment
                    }

                    // What the composer makes or would make, what it holds,
                    // why it waits.
                    Item {
                        width: parent.width
                        height: well.height + 14

                        Rectangle {
                            id: well

                            x: 12
                            y: 2
                            width: parent.width - 24
                            height: wellLines.implicitHeight + 14
                            radius: 6
                            color: Style.well

                            Column {
                                id: wellLines

                                x: 9
                                y: 7
                                width: parent.width - 18
                                spacing: 4

                                Repeater {
                                    model: playerColumn.composer ? playerColumn.composer.lines : []

                                    Item {
                                        id: wl

                                        required property var modelData

                                        width: parent.width
                                        height: Math.max(wlText.implicitHeight, wlRight.implicitHeight)

                                        Text {
                                            id: wlText

                                            width: parent.width - (wlRight.implicitWidth > 0 ? wlRight.implicitWidth + 8 : 0)
                                            wrapMode: Text.Wrap
                                            textFormat: Text.StyledText
                                            text: root.esc(wl.modelData.pre) + (wl.modelData.em !== "" ? `<font color="${Style.soft}"><b>${root.esc(wl.modelData.em)}</b></font>` : "") + root.esc(wl.modelData.post)
                                            color: root.tone(wl.modelData.tone)
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            id: wlRight

                                            anchors.right: parent.right
                                            text: wl.modelData.right
                                            color: root.tone(wl.modelData.rightTone)
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                KeyHints {
                    keys: root.hints
                    message: root.undoLine
                    messageColor: Theme.orange
                }
            }
        }
    }
}
