import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.audio
import qs.common

// The audio panel, hanging under the bar's audio item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call audio toggle
// The Magni 2 / Modi 2 stack with the Modi's state, the path to it, one row
// per playback stream, every input with a live level, then the settings Nix
// fixes (from ~/.local/share/desk/audio/locked.json, absent with no file).
// Nothing here polls or captures while the panel is closed: no pw-dump, no
// pw-top, no level capture.
Scope {
    id: root

    readonly property bool open: AudioPanel.screen !== ""
    readonly property int panelWidth: 400

    readonly property color soft: Style.soft
    readonly property color chip: Qt.tint(Theme.background, Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.5))
    readonly property color track: Style.track

    readonly property var nodes: Pipewire.nodes.values
    // Without the links to level monitors (this panel's own among them):
    // they are no destination, and a program's monitor must not make it
    // look like it plays.
    readonly property var groups: Pipewire.linkGroups.values.filter(g => g.target?.properties["media.category"] !== "Monitor")
    // Filter-chain halves (the surround sinks' outputs) are streams too;
    // node.link-group marks them.
    readonly property var programs: nodes.filter(n => n.type === PwNodeType.AudioOutStream && n.ready && !n.properties["node.link-group"]).sort((a, b) => a.id - b.id)
    readonly property var inputs: nodes.filter(n => n.type === PwNodeType.AudioSource).sort((a, b) => root.inputName(a).localeCompare(root.inputName(b)))
    readonly property PwNode modiNode: nodes.find(n => n.type === PwNodeType.AudioSink && n.name.startsWith("alsa_output.usb-Schiit_Audio_USB_Modi")) ?? null
    readonly property PwNode sink: Pipewire.defaultAudioSink
    // "Atmos" while the default output is one of the surround sinks.
    readonly property string surround: sink && sink.name.startsWith("effect_input.virtual-surround-") ? bracketed(sink.description) : ""

    // Any change here can mean a stream came, went, started or paused, so
    // formats and the Modi are read again.
    readonly property string graphKey: programs.map(p => p.id).join(",") + "|" + groups.map(g => `${g.source?.id}>${g.target?.id}:${g.state}`).join(",") + "|" + (sink?.id ?? "")

    readonly property string modiState: modiNode === null ? "off" : modi.open ? "play" : "idle"
    readonly property var playing: programs.filter(p => isPlaying(p))
    // The rate the graph runs at: the Modi's while it is open, otherwise its
    // driver's as pw-dump reports it.
    readonly property int graphRate: {
        if (modiState === "play" && modi.openRate > 0)
            return modi.openRate;
        const any = playing.map(p => graph.nodes[graph.nodes[p.id]?.driver]?.rate ?? 0).find(r => r > 0);
        return any ?? 0;
    }

    readonly property var locked: lockedFile.entries
    readonly property bool lockedPresent: lockedFile.present

    readonly property var rows: programs.map(p => ({
                kind: "program",
                key: "p" + p.id,
                node: p
            })).concat(inputs.map(i => ({
                    kind: "input",
                    key: "i" + i.id,
                    node: i
                }))).concat(lockedPresent ? locked.map((l, n) => ({
                    kind: "nix",
                    key: "n" + n,
                    entry: l
                })) : [])
    property string currentKey: ""
    property int lastIndex: 0
    // With no row picked, the nearest program or input; never a Set in Nix
    // row, which is only selected by ↓ or a click. -1 when there is none.
    readonly property int current: {
        const at = rows.findIndex(r => r.key === currentKey);
        if (at >= 0)
            return at;
        let i = Math.min(lastIndex, rows.length - 1);
        while (i >= 0 && rows[i].kind === "nix")
            i--;
        return i;
    }
    readonly property var currentRow: rows[current] ?? null
    readonly property string selectedKey: currentRow?.key ?? ""
    readonly property bool canMove: rows.length > (current >= 0 ? 1 : 0)
    property string expanded: ""
    property string flash: ""
    // Graph period from pw-top while details are open: { quantum, rate }.
    property var period: null

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("audio");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        expanded = "";
        flash = "";
        period = null;
        // Programs show up once bound, after this; no key keeps the first
        // row selected until a key is pressed.
        lastIndex = 0;
        currentKey = "";
        lockedFile.reload();
        AudioPanel.screen = window.screen.name;
        refresh();
    }

    function close(): void {
        AudioPanel.screen = "";
        refreshTimer.stop();
        settleTimer.stop();
    }

    function refresh(): void {
        graph.refresh();
        modi.card = Number(modiNode?.properties["alsa.card"] ?? -1);
        modi.refresh();
        // WirePlumber suspends an idle device after 5 s; read once more
        // after that so the read-out shows the device closing.
        settleTimer.restart();
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function select(index: int): void {
        const row = rows[Math.max(0, Math.min(index, rows.length - 1))];
        if (!row)
            return;
        currentKey = row.key;
        lastIndex = rows.indexOf(row);
    }

    function bracketed(text: string): string {
        return text.match(/\(([^)]+)\)\s*$/)?.[1] ?? text;
    }

    function khz(rate: int): string {
        return rate > 0 ? String(Math.round(rate / 100) / 10) : "?";
    }

    function channelName(n: int): string {
        return ({
                1: "mono",
                2: "stereo",
                6: "5.1",
                8: "7.1"
            })[n] ?? `${n} ch`;
    }

    function sampleText(format: string): string {
        if (format.startsWith("F32"))
            return "32 bit float";
        if (format.startsWith("F64"))
            return "64 bit float";
        const m = format.match(/^[SU](\d+)/);
        return m ? `${m[1]} bit` : format;
    }

    function programName(n: PwNode): string {
        const app = n.properties["application.name"] ?? "";
        // The ALSA plugin names its client "PipeWire ALSA [<program>]".
        const alsa = app.match(/^PipeWire ALSA \[(.+)\]$/);
        return alsa?.[1] || app || n.description || n.name;
    }

    function inputName(n: PwNode): string {
        return NoSignal.inputName(n);
    }

    function layer(n: PwNode): string {
        const api = n.properties["client.api"] ?? graph.clients[graph.nodes[n.id]?.client] ?? "";
        if (api === "pipewire-pulse")
            return "pulse";
        if (api === "alsa" || n.name.startsWith("alsa_playback."))
            return "alsa";
        if (api === "jack")
            return "jack";
        return "native";
    }

    function layerLong(name: string): string {
        return ({
                native: "native PipeWire",
                pulse: "PulseAudio layer (pipewire-pulse)",
                alsa: "ALSA layer (pipewire-alsa)",
                jack: "JACK layer (pipewire-jack)"
            })[name];
    }

    function targetsOf(n: PwNode): var {
        return groups.filter(g => g.source === n && g.target).map(g => g.target);
    }

    function isPlaying(n: PwNode): bool {
        return groups.some(g => g.source === n && g.state === PwLinkState.Active);
    }

    // A stream's monitor captures in its output's channel layout, and
    // Quickshell 0.3.2 only meters it when the stream has each of those
    // channels itself; otherwise it logs an error every cycle and reads 0
    // (a mono stream into the stereo Modi). Such streams get no monitor.
    function meterable(n: PwNode, target: PwNode): bool {
        const own = Array.from(n.audio?.channels ?? []);
        const out = Array.from(target?.audio?.channels ?? []);
        return own.length > 0 && out.length > 0 && out.every(c => own.includes(c));
    }

    // Everything a program row and its details say, from Quickshell's
    // nodes and links plus pw-dump's formats. Fields are 0 / "" / -1 while
    // pw-dump has not answered.
    function facts(n: PwNode): var {
        const own = graph.nodes[n.id] ?? {};
        const target = targetsOf(n)[0] ?? null;
        const through = target && target.name.startsWith("effect_input.virtual-surround-") ? bracketed(target.description) : "";
        const rate = own.rate ?? 0;
        const sinkChannels = graph.nodes[target?.id]?.channels ?? 0;
        const volume = n.audio?.volume ?? 1;
        const muted = n.audio?.muted ?? false;
        const live = isPlaying(n);
        let verdict = ["", Theme.comment];
        if (!live)
            verdict = ["paused", Theme.comment];
        else if (through !== "")
            verdict = [`through ${through}`, Theme.cyan];
        else if (rate > 0 && graphRate > 0 && rate !== graphRate)
            verdict = [`resampled to ${khz(graphRate)}`, Theme.orange];
        else if (own.channels > 0 && sinkChannels > 0 && own.channels > sinkChannels)
            verdict = [`downmixed to ${channelName(sinkChannels)}`, Theme.orange];
        else if (Math.round(volume * 100) !== 100)
            verdict = ["volume scaled", Theme.orange];
        else if (rate > 0 && graphRate > 0)
            verdict = ["direct", Theme.green];
        return {
            layer: layer(n),
            rate,
            channels: own.channels ?? 0,
            format: own.format ?? "",
            quality: own.quality ?? -1,
            driver: own.driver ?? -1,
            target,
            through,
            sinkChannels,
            volume,
            muted,
            live,
            meterable: meterable(n, target),
            verdict
        };
    }

    function details(n: PwNode): var {
        const f = facts(n);
        const lines = [["through", layerLong(f.layer)]];
        lines.push(["sends", f.rate > 0 ? `${khz(f.rate)} kHz · ${sampleText(f.format)} · ${channelName(f.channels)}` : "not known yet"]);
        let becomes;
        if (!f.live)
            becomes = "nothing while paused";
        else if (f.through !== "")
            becomes = `${channelName(f.channels)} folded to stereo by ${f.through}`;
        else if (f.rate > 0 && graphRate > 0 && f.rate !== graphRate)
            becomes = `${khz(graphRate)} kHz, resampled` + (f.quality >= 0 ? ` (quality ${f.quality})` : "");
        else if (f.rate > 0)
            becomes = `${khz(f.rate)} kHz, not resampled`;
        else
            becomes = "not known yet";
        if (f.through === "" && f.channels > 0 && f.sinkChannels > 0 && f.channels > f.sinkChannels)
            becomes += `, downmixed to ${channelName(f.sinkChannels)}`;
        lines.push(["becomes", becomes]);
        lines.push(["goes to", f.target ? (f.target.description || f.target.name) + (f.through !== "" ? " → Modi 2" : "") : "nothing linked"]);
        lines.push(["volume", f.muted ? "muted" : Math.round(f.volume * 100) === 100 ? "100%, untouched" : `${Math.round(f.volume * 100)}%, applied by PipeWire`]);
        if (f.target && !f.meterable)
            lines.push(["level", `not metered: ${channelName(n.audio?.channels.length ?? 0)} into ${channelName(f.target.audio?.channels.length ?? 0)}`]);
        lines.push(["period", period && period.rate > 0 ? `${period.quantum} frames · ${Math.round(period.quantum / period.rate * 1000)} ms` : "measuring…"]);
        return lines;
    }

    function pathHops(): var {
        const n = playing.length;
        if (n === 0)
            return [];
        const hops = [[n === 1 ? "1 program" : `${n} programs`, ""]];
        if (n > 1 && graphRate > 0)
            hops.push([`mixed at ${khz(graphRate)} kHz`, ""]);
        if (surround !== "")
            hops.push([/headphone/i.test(surround) ? surround : `${surround} for headphones`, ""]);
        if (modiNode !== null)
            hops.push([modi.open ? `Modi ${modi.openBits}/${khz(modi.openRate)}` : "Modi 2", ""]);
        else
            hops.push([sink?.description || sink?.name || "no output", "warn"]);
        return hops;
    }

    function step(delta: real): void {
        const row = currentRow;
        if (!row || row.kind === "nix" || !row.node.audio)
            return;
        const audio = row.node.audio;
        audio.volume = Math.max(0, Math.min(1, Math.round((audio.volume + delta) * 100) / 100));
    }

    function activate(): void {
        const row = currentRow;
        if (!row)
            return;
        if (row.kind === "nix") {
            say(`Set in ${row.entry.file}. Change it there and deploy.`);
        } else if (row.kind === "program") {
            expanded = expanded === row.key ? "" : row.key;
            if (expanded !== "") {
                period = null;
                periodQuery.running = true;
            }
        } else if (NoSignal.has(row.node)) {
            say(`${inputName(row.node)} is attached but sends nothing. Unplug its cable for a few seconds.`);
        } else if (Pipewire.defaultAudioSource !== row.node) {
            Pipewire.preferredDefaultAudioSource = row.node;
            say(`${inputName(row.node)} is the default input now, until another is chosen.`);
        }
    }

    // Returns true when the key was used.
    function key(k: int, plain: bool): bool {
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        if (k === Qt.Key_Escape) {
            if (expanded !== "")
                expanded = "";
            else
                close();
        } else if (k === Qt.Key_Down) {
            select(current + 1);
        } else if (k === Qt.Key_Up) {
            select(current - 1);
        } else if (k === Qt.Key_Right) {
            step(0.05);
        } else if (k === Qt.Key_Left) {
            step(-0.05);
        } else if (k === Qt.Key_M && plain) {
            const node = currentRow?.node;
            if (node?.audio)
                node.audio.muted = !node.audio.muted;
        } else if (enter) {
            activate();
        } else {
            return false;
        }
        return true;
    }

    onGraphKeyChanged: if (open)
        refreshTimer.restart()
    onModiNodeChanged: if (open)
        refreshTimer.restart()
    // Also when the selection moves on its own (a row came or went).
    onSelectedKeyChanged: if (expanded !== "" && expanded !== selectedKey)
        expanded = ""

    PwObjectTracker {
        objects: root.open ? root.nodes.filter(n => n.type === PwNodeType.AudioOutStream || n.type === PwNodeType.AudioInStream || n.type === PwNodeType.AudioSource || n.type === PwNodeType.AudioSink).concat(root.groups) : []
    }

    Graph {
        id: graph
    }

    Modi {
        id: modi
    }

    Timer {
        id: refreshTimer

        interval: 250
        onTriggered: root.refresh()
    }

    Timer {
        id: settleTimer

        interval: 6000
        onTriggered: {
            graph.refresh();
            modi.refresh();
        }
    }

    Timer {
        id: flashTimer

        interval: 2500
        onTriggered: root.flash = ""
    }

    // pw-top needs two samples to report a cycle, so this takes a second.
    Process {
        id: periodQuery

        command: ["pw-top", "-b", "-n", "2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const row = root.rows.find(r => r.key === root.expanded);
                const driver = row ? graph.nodes[row.node.id]?.driver ?? -1 : -1;
                let found = null;
                for (const line of text.split("\n")) {
                    const m = line.match(/^\S\s+(\d+)\s+(\d+)\s+(\d+)\s/);
                    if (m && Number(m[1]) === driver && Number(m[2]) > 0)
                        found = {
                            quantum: Number(m[2]),
                            rate: Number(m[3])
                        };
                }
                root.period = found;
            }
        }
    }

    LockedList {
        id: lockedFile

        area: "audio"
    }

    Component.onCompleted: Dropdowns.add("audio", AudioPanel)

    Connections {
        target: AudioPanel

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "audio"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A volume or gain bar: `value` 0..1, purple, pink when its row is
    // selected, empty when muted.
    component Slider: Rectangle {
        property real value
        property bool selected
        property bool muted

        width: parent.width
        height: 4
        radius: 2
        color: root.track

        Rectangle {
            width: parent.muted ? 0 : parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: 2
            color: parent.selected ? Theme.pink : Theme.purple
        }
    }

    // The letter square at the start of a row.
    component Initial: Rectangle {
        property string name

        x: 8
        y: 6
        width: 22
        height: 22
        radius: 6
        color: root.chip

        Text {
            anchors.centerIn: parent
            text: (parent.name.match(/[A-Za-z0-9]/)?.[0] ?? "?").toUpperCase()
            color: root.soft
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    // The facts line under a row's name: [text, colour, boxed] triples.
    component Facts: Flow {
        property var items: []
        property bool selected

        width: parent.width
        spacing: 6

        Repeater {
            model: parent.items

            Rectangle {
                required property var modelData

                width: factText.implicitWidth + (modelData[2] ? 8 : 0)
                height: factText.implicitHeight
                radius: 4
                color: "transparent"
                border.width: modelData[2] ? 1 : 0
                border.color: Theme.comment

                Text {
                    id: factText

                    anchors.centerIn: parent
                    text: parent.modelData[0]
                    textFormat: Text.PlainText
                    color: parent.modelData[1] ?? Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: parent.modelData[2] ? 10 : 11
                }
            }
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
        WlrLayershell.namespace: "desk-audio"
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
                // Of a held key's auto-repeats, only the arrows' act (↑↓
                // select, ←→ step the volume).
                if (event.isAutoRepeat && ![Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key))
                    return;
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                if (root.key(event.key, plain))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("audio", AudioPanel.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // The stack and the Modi's read-out.
                Item {
                    width: parent.width
                    height: Math.max(stack.height, readout.implicitHeight) + 18

                    Stack {
                        id: stack

                        x: 14
                        y: 12 + Math.max(0, (readout.implicitHeight - height) / 2)
                        width: 116
                        modi: root.modiState
                    }

                    Column {
                        id: readout

                        x: 14 + 116 + 12
                        y: 12
                        width: parent.width - x - 14
                        spacing: 6

                        Column {
                            spacing: 2

                            Text {
                                text: "Magni 2"
                                color: Theme.foreground
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Mono {
                                text: "analog · no data"
                                font.pixelSize: 12
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 2

                            Row {
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Modi 2"
                                    color: root.modiState === "off" ? Theme.comment : Theme.foreground
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    readonly property color tone: root.modiState === "play" ? Theme.green : root.modiState === "off" ? Theme.red : Theme.comment

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: pillText.implicitWidth + 14
                                    height: pillText.implicitHeight
                                    radius: height / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.modiState === "idle" ? Theme.currentLine : tone

                                    Mono {
                                        id: pillText

                                        anchors.centerIn: parent
                                        text: root.modiState === "play" ? "playing" : root.modiState === "off" ? "missing" : "idle"
                                        color: parent.tone
                                    }
                                }
                            }

                            Text {
                                text: root.modiState === "play" ? `${modi.openBits} bit · ${root.khz(modi.openRate)} kHz` : root.modiState === "idle" ? "idle" : "not connected"
                                color: root.modiState === "play" ? Theme.cyan : root.modiState === "off" ? Theme.comment : Theme.foreground
                                font.family: Theme.fontMono
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }

                            // What the Modi can take, the format it has open lit.
                            Row {
                                visible: root.modiState !== "off" && (modi.bits.length > 0 || modi.rates.length > 0)
                                spacing: 3

                                Repeater {
                                    model: modi.bits.map(b => [String(b), root.modiState === "play" && b === modi.openBits]).concat([["bit", null]]).concat(modi.rates.map(r => [root.khz(r), root.modiState === "play" && r === modi.openRate])).concat([["kHz", null]])

                                    Rectangle {
                                        required property var modelData
                                        readonly property bool label: modelData[1] === null

                                        width: capText.implicitWidth + (label ? 3 : 8)
                                        height: capText.implicitHeight
                                        radius: 4
                                        color: modelData[1] === true ? Theme.cyan : "transparent"
                                        border.width: label ? 0 : 1
                                        border.color: modelData[1] === true ? Theme.cyan : Theme.currentLine

                                        Mono {
                                            id: capText

                                            anchors.centerIn: parent
                                            text: parent.modelData[0]
                                            color: parent.modelData[1] === true ? Theme.background : Theme.comment
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }

                            Mono {
                                width: parent.width
                                elide: Text.ElideRight
                                font.pixelSize: 12
                                text: {
                                    if (root.modiState === "off")
                                        return "not on USB";
                                    const parts = [modi.clockOwn ? "USB async" : "USB"];
                                    if (root.surround !== "")
                                        parts.push(`fed by ${root.surround}`);
                                    else if (modi.channels > 0)
                                        parts.push(root.channelName(modi.channels));
                                    return parts.join(" · ");
                                }
                            }
                        }
                    }
                }

                // Where the playing programs end up.
                Item {
                    id: pathLine

                    readonly property var hops: root.pathHops()

                    visible: hops.length > 0
                    width: parent.width
                    height: visible ? pathBox.height + 8 : 0

                    Rectangle {
                        id: pathBox

                        x: 14
                        y: 2
                        width: parent.width - 28
                        height: pathFlow.implicitHeight + 14
                        radius: 8
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.currentLine

                        Flow {
                            id: pathFlow

                            x: 10
                            y: 7
                            width: parent.width - 20
                            spacing: 6

                            Repeater {
                                // QML's JavaScript has no flatMap.
                                model: Array.from(pathLine.hops).reduce((all, h, i) => all.concat(i === 0 ? [h] : [["→", "arrow"], h]), [])

                                Text {
                                    required property var modelData

                                    text: modelData[0]
                                    textFormat: Text.PlainText
                                    color: modelData[1] === "arrow" ? Theme.comment : modelData[1] === "warn" ? Theme.orange : root.soft
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    bottomPadding: 4
                    text: "PLAYING"
                }

                Mono {
                    visible: root.programs.length === 0
                    leftPadding: 14
                    bottomPadding: 8
                    topPadding: 2
                    text: "Nothing is playing."
                    font.pixelSize: 12
                }

                Column {
                    visible: root.programs.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 2
                    spacing: 2

                    Repeater {
                        model: root.programs

                        Column {
                            id: program

                            required property PwNode modelData
                            readonly property string key: "p" + modelData.id
                            readonly property bool selected: root.currentRow?.key === key
                            readonly property var f: root.facts(modelData)

                            width: parent.width - 12
                            spacing: 2

                            Rectangle {
                                width: parent.width
                                height: programBody.implicitHeight + 12
                                radius: 6
                                color: program.selected ? Theme.currentLine : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.select(root.rows.findIndex(r => r.key === program.key))
                                }

                                Initial {
                                    name: root.programName(program.modelData)
                                }

                                Column {
                                    id: programBody

                                    x: 40
                                    y: 6
                                    width: parent.width - 48
                                    spacing: 3

                                    Item {
                                        width: parent.width
                                        height: programName.implicitHeight

                                        Text {
                                            id: programName

                                            width: parent.width - 48
                                            elide: Text.ElideRight
                                            text: root.programName(program.modelData)
                                            textFormat: Text.PlainText
                                            color: Theme.foreground
                                            font.family: Theme.fontUi
                                            font.pixelSize: 15
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: program.f.muted ? "mute" : `${Math.round(program.f.volume * 100)}%`
                                            color: program.f.muted ? Theme.red : root.soft
                                            font.family: Theme.fontMono
                                            font.pixelSize: 12
                                        }
                                    }

                                    Facts {
                                        selected: program.selected
                                        items: {
                                            const f = program.f;
                                            const tone = program.selected ? root.soft : Theme.comment;
                                            const list = [[f.layer, tone, true]];
                                            if (f.rate > 0)
                                                list.push([`${root.khz(f.rate)} kHz ${root.channelName(f.channels)}`, tone]);
                                            if (f.verdict[0] !== "")
                                                list.push([f.verdict[0], f.verdict[1] === Theme.comment ? tone : f.verdict[1]]);
                                            return list;
                                        }
                                    }

                                    Item {
                                        width: parent.width
                                        height: 6

                                        Slider {
                                            y: 2
                                            value: program.f.volume
                                            selected: program.selected
                                            muted: program.f.muted
                                        }
                                    }

                                    // What the program adds to the output:
                                    // after its volume, flat when muted or
                                    // paused.
                                    Level {
                                        visible: program.f.meterable
                                        node: program.modelData
                                        active: root.open && program.f.live && program.f.meterable && !program.f.muted
                                        gain: program.f.volume
                                    }
                                }
                            }

                            // Details: what PipeWire knows about this program.
                            Item {
                                visible: root.expanded === program.key
                                width: parent.width
                                height: visible ? detailLines.implicitHeight + 8 : 0

                                Rectangle {
                                    x: 46
                                    y: 0
                                    width: 2
                                    height: detailLines.implicitHeight + 4
                                    color: Theme.currentLine
                                }

                                Column {
                                    id: detailLines

                                    x: 58
                                    y: 2
                                    width: parent.width - 64

                                    Repeater {
                                        model: root.expanded === program.key ? root.details(program.modelData) : []

                                        Row {
                                            required property var modelData

                                            Text {
                                                width: 76
                                                text: parent.modelData[0]
                                                color: Theme.comment
                                                font.family: Theme.fontMono
                                                font.pixelSize: 12
                                                lineHeight: 1.6
                                            }

                                            Text {
                                                width: detailLines.width - 76
                                                wrapMode: Text.Wrap
                                                text: parent.modelData[1]
                                                textFormat: Text.PlainText
                                                color: root.soft
                                                font.family: Theme.fontMono
                                                font.pixelSize: 12
                                                lineHeight: 1.6
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    visible: root.inputs.length > 0
                    bottomPadding: 4
                    text: "INPUTS"
                }

                Column {
                    visible: root.inputs.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 2
                    spacing: 2

                    Repeater {
                        model: root.inputs

                        Rectangle {
                            id: input

                            required property PwNode modelData
                            readonly property string key: "i" + modelData.id
                            readonly property bool selected: root.currentRow?.key === key
                            readonly property bool muted: modelData.audio?.muted ?? false
                            readonly property real gain: modelData.audio?.volume ?? 0
                            readonly property bool noSignal: NoSignal.has(modelData)
                            readonly property var listeners: tracker.linkGroups.map(g => g.target).filter(t => t && t.type === PwNodeType.AudioInStream).map(t => t.properties["application.name"] || t.description || t.name)

                            width: parent.width - 12
                            height: inputBody.implicitHeight + 12
                            radius: 6
                            color: selected ? Theme.currentLine : "transparent"

                            PwNodeLinkTracker {
                                id: tracker

                                node: input.modelData
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.select(root.rows.findIndex(r => r.key === input.key))
                            }

                            Initial {
                                name: root.inputName(input.modelData)
                            }

                            Column {
                                id: inputBody

                                x: 40
                                y: 6
                                width: parent.width - 48
                                spacing: 3

                                Item {
                                    width: parent.width
                                    height: inputName.implicitHeight

                                    Text {
                                        id: inputName

                                        width: parent.width - 48
                                        elide: Text.ElideRight
                                        text: root.inputName(input.modelData)
                                        textFormat: Text.PlainText
                                        color: Theme.foreground
                                        font.family: Theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: input.muted ? "mute" : `${Math.round(input.gain * 100)}%`
                                        color: input.muted ? Theme.red : root.soft
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }
                                }

                                Facts {
                                    readonly property var own: graph.nodes[input.modelData.id] ?? {}

                                    visible: items.length > 0
                                    selected: input.selected
                                    items: {
                                        const tone = input.selected ? root.soft : Theme.comment;
                                        const list = [];
                                        if (Pipewire.defaultAudioSource === input.modelData)
                                            list.push(["default", Theme.cyan]);
                                        if ((own.rate ?? 0) > 0)
                                            list.push([`${root.khz(own.rate)} kHz ${root.channelName(own.channels)}`, tone]);
                                        if (input.noSignal)
                                            list.push(["no signal · replug the cable", Theme.red]);
                                        if (input.listeners.length > 0)
                                            list.push([`heard by ${input.listeners.join(", ")}`, Theme.orange]);
                                        if (inputLevel.clipping)
                                            list.push(["clipping", Theme.red]);
                                        return list;
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 6

                                    Slider {
                                        y: 2
                                        value: input.gain
                                        selected: input.selected
                                        muted: input.muted
                                    }
                                }

                                // Flat while flagged: there is nothing to
                                // measure, and no capture is opened for it.
                                Level {
                                    id: inputLevel

                                    node: input.modelData
                                    active: root.open && !input.noSignal
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    visible: root.lockedPresent && root.locked.length > 0
                    bottomPadding: 4
                    text: "SET IN NIX"
                }

                Column {
                    visible: root.lockedPresent && root.locked.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 2
                    spacing: 2

                    Repeater {
                        model: root.lockedPresent ? root.locked : []

                        Rectangle {
                            id: lockedRow

                            required property var modelData
                            required property int index
                            readonly property string key: "n" + index

                            width: parent.width - 12
                            height: lockedLabel.implicitHeight + 12
                            radius: 6
                            color: root.currentRow?.key === key ? Theme.currentLine : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.select(root.rows.findIndex(r => r.key === lockedRow.key));
                                    root.activate();
                                }
                            }

                            Text {
                                id: lockedLabel

                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - tag.width - 18
                                wrapMode: Text.Wrap
                                text: lockedRow.modelData.label
                                color: Theme.comment
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                            }

                            NixTag {
                                id: tag

                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 6
                }

                KeyHints {
                    message: root.flash
                    keys: {
                        const row = root.currentRow;
                        const move = root.canMove ? [["↑↓", "select"]] : [];
                        if (!row)
                            return move.concat([["Esc", "close"]]);
                        if (row.kind === "nix")
                            return move.concat([["Enter", "show file"], ["Esc", "close"]]);
                        if (row.kind === "input" && NoSignal.has(row.node))
                            return move.concat([["←→", "gain"], ["M", "mute"], ["Enter", "why"], ["Esc", "close"]]);
                        if (row.kind === "input")
                            return move.concat([["←→", "gain"], ["M", "mute"], ["Enter", "make default"], ["Esc", "close"]]);
                        if (root.expanded === row.key)
                            return move.concat([["Enter", "close details"], ["←→", "volume"], ["M", "mute"], ["Esc", "back"]]);
                        return move.concat([["←→", "volume"], ["M", "mute"], ["Enter", "details"], ["Esc", "close"]]);
                    }
                }
            }
        }
    }
}
