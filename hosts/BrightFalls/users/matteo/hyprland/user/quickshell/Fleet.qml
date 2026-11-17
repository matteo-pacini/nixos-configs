import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.fleet
import "fleet/fleet.js" as F

// The fleet panel, hanging under the bar's fleet item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call fleet toggle
// One row per host of the SSH mesh as desk-fleet reports it (FleetShared):
// what it runs, what its comin is doing, what a reboot changes, and the keys
// that apply. Every action is a key; a click only selects a row. Switch and
// reboot ask in the row first; the helper refuses anything its row no longer
// allows.
Scope {
    id: root

    readonly property bool open: FleetShared.screen !== ""
    readonly property int panelWidth: 420

    readonly property var fleet: FleetShared.fleet
    property real now: Date.now()
    // Host name of the selected row, kept across reorders.
    property string selected: ""
    // The open question: { host, what: "switch" | "reboot" | "mode" } or null.
    property var ask: null
    // Host name -> true for rows unfolded with I.
    property var unfolded: ({})
    property string flash: ""
    property int frame: 0

    readonly property string single: F.single(fleet)
    readonly property var names: F.order(fleet)
    readonly property string current: names.includes(selected) ? selected : (names[0] ?? "")
    readonly property var pipe: F.pipeline(fleet)
    readonly property string runUrl: fleet.github?.state === "ok" ? (fleet.github.run?.url ?? "") : ""
    readonly property string spinner: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[frame % 10]
    readonly property bool spinning: F.spinning(fleet)

    readonly property color soft: Style.soft

    function tone(name: string): color {
        return name === "red" ? Theme.red : name === "orange" ? Theme.orange : name === "pink" ? Theme.pink : name === "yellow" ? Theme.yellow : name === "green" ? Theme.green : name === "cyan" ? Theme.cyan : name === "purple" ? Theme.purple : name === "dim" ? Theme.comment : root.soft;
    }

    // For helper text placed inside styled text.
    function esc(text: string): string {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("fleet");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        now = Date.now();
        ask = null;
        flash = "";
        FleetShared.screen = window.screen.name;
    }

    function close(): void {
        ask = null;
        FleetShared.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function select(host: string): void {
        if (ask && ask.host !== host)
            ask = null;
        selected = host;
    }

    // Runs what fleet.js decided for a key; `repeat`: a held key's auto-repeat.
    function act(name: string, repeat: bool): void {
        const row = fleet.rows[current] ?? null;
        const d = F.decide(row, ask, name, runUrl, repeat);
        switch (d.kind) {
        case "send":
            if (!FleetShared.send(d.cmd))
                say("The fleet helper is not running.");
            if (!d.keepAsk)
                ask = null;
            break;
        case "ask":
            ask = {
                host: row.host,
                what: d.what
            };
            break;
        case "cancel":
            ask = null;
            break;
        case "close":
            close();
            break;
        case "say":
            if (d.cancel)
                ask = null;
            say(d.text);
            break;
        case "info":
            {
                const next = Object.assign({}, unfolded);
                next[row.host] = !next[row.host];
                unfolded = next;
            }
            break;
        case "open":
            Quickshell.execDetached(["uwsm", "app", "--", "xdg-open", d.url]);
            break;
        case "refresh":
            FleetShared.send({
                cmd: "refresh"
            });
            break;
        }
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const k = event.key;
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const repeat = event.isAutoRepeat;
        if (k === Qt.Key_Escape) {
            act("Esc", repeat);
            return true;
        }
        if (single !== "")
            return false;
        let nav = "";
        if (k === Qt.Key_Up || (k === Qt.Key_K && plain))
            nav = "Up";
        else if (k === Qt.Key_Down || (k === Qt.Key_J && plain))
            nav = "Down";
        else if (k === Qt.Key_Home)
            nav = "Home";
        else if (k === Qt.Key_End)
            nav = "End";
        if (nav !== "") {
            select(F.move(names, current, nav));
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            act("Enter", repeat);
            return true;
        }
        if (k === Qt.Key_F5) {
            act("F5", repeat);
            return true;
        }
        if (!plain)
            return false;
        const letters = {
            [Qt.Key_S]: "S",
            [Qt.Key_B]: "B",
            [Qt.Key_D]: "D",
            [Qt.Key_M]: "M",
            [Qt.Key_R]: "R",
            [Qt.Key_T]: "T",
            [Qt.Key_I]: "I",
            [Qt.Key_O]: "O",
            [Qt.Key_A]: "A",
            [Qt.Key_1]: "1",
            [Qt.Key_2]: "2",
            [Qt.Key_3]: "3"
        };
        if (!(k in letters))
            return false;
        act(letters[k], repeat);
        return true;
    }

    Timer {
        id: flashTimer

        interval: 2000
        onTriggered: root.flash = ""
    }

    // "checked Ns ago" counts while the panel is open.
    Timer {
        interval: 1000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Timer {
        interval: 100
        running: root.open && root.spinning
        repeat: true
        onTriggered: root.frame = (root.frame + 1) % 10
    }

    Component.onCompleted: Dropdowns.add("fleet", FleetShared)

    Connections {
        target: FleetShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
        function onSaid(text) {
            if (root.open)
                root.say(text);
        }
        function onCloseRequested() {
            if (root.open)
                root.close();
        }
    }

    IpcHandler {
        target: "fleet"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A key hint as the rows and questions draw it.
    component KeyBox: Rectangle {
        id: box

        property var spec

        width: keyText.implicitWidth + 14
        height: keyText.implicitHeight + 4
        radius: 5
        color: Qt.lighter(Theme.background, 1.12)
        border.width: 1
        border.color: spec.danger ? Theme.red : spec.hl ? Theme.purple : Theme.currentLine

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
        WlrLayershell.namespace: "desk-fleet"
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
            centre: root.open ? Dropdowns.centre("fleet", FleetShared.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // Only this when the helper cannot run.
                Text {
                    visible: root.single !== ""
                    width: parent.width
                    padding: 14
                    text: root.single
                    wrapMode: Text.Wrap
                    color: root.soft
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                Column {
                    visible: root.single === ""
                    width: parent.width
                    spacing: 8

                    Item {
                        width: parent.width
                        height: title.implicitHeight + 12

                        Text {
                            id: title

                            x: 14
                            y: 12
                            text: "Fleet"
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.baseline: title.baseline
                            spacing: 10

                            Mono {
                                anchors.baseline: parent.baseline
                                font.pixelSize: 12
                                text: F.checked(root.fleet, root.now)
                            }

                            Mono {
                                anchors.baseline: parent.baseline
                                font.pixelSize: 12
                                text: F.liveText(root.fleet)
                                color: text === "read only" ? Theme.orange : Theme.comment
                                font.weight: text === "read only" ? Font.DemiBold : Font.Normal
                            }
                        }
                    }

                    // The pipeline, or GitHub's error in its place.
                    Rectangle {
                        visible: root.pipe !== null && root.pipe.parts !== undefined
                        x: 12
                        width: parent.width - 24
                        height: pipeFlow.implicitHeight + 12
                        radius: 6
                        color: Qt.darker(Theme.background, 1.15)

                        Flow {
                            id: pipeFlow

                            x: 8
                            y: 6
                            width: parent.width - 16
                            spacing: 8

                            Repeater {
                                model: root.pipe?.parts ?? []

                                Text {
                                    required property var modelData
                                    required property int index

                                    // The separator ends a part, so a wrapped line never starts with one.
                                    text: `<font color="${root.soft}">${modelData.label}</font> <font color="${root.tone(modelData.tone || "dim")}">${root.esc(modelData.text)}</font>` + (index < root.pipe.parts.length - 1 ? `&nbsp;&nbsp;<font color="${Theme.comment}">›</font>` : "")
                                    textFormat: Text.StyledText
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.pipe?.error !== undefined && root.pipe?.error !== null
                        x: 12
                        width: parent.width - 24
                        height: errText.implicitHeight + 12
                        radius: 6
                        color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.12)

                        Text {
                            id: errText

                            x: 10
                            y: 6
                            width: parent.width - 20
                            text: root.pipe?.error ?? ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.red
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }
                    }

                    Column {
                        x: 8
                        width: parent.width - 16
                        spacing: 4

                        Repeater {
                            model: root.names

                            HostRow {
                                required property string modelData

                                host: modelData
                            }
                        }

                        Mono {
                            visible: text !== ""
                            x: 8
                            width: parent.width - 16
                            topPadding: 2
                            bottomPadding: 4
                            text: F.checking(root.fleet)
                            wrapMode: Text.Wrap
                        }
                    }

                    KeyHints {
                        keys: (root.names.length > 1 ? [["↑↓ J K", "host"]] : []).concat(root.runUrl !== "" ? [["O", "open build run"]] : []).concat([["F5", "refresh"], ["Esc", F.escLabel(root.ask)]])
                        message: root.flash
                        messageColor: Theme.orange
                    }
                }
            }
        }
    }

    // One host. Its keys and questions show only while it is selected.
    component HostRow: Rectangle {
        id: hostRow

        property string host
        readonly property var row: root.fleet.rows[host]
        readonly property bool isSelected: root.current === host
        readonly property var view: F.rowView(row, root.unfolded[host] === true, root.fleet.actions[host] ?? null, root.fleet.messages[host] ?? "")
        readonly property var question: isSelected && root.ask && root.ask.host === host ? F.question(row, root.ask.what) : null
        readonly property var keyList: isSelected && !question ? F.keys(row, root.fleet.actions[host] ?? null) : []

        width: parent.width
        height: column.implicitHeight + 16
        radius: 6
        color: isSelected ? Qt.lighter(Theme.background, 1.1) : "transparent"
        border.width: 1
        border.color: isSelected ? Theme.currentLine : "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: root.select(hostRow.host)
        }

        Column {
            id: column

            x: 8
            y: 8
            width: parent.width - 16
            spacing: 5

            Item {
                width: parent.width
                height: Math.max(who.implicitHeight, chip.height)

                Row {
                    id: who

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Text {
                        width: 14
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: hostRow.view.glyph
                        color: hostRow.view.dim ? Theme.comment : root.soft
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                    }

                    Text {
                        // Only the name may elide.
                        width: Math.min(implicitWidth, hostRow.width - 16 - chip.width - 12 - 21 - (me.visible ? me.implicitWidth + 7 : 0) - (pill.visible ? pill.width + 7 : 0))
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: hostRow.host
                        color: hostRow.view.dim ? Theme.comment : Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    Mono {
                        id: me

                        visible: hostRow.view.local
                        anchors.verticalCenter: parent.verticalCenter
                        text: "this computer"
                        font.pixelSize: 10
                    }

                    Rectangle {
                        id: pill

                        visible: hostRow.view.mode !== null
                        anchors.verticalCenter: parent.verticalCenter
                        width: pillText.implicitWidth + 8
                        height: pillText.implicitHeight + 2
                        radius: 4
                        color: "transparent"
                        border.width: 1
                        border.color: pillText.color

                        Mono {
                            id: pillText

                            anchors.centerIn: parent
                            text: hostRow.view.mode?.text ?? ""
                            color: hostRow.view.mode?.auto ? Theme.cyan : Theme.comment
                            font.pixelSize: 10
                        }
                    }
                }

                Rectangle {
                    id: chip

                    readonly property color ink: root.tone(hostRow.view.chip.colour)

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: chipText.implicitWidth + 14
                    height: chipText.implicitHeight + 4
                    radius: 5
                    color: Qt.rgba(ink.r, ink.g, ink.b, 0.16)

                    Text {
                        id: chipText

                        anchors.centerIn: parent
                        text: (hostRow.view.chip.busy ? root.spinner + " " : "") + hostRow.view.chip.label
                        color: chip.ink
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            // The helper's lines: key as the label, text in its tone.
            Repeater {
                model: hostRow.view.lines

                Item {
                    required property var modelData

                    x: 21
                    width: column.width - 21
                    height: lineText.implicitHeight

                    Mono {
                        text: parent.modelData.label
                    }

                    Text {
                        id: lineText

                        x: 52
                        width: parent.width - 52
                        text: parent.modelData.text
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: root.tone(parent.modelData.tone)
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            // The last action run from the panel on this host.
            Item {
                visible: hostRow.view.action !== null
                x: 21
                width: column.width - 21
                height: actionText.implicitHeight

                Mono {
                    text: hostRow.view.action?.busy ? root.spinner : ""
                    color: Theme.cyan
                }

                Text {
                    id: actionText

                    x: 52
                    width: parent.width - 52
                    text: hostRow.view.action?.text ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: root.tone(hostRow.view.action?.tone ?? "")
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }

            Text {
                visible: text !== ""
                x: 21 + 52
                width: column.width - 21 - 52
                text: hostRow.view.message
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: Theme.orange
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            // I: the row's info, label then value.
            Column {
                visible: hostRow.view.info.length > 0
                x: 21
                width: column.width - 21
                spacing: 2
                topPadding: 2

                Repeater {
                    model: hostRow.view.info

                    Text {
                        required property var modelData

                        width: parent.width
                        text: `<font color="${Theme.comment}">${root.esc(modelData.label)}</font>&nbsp;&nbsp;${root.esc(modelData.value)}`
                        textFormat: Text.StyledText
                        wrapMode: Text.WrapAnywhere
                        color: root.soft
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                }
            }

            Flow {
                visible: hostRow.keyList.length > 0
                x: 21
                width: column.width - 21
                spacing: 6
                topPadding: 2

                Repeater {
                    model: hostRow.keyList

                    KeyBox {
                        required property var modelData

                        spec: modelData
                    }
                }
            }

            Rectangle {
                visible: hostRow.question !== null
                width: column.width
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
                        text: hostRow.question ? `<b>${root.esc(hostRow.question.title)}</b>` + (hostRow.question.text ? " " + root.esc(hostRow.question.text) : "") : ""
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: hostRow.question?.keys ?? []

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
