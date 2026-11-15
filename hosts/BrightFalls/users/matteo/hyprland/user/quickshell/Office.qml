import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.office
import "office/office.js" as O

// The office panel, hanging under the bar's office item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call office toggle
// The light (on/off, brightness) and the blind (up, stop, down, position),
// controlled through desk-mqtt (OfficeShared), and the sockets' power, watched
// only: nothing here can address a socket. A slider is sent once, on mouse or
// key release; a command that is not confirmed is put back and said, never
// retried.
Scope {
    id: root

    readonly property bool open: OfficeShared.screen !== ""
    readonly property int panelWidth: 360

    readonly property var office: OfficeShared.office
    property real now: Date.now()
    // 0 the light, 1 the blind; the sockets are never selected.
    property int selected: 0
    // Percent being dragged or keyed on the light, position on the blind, or
    // null.
    property var lightDraft: null
    property var blindDraft: null
    // The position last asked of the blind, shown as the handle while it
    // moves there.
    property var blindTarget: null
    property string flash: ""

    readonly property string single: O.single(office)
    readonly property var banner: O.banner(office, now)
    readonly property bool neverUp: O.neverUp(office)
    readonly property bool stale: O.stale(office)
    readonly property var light: O.lightView(office, now, lightDraft)
    readonly property var blind: O.blindView(office, now, blindDraft, blindTarget)
    readonly property var sockets: O.socketsView(office, now)
    readonly property bool anyControl: (light !== null && !light.locked) || (blind !== null && !blind.locked)

    readonly property color soft: Style.soft

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("office");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        now = Date.now();
        selected = 0;
        lightDraft = null;
        blindDraft = null;
        flash = "";
        OfficeShared.screen = window.screen.name;
    }

    function close(): void {
        lightDraft = null;
        blindDraft = null;
        OfficeShared.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function send(device: string, action: string, value: var): void {
        if (!OfficeShared.send(device, action, value))
            say("The office helper is not running.");
    }

    function toggleLight(): void {
        if (!light)
            return;
        if (light.locked) {
            say(O.lockText(office, "light"));
            return;
        }
        send(light.id, light.on ? "off" : "on", null);
    }

    function blindAction(action: string): void {
        if (!blind)
            return;
        if (blind.locked) {
            say(O.lockText(office, "blind"));
            return;
        }
        if ((action === "open" && blind.upOff) || (action === "close" && blind.downOff))
            return;
        blindTarget = action === "open" && blind.hasPosition ? 100 : action === "close" && blind.hasPosition ? 0 : null;
        send(blind.id, action, null);
    }

    // Moves the selected row's slider one step.
    function nudge(direction: int): void {
        if (selected === 0) {
            if (!light || !light.slider)
                return;
            if (light.locked) {
                say(O.lockText(office, "light"));
                return;
            }
            lightDraft = O.step(lightDraft ?? light.handle, direction, 1, 100);
        } else {
            if (!blind || !blind.hasPosition)
                return;
            if (blind.locked) {
                say(O.lockText(office, "blind"));
                return;
            }
            blindDraft = O.step(blindDraft ?? blind.handle, direction, 0, 100);
        }
    }

    // Sends a slider's value, once, when the key or the mouse lets go. An
    // off light is sent its brightness too: that turns it on at that level.
    function commitLight(): void {
        const draft = lightDraft;
        lightDraft = null;
        if (draft === null || !light || light.locked || (light.on && draft === light.percent))
            return;
        send(light.id, "brightness", O.toRaw(draft));
    }

    function commitBlind(): void {
        const draft = blindDraft;
        blindDraft = null;
        if (draft === null || !blind || blind.locked || draft === blind.position)
            return;
        blindTarget = draft;
        send(blind.id, "position", draft);
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const k = event.key;
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        if (k === Qt.Key_Escape)
            close();
        else if (single !== "")
            return false;
        else if (k === Qt.Key_Up || k === Qt.Key_Down) {
            commitLight();
            commitBlind();
            selected = k === Qt.Key_Up ? 0 : 1;
        } else if (k === Qt.Key_Left || k === Qt.Key_Right)
            nudge(k === Qt.Key_Left ? -1 : 1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            toggleLight();
        else if (k === Qt.Key_U && plain)
            blindAction("open");
        else if (k === Qt.Key_S && plain)
            blindAction("stop");
        else if (k === Qt.Key_D && plain)
            blindAction("close");
        else
            return false;
        return true;
    }

    function release(event: var): void {
        if (event.isAutoRepeat || (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right))
            return;
        commitLight();
        commitBlind();
    }


    Timer {
        id: flashTimer

        interval: 5000
        onTriggered: root.flash = ""
    }

    // Ages count while the panel is open.
    Timer {
        interval: 10000
        running: root.open
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Component.onCompleted: Dropdowns.add("office", OfficeShared)

    Connections {
        target: OfficeShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
        function onFailed(device, text) {
            if (root.open)
                root.say(text);
        }
        // The blind's target is kept only while it may still be moving
        // there.
        function onOfficeChanged() {
            if (root.blindTarget === null || !root.blind || root.blind.moving)
                return;
            if (!Object.values(OfficeShared.office.commands).some(c => c.device === root.blind.id))
                root.blindTarget = null;
        }
    }

    IpcHandler {
        target: "office"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A section's small capitals, with an optional note at the right.
    component Section: Item {
        property string title
        property string note

        width: parent.width
        height: 22

        Mono {
            x: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            text: parent.title.toUpperCase()
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        Mono {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            text: parent.note.toUpperCase()
            font.pixelSize: 10
            font.letterSpacing: 1
        }
    }

    // A slider: the fill is the confirmed value, the handle the asked one
    // (none when null). `send` gets the value under the pointer on release.
    component Slider: Item {
        id: slider

        property real fill
        property var handle
        property color colour: Theme.purple
        property bool locked
        property int minimum: 0
        signal dragged(int value)
        signal released

        height: 14

        function at(x: real): int {
            return Math.max(minimum, Math.min(100, Math.round(x / width * 100)));
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Style.track

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, slider.fill / 100))
                height: parent.height
                radius: 3
                color: slider.locked ? Theme.comment : slider.colour
            }
        }

        Rectangle {
            visible: slider.handle !== null && slider.handle !== undefined && !slider.locked
            x: Math.max(0, Math.min(parent.width - width, parent.width * slider.handle / 100 - width / 2))
            width: 4
            height: 14
            radius: 2
            color: Theme.foreground
        }

        MouseArea {
            anchors.fill: parent
            enabled: !slider.locked
            preventStealing: true
            onPressed: mouse => slider.dragged(slider.at(mouse.x))
            onPositionChanged: mouse => slider.dragged(slider.at(mouse.x))
            onReleased: slider.released()
        }
    }

    // ▲ ■ ▼ on the blind's row.
    component Button: Rectangle {
        id: button

        property string glyph
        property bool off
        property bool lit
        signal clicked

        width: 26
        height: 20
        radius: 5
        color: off ? "transparent" : area.containsMouse ? Theme.currentLine : Qt.lighter(Theme.background, 1.12)
        border.width: 1
        border.color: lit && !off ? Theme.purple : off ? Qt.darker(Theme.currentLine, 1.15) : Theme.currentLine

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: button.off ? Theme.comment : button.lit ? Theme.purple : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: 11
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            enabled: !button.off
            onClicked: button.clicked()
        }
    }

    // The state line under a row: text on the left, age on the right.
    component Sub: Item {
        property string text
        property string tone
        property var age
        property bool grey

        width: parent.width
        height: Math.max(subText.implicitHeight, ageText.implicitHeight)

        Text {
            id: subText

            width: parent.width - ageText.implicitWidth - 8
            text: parent.text
            wrapMode: Text.Wrap
            color: parent.tone === "bad" ? Theme.red : parent.tone === "note" ? Theme.orange : parent.tone === "dim" || parent.grey ? Theme.comment : root.soft
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        Mono {
            id: ageText

            anchors.right: parent.right
            text: parent.age ? parent.age.text : ""
            color: parent.age && parent.age.old ? Theme.orange : Theme.comment
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
        WlrLayershell.namespace: "desk-office"
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
            Keys.onReleased: event => root.release(event)
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("office", OfficeShared.screen) : -1
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

                    Item {
                        width: parent.width
                        height: title.implicitHeight + 16

                        Text {
                            id: title

                            x: 14
                            y: 12
                            text: "Office"
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Mono {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.baseline: title.baseline
                            font.pixelSize: 12
                            text: O.liveText(root.office)
                            color: text === "read only" ? Theme.orange : Theme.comment
                            font.weight: text === "read only" ? Font.DemiBold : Font.Normal
                        }
                    }

                    Rectangle {
                        visible: root.banner.text !== ""
                        x: 12
                        width: parent.width - 24
                        height: bannerText.implicitHeight + 12
                        radius: 6
                        color: Qt.rgba(bannerText.color.r, bannerText.color.g, bannerText.color.b, 0.12)

                        Text {
                            id: bannerText

                            x: 8
                            y: 6
                            width: parent.width - 16
                            text: root.banner.text
                            wrapMode: Text.Wrap
                            color: root.banner.tone === "err" ? Theme.red : Theme.orange
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }
                    }

                    Section {
                        visible: root.light !== null
                        title: "Light"
                    }

                    // The light.
                    Rectangle {
                        id: lightRow

                        visible: root.light !== null
                        x: 8
                        width: parent.width - 16
                        height: lightColumn.implicitHeight + 10
                        radius: 6
                        color: root.selected === 0 && root.anyControl ? Theme.currentLine : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selected = 0
                        }

                        Text {
                            x: 6
                            y: 5
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: root.light?.on && root.light?.known && !root.light?.offline ? "●" : "○"
                            color: root.light?.lit ? Theme.yellow : Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 13

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                enabled: !root.neverUp
                                onClicked: {
                                    root.selected = 0;
                                    root.toggleLight();
                                }
                            }
                        }

                        Column {
                            id: lightColumn

                            x: 30
                            y: 5
                            width: parent.width - 36
                            spacing: 3

                            Item {
                                width: parent.width
                                height: lightName.implicitHeight

                                Text {
                                    id: lightName

                                    width: parent.width - lightValue.implicitWidth - 8
                                    elide: Text.ElideRight
                                    text: root.light?.label ?? ""
                                    color: root.light?.locked ? Theme.comment : Theme.foreground
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                }

                                Text {
                                    id: lightValue

                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.light?.value ?? ""
                                    color: root.light?.dim || !root.light?.known ? Theme.comment : root.soft
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }

                            Slider {
                                visible: root.light?.slider ?? false
                                width: parent.width
                                fill: root.light?.percent ?? 0
                                handle: root.light && root.light.on && !root.light.locked ? root.light.handle : root.lightDraft
                                locked: (root.light?.locked ?? true) || !(root.light?.on ?? false) && root.lightDraft === null
                                minimum: 1
                                onDragged: value => {
                                    if (root.light.locked)
                                        return;
                                    root.selected = 0;
                                    root.lightDraft = value;
                                }
                                onReleased: root.commitLight()
                            }

                            Sub {
                                visible: text !== ""
                                text: root.light?.sub ?? ""
                                tone: root.light?.tone ?? ""
                                age: root.light?.age
                                grey: root.light?.locked ?? false
                            }
                        }
                    }

                    Section {
                        visible: root.blind !== null
                        title: "Blind"
                    }

                    // The blind.
                    Rectangle {
                        visible: root.blind !== null
                        x: 8
                        width: parent.width - 16
                        height: blindColumn.implicitHeight + 10
                        radius: 6
                        color: root.selected === 1 && root.anyControl ? Theme.currentLine : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selected = 1
                        }

                        Text {
                            x: 6
                            y: 5
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: "▤"
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                        }

                        Column {
                            id: blindColumn

                            x: 30
                            y: 5
                            width: parent.width - 36
                            spacing: 3

                            Item {
                                width: parent.width
                                height: Math.max(blindName.implicitHeight, buttons.height)

                                Text {
                                    id: blindName

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (buttons.visible ? buttons.width : blindUnknown.implicitWidth) - 8
                                    elide: Text.ElideRight
                                    text: root.blind?.label ?? ""
                                    color: root.blind?.locked ? Theme.comment : Theme.foreground
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                }

                                Text {
                                    id: blindUnknown

                                    visible: root.neverUp
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "not known"
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }

                                Row {
                                    id: buttons

                                    visible: !root.neverUp
                                    anchors.right: parent.right
                                    spacing: 5

                                    Button {
                                        glyph: "▲"
                                        off: root.blind?.upOff ?? true
                                        onClicked: root.blindAction("open")
                                    }

                                    Button {
                                        glyph: "■"
                                        off: root.blind?.stopOff ?? true
                                        lit: root.blind?.moving ?? false
                                        onClicked: root.blindAction("stop")
                                    }

                                    Button {
                                        glyph: "▼"
                                        off: root.blind?.downOff ?? true
                                        onClicked: root.blindAction("close")
                                    }
                                }
                            }

                            Slider {
                                visible: root.blind?.hasPosition ?? false
                                width: parent.width
                                colour: Theme.cyan
                                fill: root.blind?.position ?? 0
                                handle: root.blind?.handle ?? null
                                locked: root.blind?.locked ?? true
                                onDragged: value => {
                                    root.selected = 1;
                                    root.blindDraft = value;
                                }
                                onReleased: root.commitBlind()
                            }

                            Sub {
                                visible: text !== ""
                                text: root.blind?.sub ?? ""
                                tone: root.blind?.tone ?? ""
                                age: root.blind?.age
                                grey: root.blind?.locked ?? false
                            }
                        }
                    }

                    Section {
                        visible: root.sockets.all > 0
                        title: "Power"
                        note: "watch only"
                    }

                    // The total.
                    Item {
                        visible: root.sockets.all > 0 && !root.neverUp
                        width: parent.width
                        height: total.implicitHeight + 4

                        Text {
                            id: total

                            x: 14
                            text: root.sockets.counted > 0 ? `${root.sockets.watts} W` : "— W"
                            color: root.stale ? Theme.comment : Theme.foreground
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }

                        Mono {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.baseline: total.baseline
                            text: root.sockets.text
                        }
                    }

                    // Before the broker has ever answered: one line for all.
                    SocketRow {
                        visible: root.sockets.all > 0 && root.neverUp
                        label: `${root.sockets.all} sockets`
                        dot: "silent"
                        watts: "—"
                        grey: true
                    }

                    Column {
                        visible: !root.neverUp
                        width: parent.width
                        bottomPadding: 6

                        Repeater {
                            model: root.sockets.rows

                            SocketRow {
                                required property var modelData

                                label: modelData.label
                                dot: modelData.state
                                share: modelData.share
                                watts: modelData.state === "offline" ? "offline" : modelData.state === "off" ? "off" : modelData.state === "silent" || modelData.power === null ? "—" : `${Math.round(modelData.power)} W`
                                wattsColour: modelData.state === "offline" ? Theme.red : modelData.state === "off" || modelData.state === "silent" || root.stale ? Theme.comment : Theme.foreground
                                age: modelData.age
                                grey: modelData.state === "offline" || modelData.state === "silent" || root.stale
                            }
                        }
                    }

                    KeyHints {
                        keys: root.anyControl ? [["↑↓", "select"], ["←→", "slider ±10 %"], ["Enter", "light on/off"], ["U S D", "blind up, stop, down"], ["Esc", "close"]] : [["Esc", "close"]]
                        message: root.flash
                        messageColor: Theme.orange
                    }
                }
            }
        }
    }

    // One socket: state dot, name, share of the largest, watts, age. Never
    // selectable and nothing to click.
    component SocketRow: Item {
        id: socket

        property string label
        // "on" | "off" | "offline" | "silent"
        property string dot
        property real share
        property string watts
        property color wattsColour: Theme.comment
        property var age: null
        property bool grey

        x: 8
        width: parent.width - 16
        height: 22

        Rectangle {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: socket.dot === "on" ? (socket.grey ? Theme.comment : Theme.green) : socket.dot === "offline" ? Theme.red : socket.dot === "silent" ? Theme.comment : "transparent"
            border.width: socket.dot === "off" ? 1 : 0
            border.color: Theme.comment
        }

        Text {
            x: 30
            anchors.verticalCenter: parent.verticalCenter
            width: shareBar.x - x - 8
            elide: Text.ElideRight
            text: socket.label
            color: socket.grey ? Theme.comment : Theme.foreground
            font.family: Theme.fontUi
            font.pixelSize: 12
        }

        Rectangle {
            id: shareBar

            x: wattsText.x - 8 - width
            anchors.verticalCenter: parent.verticalCenter
            width: 60
            height: 5
            radius: 2.5
            color: Style.track
            // Not on the one line for all sockets, which has no age.
            visible: socket.age !== null

            Rectangle {
                width: parent.width * socket.share
                height: parent.height
                radius: 2.5
                color: socket.grey ? Theme.comment : Theme.orange
            }
        }

        Text {
            id: wattsText

            x: ageText.x - 8 - width
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            horizontalAlignment: Text.AlignRight
            text: socket.watts
            color: socket.wattsColour
            font.family: Theme.fontMono
            font.pixelSize: 12
        }

        Mono {
            id: ageText

            x: parent.width - 6 - width
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            horizontalAlignment: Text.AlignRight
            text: socket.age ? socket.age.text : "—"
            color: socket.age && socket.age.old ? Theme.orange : Theme.comment
            font.pixelSize: 11
        }
    }
}
