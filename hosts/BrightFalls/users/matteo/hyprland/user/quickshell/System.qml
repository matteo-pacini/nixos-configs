import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.system
import "system/decode.js" as D

// The system panel, hanging under the bar's system item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call system toggle
// The machine drawn with its fans turning at the card's speed, the eGPU link,
// then CPU, memory, eGPU, iGPU, storage and network. Read-only: figures come
// from Sensors, which reads sysfs and procfs; with the panel closed it reads
// only what the bar item and its hover list show (see its header).
Scope {
    id: root

    readonly property bool open: SystemPanel.screen !== ""
    readonly property int panelWidth: 420

    readonly property color soft: Style.soft
    readonly property color track: Style.track

    readonly property var s: Sensors.s
    readonly property var sections: ["cpu", "mem", "egpu", "igpu", "storage"]
    property int current: 0
    property bool details: false

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("system");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        current = 0;
        details = false;
        SystemPanel.screen = window.screen.name;
    }

    function close(): void {
        SystemPanel.screen = "";
    }

    // Returns true when the key was used.
    function key(k: int): bool {
        if (k === Qt.Key_Escape) {
            if (details)
                details = false;
            else
                close();
        } else if (k === Qt.Key_Down) {
            current = Math.min(sections.length - 1, current + 1);
        } else if (k === Qt.Key_Up) {
            current = Math.max(0, current - 1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            details = !details;
        } else {
            return false;
        }
        return true;
    }

    function temp(t: var): string {
        return t === null || t === undefined ? "–" : `${Math.round(t)} °C`;
    }

    function heatColor(level: int): color {
        return level === 2 ? Theme.red : level === 1 ? Theme.orange : root.soft;
    }

    function percent(used: var, total: var): var {
        return used === null || used === undefined || !total ? null : used / total * 100;
    }

    function known(x: var): bool {
        return x !== null && x !== undefined;
    }

    // "0.07 / 2" under 4 GiB, "5.1 / 16" above.
    function gibPair(used: var, total: var): string {
        if (!known(used) || !known(total))
            return "–";
        const digits = total < 4 * 1073741824 ? 2 : 1;
        const g = x => String(Number((x / 1073741824).toFixed(digits)));
        return `${g(used)} / ${g(total)} GiB`;
    }

    onOpenChanged: if (!open)
        details = false

    Component.onCompleted: Dropdowns.add("system", SystemPanel)

    Connections {
        target: SystemPanel

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "system"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    component Pill: Rectangle {
        property string text
        property color tone: Theme.comment

        width: pillText.implicitWidth + 14
        height: pillText.implicitHeight + 2
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: tone

        Mono {
            id: pillText

            anchors.centerIn: parent
            text: parent.text
            color: parent.tone
            font.pixelSize: 10
        }
    }

    // A section's title line: name, what it is, tags, and its temperature
    // at the right, coloured by its limit.
    component Head: Item {
        id: head

        property string title
        property string sub
        property var pills: []
        property string temp: ""
        property int heat: 0

        width: parent.width
        height: titleText.implicitHeight

        Text {
            id: titleText

            text: head.title
            color: Theme.foreground
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Mono {
            x: titleText.implicitWidth + 8
            anchors.baseline: titleText.baseline
            width: Math.max(0, tail.x - x - 8)
            elide: Text.ElideRight
            text: head.sub
        }

        Row {
            id: tail

            anchors.right: parent.right
            anchors.verticalCenter: titleText.verticalCenter
            spacing: 8

            Repeater {
                model: head.pills

                Pill {
                    required property var modelData

                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData[0]
                    tone: modelData[1]
                }
            }

            Text {
                visible: head.temp !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: head.temp
                color: root.heatColor(head.heat)
                font.family: Theme.fontMono
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // Label and value pairs: [label, value, heat, nix].
    component Pairs: Grid {
        id: pairs

        property var rows: []

        columns: 2
        columnSpacing: 10
        rowSpacing: 1

        Repeater {
            model: pairs.rows.length * 2

            Item {
                id: cell

                required property int index
                readonly property var row: pairs.rows[Math.floor(index / 2)]
                readonly property bool isLabel: index % 2 === 0

                width: isLabel ? pairs.labelWidth : Math.max(0, pairs.width - pairs.labelWidth - pairs.columnSpacing)
                height: Math.max(labelText.implicitHeight, valueRow.implicitHeight)

                Mono {
                    id: labelText

                    visible: cell.isLabel
                    text: cell.row[0]
                }

                Row {
                    id: valueRow

                    visible: !cell.isLabel
                    width: parent.width
                    spacing: 6

                    Mono {
                        width: Math.min(implicitWidth, valueRow.width - (tag.visible ? tag.width + 6 : 0))
                        elide: Text.ElideRight
                        text: cell.row[1]
                        color: root.heatColor(cell.row[2] ?? 0)
                    }

                    NixTag {
                        id: tag

                        pixelSize: 10
                        visible: cell.row[3] === true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        readonly property real labelWidth: Math.ceil(Math.max(0, ...rows.map(r => monoMetrics.advanceWidth(r[0]))))
    }

    FontMetrics {
        id: monoMetrics

        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A label, a thin bar and a value, for swap and the volumes.
    component BarRow: Item {
        id: barRow

        property string label
        property var value: null
        property string text

        width: parent.width
        height: barValue.implicitHeight

        Mono {
            width: 62
            elide: Text.ElideRight
            text: barRow.label
        }

        Rectangle {
            x: 72
            anchors.verticalCenter: parent.verticalCenter
            width: barRow.width - x - barValue.implicitWidth - 10
            height: 5
            radius: 3
            color: root.track

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, (barRow.value ?? 0) / 100))
                height: parent.height
                radius: 3
                color: (barRow.value ?? 0) >= 90 ? Theme.pink : Theme.purple
            }
        }

        Mono {
            id: barValue

            anchors.right: parent.right
            text: barRow.text
            color: root.soft
        }
    }

    // One section: a highlight while it is the current one, then its rows.
    component Section: Rectangle {
        id: section

        required property string name
        default property alias body: inner.data

        readonly property bool selected: root.sections[root.current] === name

        width: parent.width
        height: inner.implicitHeight + 22
        color: selected ? Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.45) : "transparent"

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.currentLine
        }

        Rectangle {
            visible: section.selected
            y: 1
            width: 2
            height: parent.height - 1
            color: Theme.purple
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                const at = root.sections.indexOf(section.name);
                if (root.current === at)
                    root.details = !root.details;
                else
                    root.current = at;
            }
        }

        Column {
            id: inner

            x: 14
            y: 11
            width: parent.width - 28
            spacing: 8
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
        WlrLayershell.namespace: "desk-system"
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
                if (root.key(event.key))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("system", SystemPanel.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // The machine.
                Item {
                    width: parent.width
                    height: machine.height + 16

                    Machine {
                        id: machine

                        x: 12
                        y: 12
                        width: parent.width - 24
                        height: implicitHeight * width / implicitWidth
                        egpu: root.s.egpuPresent ?? true
                        rpm: root.s.egpuAwake ? root.s.fanRpm ?? 0 : 0
                        hot: (root.s.egpuLoad ?? 0) > 60
                        running: root.open
                    }
                }

                // The cable hop: what was negotiated against what the port
                // can do, and the honest power sum.
                Row {
                    readonly property var link: root.s.link ?? {}
                    readonly property var power: root.s.egpuPresent && root.s.egpuAwake && root.known(root.s.packageW) && root.known(root.s.egpuPower) ? Math.round(root.s.packageW + root.s.egpuPower) : null

                    anchors.horizontalCenter: parent.horizontalCenter
                    bottomPadding: 10
                    spacing: 12

                    Mono {
                        visible: !(root.s.egpuPresent ?? true)
                        text: "no card on the OCuLink port"
                    }

                    Mono {
                        visible: (root.s.egpuPresent ?? false) && !!parent.link.gen
                        text: `PCIe ${parent.link.gen}.0 ×${parent.link.width}`
                        color: root.soft
                        font.weight: Font.Medium
                    }

                    Mono {
                        visible: (root.s.egpuPresent ?? false) && (parent.link.state ?? "") !== ""
                        text: parent.link.state === "full" ? "full width" : parent.link.state === "saving" ? "power-saving, card's choice" : parent.link.width < parent.link.maxWidth ? `reduced, port can do ×${parent.link.maxWidth}` : `reduced, port can do PCIe ${parent.link.maxGen}.0`
                        color: parent.link.state === "full" ? Theme.green : parent.link.state === "reduced" ? Theme.orange : Theme.comment
                    }

                    Mono {
                        visible: parent.power !== null && parent.link.state !== "reduced"
                        text: `≈ ${parent.power} W chip + card`
                    }
                }

                // CPU.
                Section {
                    name: "cpu"

                    Head {
                        title: "CPU"
                        sub: [root.s.cpuModel, root.s.threadCount ? `${root.s.threadCount} threads` : ""].filter(x => x).join(" · ")
                        temp: root.temp(root.s.cpuTemp)
                        heat: Sensors.heat("cpu", root.s.cpuTemp)
                    }

                    Row {
                        width: parent.width
                        spacing: 12

                        Ring {
                            value: root.s.cpuLoad ?? null
                            label: "load"
                        }

                        Pairs {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 66 - 12
                            rows: [["clock", root.known(root.s.clockAvg) && root.known(root.s.scalingMax) ? `${D.ghz(root.s.clockAvg)} GHz avg · ${D.ghz(root.s.scalingMax)} max` : "–", 0, root.s.capNix === true], ["hottest core", root.temp(root.s.cpuHottest), Sensors.heat("core", root.s.cpuHottest)], ["package", root.known(root.s.packageW) ? `${Math.round(root.s.packageW)} W` : "–"]]
                        }
                    }

                    // One bar per thread.
                    Row {
                        id: threads

                        readonly property var loads: root.s.threads ?? []

                        width: parent.width
                        height: 26
                        spacing: 3

                        Repeater {
                            model: threads.loads.length

                            Item {
                                required property int index
                                readonly property real load: threads.loads[index] ?? 0

                                width: (threads.width - 3 * (threads.loads.length - 1)) / threads.loads.length
                                height: threads.height

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * Math.max(parent.load, 6) / 100)
                                    radius: 2
                                    color: parent.load > 80 ? Theme.pink : Theme.purple
                                }
                            }
                        }
                    }

                    Pairs {
                        visible: root.details && root.current === 0
                        width: parent.width
                        rows: {
                            const s = root.s;
                            const rows = [["policy", [s.governor, s.epp].filter(x => x).join(" · ") || "–"]];
                            if (root.known(s.scalingMax) && root.known(s.cpuinfoMax))
                                rows.push(["limit", s.scalingMax < s.cpuinfoMax ? `${D.ghz(s.scalingMax)} GHz of ${D.ghz(s.cpuinfoMax, 2)} possible` : `none, ${D.ghz(s.cpuinfoMax, 2)} GHz`, 0, s.capNix === true]);
                            if (s.capNix)
                                rows.push(["set in", s.capFile]);
                            rows.push(["load average", s.loadavg || "–"]);
                            return rows;
                        }
                    }
                }

                // Memory.
                Section {
                    name: "mem"

                    Head {
                        readonly property var dimms: root.s.dimms ?? []

                        title: "Memory"
                        sub: dimms.length ? `${dimms.length} modules` : ""
                        temp: dimms.length ? dimms.map(t => Math.round(t)).join(" · ") + " °C" : ""
                        heat: Sensors.heat("dimm", dimms.length ? Math.max(...dimms) : null)
                    }

                    Row {
                        width: parent.width
                        spacing: 12

                        Ring {
                            value: root.percent(root.s.memUsed, root.s.memTotal)
                            label: "used"
                        }

                        Pairs {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 66 - 12
                            rows: [["in use", root.gibPair(root.s.memUsed, root.s.memTotal)], ["cached", root.known(root.s.memCached) ? `${D.gib(root.s.memCached)} GiB` : "–"]]
                        }
                    }

                    BarRow {
                        label: "swap"
                        value: root.percent(root.s.swapUsed, root.s.swapTotal)
                        text: root.s.swapTotal ? root.gibPair(root.s.swapUsed, root.s.swapTotal) : "none"
                    }

                    Pairs {
                        visible: root.details && root.current === 1
                        width: parent.width
                        rows: [["available", root.known(root.s.memAvailable) ? `${D.gib(root.s.memAvailable)} GiB` : "–"], ["buffers", root.known(root.s.memBuffers) ? `${D.gib(root.s.memBuffers)} GiB` : "–"], ["shared", root.known(root.s.memShared) ? `${D.gib(root.s.memShared)} GiB` : "–"]]
                    }
                }

                // eGPU.
                Section {
                    id: egpuSection

                    name: "egpu"

                    readonly property bool present: root.s.egpuPresent ?? true
                    readonly property bool awake: present && (root.s.egpuAwake ?? true)

                    Head {
                        title: "eGPU"
                        sub: egpuSection.present ? root.s.egpuName ?? "" : ""
                        pills: {
                            const s = root.s;
                            if (!egpuSection.present)
                                return [["not connected", Theme.red]];
                            if (!egpuSection.awake)
                                return [["asleep", Theme.comment]];
                            if ((s.throttle ?? []).length > 0)
                                return [[`throttling: ${s.throttle.join(", ")}`, Theme.red]];
                            if ((s.egpuDriving ?? []).length > 0)
                                return [[`driving ${s.egpuDriving.join(", ")}`, Theme.green]];
                            return [];
                        }
                        temp: egpuSection.awake ? root.temp(root.s.egpuEdge) : ""
                        heat: Math.max(Sensors.heat("edge", root.s.egpuEdge), Sensors.heat("junction", root.s.egpuJunction))
                    }

                    Mono {
                        visible: !egpuSection.awake
                        width: parent.width
                        wrapMode: Text.Wrap
                        topPadding: 2
                        bottomPadding: 4
                        font.pixelSize: 12
                        text: !egpuSection.present ? ((root.s.igpuDriving ?? []).length > 0 ? `Displays are driven by the ${root.s.igpuName || "iGPU"}.` : "No card on the OCuLink port.") : "The card is powered down; its figures return when it wakes."
                    }

                    Row {
                        visible: egpuSection.awake
                        width: parent.width
                        spacing: 12

                        Row {
                            id: egpuRings

                            spacing: 8

                            Ring {
                                value: root.s.egpuLoad ?? null
                                label: "load"
                            }

                            Ring {
                                value: root.percent(root.s.egpuVramUsed, root.s.egpuVramTotal)
                                label: "vram"
                            }
                        }

                        Pairs {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - egpuRings.width - 12
                            rows: {
                                const s = root.s;
                                return [["junction", root.temp(s.egpuJunction), Sensors.heat("junction", s.egpuJunction)], ["memory", root.temp(s.egpuMem), Sensors.heat("mem", s.egpuMem)], ["fan", root.known(s.fanRpm) ? `${s.fanRpm} rpm` + (root.known(s.fanPct) ? ` · ${Math.round(s.fanPct)}%` : "") : "–"], ["power", root.known(s.egpuPower) ? `${s.egpuPower} W` : "–"], ["clocks", root.known(s.coreClock) ? `${s.coreClock} · ${s.memClock ?? "–"} MHz` : "–"], ["voltage", root.known(s.voltGfx) ? `${(s.voltGfx / 1000).toFixed(3)} V` : "–"]];
                            }
                        }
                    }

                    Pairs {
                        visible: root.details && root.current === 2 && egpuSection.awake
                        width: parent.width
                        rows: {
                            const s = root.s;
                            const vr = s.egpuVr ?? [];
                            const rows = [["edge", root.temp(s.egpuEdge), Sensors.heat("edge", s.egpuEdge)], ["regulators", vr.length && vr.every(x => root.known(x)) ? `${vr.join(" · ")} °C  (gfx · soc · mem)` : "–"], ["voltages", root.known(s.voltSoc) && root.known(s.voltMem) ? `SoC ${(s.voltSoc / 1000).toFixed(2)} V · memory ${(s.voltMem / 1000).toFixed(2)} V` : "–"], ["vram", root.gibPair(s.egpuVramUsed, s.egpuVramTotal)], ["power limit", root.known(s.egpuCap) ? `${Math.round(s.egpuCap)} W` : "–"], ["fan control", s.fanControl || "–"]];
                            if (s.lactFile)
                                rows.push(["LACT daemon", `set in ${s.lactFile}`, 0, true]);
                            if ((s.linkErrors ?? 0) > 0)
                                rows.push(["link errors", `${s.linkErrors} since boot`, 1]);
                            return rows;
                        }
                    }
                }

                // iGPU.
                Section {
                    name: "igpu"

                    Head {
                        title: "iGPU"
                        sub: root.s.igpuName ?? ""
                        temp: root.temp(root.s.igpuTemp)
                        heat: Sensors.heat("igpu", root.s.igpuTemp)
                    }

                    Row {
                        width: parent.width
                        spacing: 12

                        Row {
                            id: igpuRings

                            spacing: 8

                            Ring {
                                value: root.s.igpuLoad ?? null
                                label: "load"
                            }

                            Ring {
                                value: root.percent(root.s.igpuVramUsed, root.s.igpuVramTotal)
                                label: "vram"
                            }
                        }

                        Pairs {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - igpuRings.width - 12
                            rows: [["vram", root.gibPair(root.s.igpuVramUsed, root.s.igpuVramTotal)], ["clock", root.known(root.s.igpuClock) ? `${Math.round(root.s.igpuClock)} MHz` : "–"], ["voltage", root.known(root.s.igpuVolt) ? `${root.s.igpuVolt.toFixed(2)} V` : "–"]]
                        }
                    }

                    Pairs {
                        visible: root.details && root.current === 3
                        width: parent.width
                        rows: [["northbridge", root.known(root.s.igpuVoltNb) ? `${root.s.igpuVoltNb.toFixed(2)} V` : "–"], ["drives", (root.s.igpuDriving ?? []).join(", ") || "no display"]]
                    }
                }

                // Storage and network.
                Section {
                    name: "storage"

                    Head {
                        title: "Storage and network"
                        sub: root.known(root.s.nvmeSize) ? `NVMe ${Math.round(root.s.nvmeSize / 1e12)} TB` : "NVMe"
                        temp: root.temp(root.s.nvmeTemp)
                        heat: Sensors.heat("nvme", root.s.nvmeTemp)
                    }

                    Repeater {
                        model: root.s.volumes ?? []

                        BarRow {
                            required property var modelData

                            label: modelData.target.startsWith("/mnt/") ? modelData.target.slice(5) : modelData.target
                            value: root.percent(modelData.used, modelData.size)
                            text: D.diskPair(modelData.used, modelData.size)
                        }
                    }

                    Pairs {
                        width: parent.width
                        rows: [["disk", root.known(root.s.readBps) ? `read ${D.rate(root.s.readBps)} · write ${D.rate(root.s.writeBps)}` : "–"], ["network", root.known(root.s.rxBps) ? `↓ ${D.rate(root.s.rxBps)} · ↑ ${D.rate(root.s.txBps)}` : "–"]]
                    }

                    Pairs {
                        visible: root.details && root.current === 4
                        width: parent.width
                        rows: [["disk busy", root.known(root.s.diskBusy) ? `${Math.round(root.s.diskBusy)}%` : "–"], ["uplink", root.s.uplink || "none"]]
                    }
                }

                KeyHints {
                    keys: root.details ? [["↑↓", "section"], ["Enter", "close details"], ["Esc", "back"]] : [["↑↓", "section"], ["Enter", "details"], ["Esc", "close"]]
                }
            }
        }
    }
}
