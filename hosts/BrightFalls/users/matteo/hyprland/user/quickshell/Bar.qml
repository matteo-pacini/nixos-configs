import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import qs.audio
import qs.bluetooth
import qs.calendar
import qs.common
import qs.network
import qs.system

// The top bar, one per monitor. It reserves its height, and steps aside on a
// monitor whose active workspace has a fullscreen window.
Scope {
    id: root

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            menu: "\u{f035c}",
            chip: "\u{f061a}",
            gamepad: "\u{f0297}",
            bluetooth: "\u{f00af}",
            bluetoothConnected: "\u{f00b1}",
            bluetoothOff: "\u{f00b2}",
            ethernet: "\u{f0200}",
            wifi: "\u{f05a9}",
            noNetwork: "\u{f0319}",
            volumeHigh: "\u{f057e}",
            volumeMedium: "\u{f0580}",
            volumeLow: "\u{f057f}",
            volumeMuted: "\u{f0581}"
        })
    readonly property int fontSize: 16
    readonly property int iconSize: 18
    readonly property int gap: 12
    // Each monitor's own workspaces. Must match the workspace rules in
    // hypr/monitors.lua.
    readonly property var workspaceMonitors: ({
            "DP-1": [1, 2, 3, 4, 5],
            "DP-2": [6, 7, 8, 9, 10]
        })
    readonly property color soft: Style.soft

    // Game mode (Super+Ctrl+G in hypr/bindings.lua) is the only thing that
    // turns animations off, and it always removes or re-adds DP-2 or reloads
    // the config, so the option is re-read on those events only.
    property bool gameMode: false

    Process {
        id: gameModeQuery

        command: ["hyprctl", "-j", "getoption", "animations:enabled"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.gameMode = JSON.parse(text).bool === false;
                } catch (e) {
                    console.warn("bar: hyprctl getoption:", e.message);
                }
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (["configreloaded", "monitorremoved", "monitoraddedv2"].includes(event.name))
                gameModeQuery.running = true;
        }
    }

    Component.onCompleted: gameModeQuery.running = true

    readonly property PwNode sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [root.sink]
    }

    readonly property var networkDevices: Networking.devices.values
    readonly property bool wired: networkDevices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool wireless: networkDevices.some(d => d.type === DeviceType.Wifi && d.connected)
    // Unknown means NetworkManager's check is off or has not run, not that
    // the host is offline.
    readonly property bool offline: !(wired || wireless) || [NetworkConnectivity.None, NetworkConnectivity.Portal, NetworkConnectivity.Limited].includes(Networking.connectivity)

    readonly property bool bluetoothOn: Bt.on
    readonly property bool bluetoothConnected: bluetoothOn && Bt.devices.some(d => d.connected)

    // A hover highlight behind a clickable item.
    component Hover: Rectangle {
        property bool hovered

        anchors.centerIn: parent
        width: parent.width + 8
        height: 26
        radius: 5
        color: Theme.currentLine
        visible: hovered
    }

    component Glyph: Text {
        color: Theme.foreground
        font.family: Theme.fontMono
        font.pixelSize: root.iconSize
        verticalAlignment: Text.AlignVCenter
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar

            required property ShellScreen modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property HyprlandWorkspace activeWorkspace: monitor?.activeWorkspace ?? null

            // Kept so the title stays when focus moves to another monitor.
            property HyprlandToplevel lastWindow: null
            // Until focus has been on this monitor, Hyprland's own record of
            // the workspace's last window. That record is refreshed only on
            // some events, so it is the fallback, not the source.
            readonly property HyprlandToplevel shownWindow: lastWindow && lastWindow.workspace === activeWorkspace ? lastWindow : activeWorkspace?.toplevels.values.find(t => "0x" + t.address === activeWorkspace.lastIpcObject.lastwindow) ?? null
            readonly property string title: shownWindow?.title ?? ""

            // This monitor's own workspaces, and any other existing normal
            // workspace on it (named and special ones have ids below 1).
            readonly property var workspaceIds: {
                const ids = new Set(root.workspaceMonitors[modelData.name] ?? []);
                for (const w of Hyprland.workspaces.values)
                    if (w.id > 0 && w.monitor === monitor)
                        ids.add(w.id);
                return Array.from(ids).sort((a, b) => a - b);
            }

            function focusWorkspace(id) {
                Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
            }

            screen: modelData
            visible: !(activeWorkspace?.hasFullscreen ?? false)
            color: "transparent"
            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: Style.barMargin
                left: Style.barMargin
                right: Style.barMargin
            }
            implicitHeight: Style.barHeight
            WlrLayershell.namespace: "desk-bar"

            Connections {
                target: Hyprland

                function onActiveToplevelChanged() {
                    const window = Hyprland.activeToplevel;
                    if (window && window.monitor === bar.monitor)
                        bar.lastWindow = window;
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Style.radius
                color: Style.surface
                border.width: 1
                border.color: Theme.purple

                Row {
                    id: left

                    x: 13
                    height: parent.height
                    spacing: root.gap

                    Item {
                        width: menuGlyph.implicitWidth
                        height: parent.height

                        Hover {
                            hovered: menuArea.containsMouse
                        }

                        Glyph {
                            id: menuGlyph

                            anchors.centerIn: parent
                            text: root.glyph.menu
                            color: Theme.purple
                        }

                        MouseArea {
                            id: menuArea

                            anchors.fill: parent
                            hoverEnabled: true
                            // Launcher.qml takes its toggle over IPC only;
                            // --pid sends it to this process.
                            onClicked: Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "launcher", "toggle"])
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Repeater {
                            model: bar.workspaceIds

                            Rectangle {
                                id: button

                                required property int modelData
                                readonly property HyprlandWorkspace workspace: Hyprland.workspaces.values.find(w => w.id === modelData) ?? null
                                readonly property bool active: workspace !== null && workspace === bar.activeWorkspace
                                readonly property bool occupied: (workspace?.toplevels.values.length ?? 0) > 0

                                width: 24
                                height: 24
                                radius: 5
                                color: active ? Theme.purple : buttonArea.containsMouse ? Theme.currentLine : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: button.modelData
                                    color: button.active ? Theme.background : Theme.foreground
                                    opacity: button.active || button.occupied ? 1 : 0.45
                                    font.family: Theme.fontMono
                                    font.pixelSize: root.fontSize
                                    font.weight: button.active ? Font.DemiBold : Font.Normal
                                }

                                MouseArea {
                                    id: buttonArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: bar.focusWorkspace(button.modelData)
                                }
                            }
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const ids = bar.workspaceIds;
                                const at = ids.indexOf(bar.activeWorkspace?.id ?? -1);
                                if (at < 0 || event.angleDelta.y === 0)
                                    return;
                                const next = at + (event.angleDelta.y > 0 ? -1 : 1);
                                if (next >= 0 && next < ids.length)
                                    bar.focusWorkspace(ids[next]);
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, Math.min(implicitWidth, clock.x - root.gap - left.x - x))
                        text: bar.title
                        elide: Text.ElideRight
                        color: root.soft
                        font.family: Theme.fontMono
                        font.pixelSize: root.fontSize
                    }
                }

                // Week dots (Monday first: gone filled, today large, to come
                // hollow), short date, the day ring filling clockwise from
                // midnight, the time, and the next-event hint.
                Item {
                    id: clock

                    readonly property date now: CalendarPanel.now
                    readonly property int weekday: (now.getDay() + 6) % 7
                    readonly property real dayFraction: (now.getHours() * 60 + now.getMinutes()) / 1440
                    readonly property bool panelOpen: CalendarPanel.screen === bar.modelData.name

                    anchors.centerIn: parent
                    width: clockRow.implicitWidth
                    height: parent.height

                    Component.onCompleted: Dropdowns.anchor("calendar", bar.modelData.name, clock, bar)

                    Hover {
                        hovered: clockArea.containsMouse
                    }

                    // Marks the item whose panel is open.
                    Rectangle {
                        visible: clock.panelOpen
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: 14
                        height: 2
                        radius: 1
                        color: Theme.purple
                    }

                    Row {
                        id: clockRow

                        height: parent.height
                        spacing: 10

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Repeater {
                                model: 7

                                Rectangle {
                                    required property int index
                                    readonly property bool today: index === clock.weekday

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: today ? 8 : 6
                                    height: width
                                    radius: width / 2
                                    color: today ? Theme.purple : index < clock.weekday ? Theme.comment : "transparent"
                                    border.width: 1
                                    border.color: today ? Theme.purple : Theme.comment
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDateTime(clock.now, "ddd d")
                            color: root.soft
                            font.family: Theme.fontMono
                            font.pixelSize: root.fontSize
                        }

                        Canvas {
                            id: ring

                            readonly property real fraction: clock.dayFraction
                            readonly property color track: Style.track
                            readonly property color fill: Theme.pink

                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            onFractionChanged: requestPaint()
                            onTrackChanged: requestPaint()
                            onFillChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.lineWidth = 3.5;
                                ctx.strokeStyle = track;
                                ctx.beginPath();
                                ctx.arc(12, 12, 9, 0, 2 * Math.PI);
                                ctx.stroke();
                                if (fraction <= 0)
                                    return;
                                ctx.strokeStyle = fill;
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.arc(12, 12, 9, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * fraction);
                                ctx.stroke();
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDateTime(clock.now, "HH:mm")
                            color: clock.panelOpen ? Theme.purple : Theme.foreground
                            font.family: Theme.fontMono
                            font.pixelSize: root.fontSize
                            font.weight: Font.DemiBold
                        }

                        Text {
                            visible: CalendarPanel.hint !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: CalendarPanel.hint
                            color: Theme.cyan
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: clockArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: CalendarPanel.toggleRequested(bar.modelData.name)
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 13
                    height: parent.height
                    spacing: root.gap

                    Glyph {
                        visible: root.gameMode
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.glyph.gamepad
                        color: Theme.green
                    }

                    Row {
                        visible: SystemTray.items.values.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Repeater {
                            model: SystemTray.items

                            Item {
                                id: trayItem

                                required property SystemTrayItem modelData

                                function showMenu() {
                                    const p = mapToItem(null, 0, height);
                                    modelData.display(bar, Math.round(p.x), Math.round(p.y) + 6);
                                }

                                width: root.iconSize
                                height: root.iconSize

                                Hover {
                                    hovered: trayArea.containsMouse
                                }

                                IconImage {
                                    anchors.fill: parent
                                    source: trayItem.modelData.icon
                                }

                                MouseArea {
                                    id: trayArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        const item = trayItem.modelData;
                                        if (mouse.button === Qt.RightButton || item.onlyMenu) {
                                            if (item.hasMenu)
                                                trayItem.showMenu();
                                        } else {
                                            item.activate();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: system

                        readonly property bool panelOpen: SystemPanel.screen === bar.modelData.name
                        readonly property var s: Sensors.s
                        // CPU, then the eGPU's junction; one line per
                        // temperature. Each must be one Sensors reads while
                        // closed (level 0 sources).
                        readonly property var temps: [[s.cpuTemp, Sensors.heat("cpu", s.cpuTemp)], [s.egpuPresent && s.egpuAwake ? s.egpuJunction : null, Sensors.heat("junction", s.egpuJunction)]].filter(t => t[0] !== null && t[0] !== undefined)

                        width: systemRow.implicitWidth
                        height: parent.height

                        Component.onCompleted: Dropdowns.anchor("system", bar.modelData.name, system, bar)

                        Hover {
                            hovered: systemArea.containsMouse
                        }

                        // Marks the item whose panel is open.
                        Rectangle {
                            visible: system.panelOpen
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 14
                            height: 2
                            radius: 1
                            color: Theme.purple
                        }

                        Row {
                            id: systemRow

                            height: parent.height
                            spacing: 6

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.glyph.chip
                                color: system.panelOpen ? Theme.purple : Theme.foreground
                            }

                            Repeater {
                                model: system.temps

                                Text {
                                    required property var modelData

                                    anchors.verticalCenter: parent.verticalCenter
                                    text: `${Math.round(modelData[0])}°`
                                    color: modelData[1] === 2 ? Theme.red : modelData[1] === 1 ? Theme.orange : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: root.fontSize
                                }
                            }
                        }

                        MouseArea {
                            id: systemArea

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: SystemPanel.toggleRequested(bar.modelData.name)
                            onContainsMouseChanged: {
                                if (containsMouse)
                                    SystemPanel.hoverScreen = bar.modelData.name;
                                else if (SystemPanel.hoverScreen === bar.modelData.name)
                                    SystemPanel.hoverScreen = "";
                            }
                        }

                        Temperatures {
                            item: system
                            shown: SystemPanel.hoverScreen === bar.modelData.name && SystemPanel.screen === ""
                        }
                    }

                    Item {
                        id: bluetooth

                        readonly property bool panelOpen: Bt.screen === bar.modelData.name

                        width: bluetoothRow.implicitWidth
                        height: parent.height

                        Component.onCompleted: Dropdowns.anchor("bluetooth", bar.modelData.name, bluetooth, bar)

                        Hover {
                            hovered: bluetoothArea.containsMouse
                        }

                        // Marks the item whose panel is open.
                        Rectangle {
                            visible: bluetooth.panelOpen
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 14
                            height: 2
                            radius: 1
                            color: Theme.purple
                        }

                        Row {
                            id: bluetoothRow

                            height: parent.height
                            spacing: 5

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.bluetoothConnected ? root.glyph.bluetoothConnected : root.bluetoothOn ? root.glyph.bluetooth : root.glyph.bluetoothOff
                                color: !root.bluetoothOn ? Theme.comment : bluetooth.panelOpen ? Theme.purple : Theme.foreground
                            }

                            // A connected device's battery under 15%, the
                            // lowest if several.
                            Text {
                                visible: Bt.lowest >= 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Bt.lowest}%`
                                color: Theme.red
                                font.family: Theme.fontMono
                                font.pixelSize: root.fontSize
                            }
                        }

                        MouseArea {
                            id: bluetoothArea

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Bt.toggleRequested(bar.modelData.name)
                        }
                    }

                    Item {
                        id: network

                        readonly property bool panelOpen: Panel.screen === bar.modelData.name

                        width: networkGlyph.implicitWidth
                        height: parent.height

                        Component.onCompleted: Dropdowns.anchor("network", bar.modelData.name, network, bar)

                        Hover {
                            hovered: networkArea.containsMouse
                        }

                        Glyph {
                            id: networkGlyph

                            anchors.centerIn: parent
                            text: root.wired ? root.glyph.ethernet : root.wireless ? root.glyph.wifi : root.glyph.noNetwork
                            color: root.offline ? Theme.red : network.panelOpen ? Theme.purple : Theme.foreground
                        }

                        // Marks the icon whose panel is open.
                        Rectangle {
                            visible: network.panelOpen
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 14
                            height: 2
                            radius: 1
                            color: Theme.purple
                        }

                        MouseArea {
                            id: networkArea

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: Panel.toggleRequested(bar.modelData.name)
                        }
                    }

                    Item {
                        id: audio

                        readonly property bool panelOpen: AudioPanel.screen === bar.modelData.name
                        readonly property PwNodeAudio pw: root.sink?.audio ?? null
                        readonly property bool muted: pw?.muted ?? true
                        readonly property real volume: pw?.volume ?? 0
                        // "Modi 2 (Atmos)" -> "Atmos": the sinks differ only
                        // in the bracketed part.
                        readonly property string name: {
                            const description = root.sink?.description || root.sink?.nickname || root.sink?.name || "";
                            return description.match(/\(([^)]+)\)\s*$/)?.[1] ?? description;
                        }

                        width: audioRow.implicitWidth
                        height: parent.height

                        Component.onCompleted: Dropdowns.anchor("audio", bar.modelData.name, audio, bar)

                        Hover {
                            hovered: audioArea.containsMouse
                        }

                        // Marks the item whose panel is open.
                        Rectangle {
                            visible: audio.panelOpen
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 14
                            height: 2
                            radius: 1
                            color: Theme.purple
                        }

                        Row {
                            id: audioRow

                            height: parent.height
                            spacing: 6

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: audio.muted || audio.volume === 0 ? root.glyph.volumeMuted : audio.volume < 0.34 ? root.glyph.volumeLow : audio.volume < 0.67 ? root.glyph.volumeMedium : root.glyph.volumeHigh
                                color: audio.muted ? Theme.comment : audio.panelOpen ? Theme.purple : Theme.foreground

                                // An input is attached but sends nothing
                                // (NoSignal); the audio panel says which.
                                Rectangle {
                                    visible: NoSignal.any
                                    x: parent.width - width / 2
                                    y: (parent.height - parent.contentHeight) / 2
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Theme.red
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 180)
                                text: audio.name
                                elide: Text.ElideRight
                                color: Theme.foreground
                                font.family: Theme.fontMono
                                font.pixelSize: root.fontSize
                            }
                        }

                        MouseArea {
                            id: audioArea

                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) {
                                    AudioPanel.toggleRequested(bar.modelData.name);
                                } else if (mouse.button === Qt.RightButton) {
                                    if (audio.pw)
                                        audio.pw.muted = !audio.pw.muted;
                                } else {
                                    Quickshell.execDetached(["audio-output-cycle"]);
                                }
                            }
                            onWheel: wheel => {
                                if (!audio.pw || wheel.angleDelta.y === 0)
                                    return;
                                // 0..1, the same cap as the volume keys' wpctl -l 1.
                                const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                audio.pw.volume = Math.max(0, Math.min(1, Math.round((audio.volume + step) * 100) / 100));
                            }
                        }
                    }
                }
            }
        }
    }
}
