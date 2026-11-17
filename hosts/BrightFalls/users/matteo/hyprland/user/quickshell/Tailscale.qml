import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.tailscale
import "tailscale/tailscale.js" as T

// The Tailscale panel, hanging under the bar's Tailscale item on one
// monitor. Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call tailscale toggle
// Read-only: this computer in the well, then every peer, mesh hosts first.
// tailscale.js decides everything drawn and what each key does; this file
// draws its view and runs its commands.
Scope {
    id: root

    readonly property bool open: TailscaleShared.screen !== ""
    readonly property int panelWidth: 420

    property real now: Date.now()
    // tailscale.js's ui: selection, unfolded rows, the copy chooser.
    property var ui: T.initialUi()
    property string flash: ""

    readonly property var v: T.view(TailscaleShared.answer, TailscaleShared.mesh, now, ui)

    // The selection falls back when its peer goes; keep the fallback. Later,
    // not inside the change: ui is one of v's inputs.
    onVChanged: Qt.callLater(keepSelection)

    function keepSelection(): void {
        if (ui.selected !== v.selected)
            ui = Object.assign({}, ui, {
                selected: v.selected
            });
    }

    function tone(name: string): color {
        return name === "red" ? Theme.red : name === "orange" ? Theme.orange : name === "yellow" ? Theme.yellow : name === "green" ? Theme.green : name === "cyan" ? Theme.cyan : name === "purple" ? Theme.purple : name === "dim" ? Theme.comment : name === "fg" ? Theme.foreground : Style.soft;
    }

    // For daemon text placed inside styled text.
    function esc(text: string): string {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("tailscale");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        now = Date.now();
        ui = Object.assign({}, ui, {
            chooser: null
        });
        flash = "";
        TailscaleShared.screen = window.screen.name;
    }

    function close(): void {
        TailscaleShared.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function select(id: string): void {
        ui = Object.assign({}, ui, {
            selected: id
        });
    }

    // Runs what tailscale.js decided for a key; `repeat`: a held key's
    // auto-repeat.
    function act(name: string, repeat: bool): void {
        const d = T.decide(v, ui, name, repeat);
        ui = d.ui;
        switch (d.kind) {
        case "copy":
            Quickshell.execDetached(d.command);
            say(d.say);
            break;
        case "open":
            Quickshell.execDetached(d.command);
            break;
        case "ssh":
            // The panel holds the keyboard; the terminal needs it.
            close();
            Quickshell.execDetached(d.command);
            break;
        case "refresh":
            console.info("tailscale: refresh");
            TailscaleShared.refresh();
            break;
        case "close":
            close();
            break;
        case "say":
            say(d.text);
            break;
        }
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const k = event.key;
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const always = {
            [Qt.Key_Escape]: "Esc",
            [Qt.Key_Up]: "Up",
            [Qt.Key_Down]: "Down",
            [Qt.Key_Home]: "Home",
            [Qt.Key_End]: "End",
            [Qt.Key_Return]: "Enter",
            [Qt.Key_Enter]: "Enter",
            [Qt.Key_F5]: "F5"
        };
        const letters = {
            [Qt.Key_J]: "J",
            [Qt.Key_K]: "K",
            [Qt.Key_Y]: "Y",
            [Qt.Key_T]: "T",
            [Qt.Key_O]: "O",
            [Qt.Key_1]: "1",
            [Qt.Key_2]: "2",
            [Qt.Key_3]: "3",
            [Qt.Key_4]: "4"
        };
        const name = always[k] ?? (plain ? letters[k] : undefined);
        if (name === undefined)
            return false;
        act(name, event.isAutoRepeat);
        return true;
    }

    Timer {
        id: flashTimer

        interval: 2000
        onTriggered: root.flash = ""
    }

    // Ages ("last seen 5 min ago") count while the panel is open.
    Timer {
        interval: 1000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Component.onCompleted: Dropdowns.add("tailscale", TailscaleShared)

    Connections {
        target: TailscaleShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "tailscale"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A key hint as the rows and the chooser draw it.
    component KeyBox: Rectangle {
        id: box

        property var spec

        width: keyText.implicitWidth + 14
        height: keyText.implicitHeight + 4
        radius: 5
        color: Qt.lighter(Theme.background, 1.12)
        border.width: 1
        border.color: Theme.currentLine

        Text {
            id: keyText

            anchors.centerIn: parent
            text: `<font color="${Theme.cyan}">${box.spec.key}</font> ${box.spec.label}`
            textFormat: Text.StyledText
            color: Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: 11
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
        WlrLayershell.namespace: "desk-tailscale"
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
            centre: root.open ? Dropdowns.centre("tailscale", TailscaleShared.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2
                spacing: 6

                // The title, then the state word and "read only" or "as of";
                // those move under the title when they do not fit beside it.
                Item {
                    id: head

                    readonly property bool beside: title.implicitWidth + 10 + metaWidth.implicitWidth <= width - 28

                    width: parent.width
                    height: beside ? title.implicitHeight + 16 : title.implicitHeight + 16 + meta.implicitHeight + 2

                    Text {
                        id: title

                        x: 14
                        y: 12
                        text: "Tailscale"
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Text {
                        id: metaWidth

                        visible: false
                        text: meta.text
                        textFormat: Text.StyledText
                        font: meta.font
                    }

                    Text {
                        id: meta

                        x: head.beside ? head.width - 14 - implicitWidth : 14
                        y: head.beside ? title.y + title.baselineOffset - baselineOffset : title.y + title.implicitHeight + 2
                        width: head.beside ? implicitWidth : head.width - 28
                        text: `<font color="${root.tone(root.v.header.colour)}"><b>${root.esc(root.v.header.word)}</b></font>&nbsp;&nbsp;&nbsp;${root.esc(root.v.header.meta)}`
                        textFormat: Text.StyledText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }
                }

                Repeater {
                    model: root.v.strips

                    Strip {
                        required property var modelData

                        tone: modelData.tone
                        parts: modelData.parts
                    }
                }

                Strip {
                    visible: root.v.versionLine !== ""
                    tone: "yellow"
                    parts: [
                        {
                            text: root.v.versionLine,
                            code: false
                        }
                    ]
                }

                // This computer.
                Rectangle {
                    visible: root.v.well !== null
                    x: 12
                    width: parent.width - 24
                    height: wellFlow.implicitHeight + 12
                    radius: 6
                    color: Qt.darker(Theme.background, 1.15)

                    Flow {
                        id: wellFlow

                        x: 8
                        y: 6
                        width: parent.width - 16
                        spacing: 8

                        Repeater {
                            model: root.v.well?.parts ?? []

                            Text {
                                required property var modelData

                                width: Math.min(implicitWidth, wellFlow.width)
                                text: modelData.text
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: modelData.tone !== "" ? root.tone(modelData.tone) : modelData.bold ? Style.soft : Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                font.weight: modelData.bold ? Font.Medium : Font.Normal
                            }
                        }
                    }
                }

                Mono {
                    visible: text !== ""
                    x: 14
                    width: parent.width - 28
                    topPadding: 4
                    bottomPadding: 4
                    text: root.v.note
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: root.v.groups

                    Column {
                        id: group

                        required property var modelData

                        width: content.width
                        spacing: 3

                        Text {
                            x: 14
                            topPadding: 4
                            bottomPadding: 1
                            text: group.modelData.title
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 0.9
                        }

                        Repeater {
                            model: group.modelData.rows

                            PeerRow {
                                required property var modelData

                                x: 8
                                width: group.width - 16
                                row: modelData
                            }
                        }
                    }
                }

                KeyHints {
                    keys: root.v.hints
                    message: root.flash
                    messageColor: Theme.orange
                }
            }
        }
    }

    // A line over the list: a state, a warning, a version.
    component Strip: Rectangle {
        id: strip

        property string tone
        property var parts: []
        readonly property color ink: tone === "dim" ? Style.soft : root.tone(tone)
        readonly property color fill: root.tone(tone)

        x: 12
        width: parent ? parent.width - 24 : 0
        height: stripText.implicitHeight + 12
        radius: 6
        color: Qt.rgba(fill.r, fill.g, fill.b, tone === "dim" ? 0.16 : 0.13)

        Text {
            id: stripText

            x: 10
            y: 6
            width: parent.width - 20
            text: strip.parts.map(p => p.code ? `<font face="${Theme.fontMono}">${root.esc(p.text)}</font>` : root.esc(p.text)).join("")
            textFormat: Text.StyledText
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            color: strip.ink
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }

    // One peer. Its keys, details and the copy chooser show only while it is
    // selected or unfolded.
    component PeerRow: Rectangle {
        id: peer

        property var row
        readonly property bool choosing: root.v.chooser !== null && root.v.chooser.id === row.id

        height: column.implicitHeight + 14
        radius: 6
        color: row.selected ? Qt.lighter(Theme.background, 1.1) : "transparent"
        border.width: 1
        border.color: row.selected ? Theme.currentLine : "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: root.select(peer.row.id)
        }

        Column {
            id: column

            x: 8
            y: 7
            width: parent.width - 16
            spacing: 5

            Item {
                width: parent.width
                height: Math.max(name.implicitHeight, chip.height)

                Text {
                    id: glyph

                    width: 14
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: peer.row.glyph
                    color: peer.row.dim ? Theme.comment : Style.soft
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }

                Text {
                    id: name

                    // Only the name may elide.
                    x: 22
                    width: Math.min(implicitWidth, parent.width - 22 - chip.width - 8)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: peer.row.name
                    textFormat: Text.PlainText
                    color: peer.row.dim || peer.row.unnamed ? Theme.comment : Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                Rectangle {
                    id: chip

                    readonly property color ink: root.tone(peer.row.chip.colour)

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: chipText.implicitWidth + 14
                    height: chipText.implicitHeight + 2
                    radius: 5
                    color: Qt.rgba(ink.r, ink.g, ink.b, 0.16)

                    Text {
                        id: chipText

                        anchors.centerIn: parent
                        text: peer.row.chip.label
                        color: chip.ink
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            Mono {
                x: 22
                width: column.width - 22
                text: peer.row.line
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            // Enter: label, then value.
            Column {
                visible: peer.row.details.length > 0
                x: 22
                width: column.width - 22
                spacing: 1

                Repeater {
                    model: peer.row.details

                    Item {
                        required property var modelData

                        width: parent.width
                        height: value.implicitHeight

                        Text {
                            width: 76
                            text: parent.modelData.label
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }

                        Text {
                            id: value

                            x: 84
                            width: parent.width - 84
                            text: parent.modelData.value
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere
                            color: Style.soft
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                }
            }

            Flow {
                visible: peer.row.keys.length > 0 && !peer.choosing
                x: 22
                width: column.width - 22
                spacing: 6
                topPadding: 1

                Repeater {
                    model: peer.row.keys

                    KeyBox {
                        required property var modelData

                        spec: modelData
                    }
                }
            }

            // Y: what to copy.
            Rectangle {
                visible: peer.choosing
                x: 22
                width: column.width - 22
                height: askColumn.implicitHeight + 16
                radius: 6
                color: Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0.12)

                Column {
                    id: askColumn

                    x: 10
                    y: 8
                    width: parent.width - 20
                    spacing: 8

                    Text {
                        width: parent.width
                        text: root.v.chooser?.title ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: peer.choosing ? root.v.chooser.keys : []

                            KeyBox {
                                required property var modelData

                                spec: modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
