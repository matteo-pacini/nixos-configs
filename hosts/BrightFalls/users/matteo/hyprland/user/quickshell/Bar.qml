import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

// The top bar, one per monitor. It reserves its height, and steps aside on a
// monitor whose active workspace has a fullscreen window.
Scope {
    id: root

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            menu: "\u{f035c}",
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
    readonly property int fontSize: 12
    readonly property int iconSize: 14
    readonly property int gap: 12
    // The mockup's "soft" text colour, between foreground and comment.
    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))

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

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter !== null && adapter.enabled
    readonly property bool bluetoothConnected: bluetoothOn && adapter.devices.values.some(d => d.connected)

    // A hover highlight behind a clickable item.
    component Hover: Rectangle {
        property bool hovered

        anchors.centerIn: parent
        width: parent.width + 8
        height: 22
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

            // 1 to 5, and any other existing normal workspace (named and
            // special ones have ids below 1).
            readonly property var workspaceIds: {
                const ids = new Set([1, 2, 3, 4, 5]);
                for (const w of Hyprland.workspaces.values)
                    if (w.id > 0)
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
                top: 6
                left: 6
                right: 6
            }
            implicitHeight: 30
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
                radius: 10
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
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

                                width: 20
                                height: 20
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

                Text {
                    id: clock

                    anchors.centerIn: parent
                    text: Qt.formatDateTime(systemClock.date, "dddd HH:mm")
                    color: Theme.foreground
                    font.family: Theme.fontMono
                    font.pixelSize: root.fontSize

                    SystemClock {
                        id: systemClock

                        precision: SystemClock.Minutes
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

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.bluetoothConnected ? root.glyph.bluetoothConnected : root.bluetoothOn ? root.glyph.bluetooth : root.glyph.bluetoothOff
                        color: root.bluetoothOn ? Theme.foreground : Theme.comment
                    }

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wired ? root.glyph.ethernet : root.wireless ? root.glyph.wifi : root.glyph.noNetwork
                        color: root.offline ? Theme.red : Theme.foreground
                    }

                    Item {
                        id: audio

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

                        Hover {
                            hovered: audioArea.containsMouse
                        }

                        Row {
                            id: audioRow

                            height: parent.height
                            spacing: 6

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: audio.muted || audio.volume === 0 ? root.glyph.volumeMuted : audio.volume < 0.34 ? root.glyph.volumeLow : audio.volume < 0.67 ? root.glyph.volumeMedium : root.glyph.volumeHigh
                                color: audio.muted ? Theme.comment : Theme.foreground
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 140)
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
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
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
