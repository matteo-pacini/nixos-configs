import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.bluetooth
import qs.common

// The volume OSD: a pill under the bar on the focused monitor. Shows on a
// change to the default output's volume, mute or device, to the default
// input's mute, or to Bluetooth power from its bind, and hides 1.2 s after
// the last change. Clicks pass through.
Scope {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // A node's first values after it binds, at startup, on a reload or when
    // it becomes the default, are not changes. Its signals count only once it
    // has been the default for a settle period with nothing pending.
    property PwNode armedSink: null
    property PwNode armedSource: null
    property int lastSinkId: -1

    property bool shown: false
    property string glyph: ""
    property real level: 0
    property bool muted: false
    // Non-empty shows this name in place of the track and percentage.
    property string device: ""

    function show() {
        if (!window.visible) {
            const name = Hyprland.focusedMonitor?.name;
            window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
        }
        shown = true;
        hide.restart();
    }

    function showVolume(node, isSink) {
        const volume = node.audio.volume;
        muted = node.audio.muted;
        level = volume;
        // Nerd Font Material Design: volume off/low/medium/high, mic, mic off.
        if (!isSink)
            glyph = muted ? "\u{f036d}" : "\u{f036c}";
        else if (muted || volume <= 0)
            glyph = "\u{f0581}";
        else
            glyph = volume < 1 / 3 ? "\u{f057f}" : volume < 2 / 3 ? "\u{f0580}" : "\u{f057e}";
        device = "";
        show();
    }

    onSinkChanged: {
        armedSink = null;
        settle.restart();
        // The default may briefly be null while it changes; compare against
        // the last real one so that does not count as a change.
        if (sink === null)
            return;
        if (lastSinkId >= 0 && sink.id !== lastSinkId && Pipewire.ready) {
            glyph = "\u{f04c3}";
            device = sink.description || sink.nickname || sink.name;
            show();
        }
        lastSinkId = sink.id;
    }

    onSourceChanged: {
        armedSource = null;
        settle.restart();
    }

    Component.onCompleted: settle.start()

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Timer {
        id: settle

        interval: 1000
        onTriggered: {
            if (root.sink?.ready)
                root.armedSink = root.sink;
            if (root.source?.ready)
                root.armedSource = root.source;
        }
    }

    // Binding a node finishes after it becomes the default; restart the
    // settle period so its first values land before it is armed.
    Connections {
        target: root.sink
        function onReadyChanged() {
            settle.restart();
        }
    }

    Connections {
        target: root.source
        function onReadyChanged() {
            settle.restart();
        }
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumesChanged() {
            if (root.sink === root.armedSink)
                root.showVolume(root.sink, true);
        }
        function onMutedChanged() {
            if (root.sink === root.armedSink)
                root.showVolume(root.sink, true);
        }
    }

    // Bluetooth on or off from its bind (BluetoothPanel.qml).
    Connections {
        target: BluetoothShared

        function onAnnounce(text) {
            root.glyph = text === "Bluetooth on" ? "\u{f00af}" : "\u{f00b2}";
            root.device = text;
            root.show();
        }
    }

    Connections {
        target: root.source?.audio ?? null
        function onMutedChanged() {
            if (root.source === root.armedSource)
                root.showVolume(root.source, false);
        }
    }

    Timer {
        id: hide

        interval: 1200
        onTriggered: root.shown = false
    }

    PanelWindow {
        id: window

        // Room around the pill for its shadow; the window starts above y = 44
        // so the pill itself sits there.
        readonly property int pad: 44
        readonly property int padTop: 20

        visible: root.shown || pill.opacity > 0
        color: "transparent"
        anchors.top: true
        margins.top: 44 - padTop
        implicitWidth: pill.width + 2 * pad
        implicitHeight: pill.height + padTop + pad
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "desk-osd"
        // An empty region: no part of the window takes pointer input.
        mask: Region {}

        RectangularShadow {
            anchors.fill: pill
            radius: pill.radius
            offset.y: 12
            blur: 34
            color: Qt.rgba(0, 0, 0, 0.5)
            opacity: pill.opacity
        }

        Rectangle {
            id: pill

            x: window.pad
            y: window.padTop
            width: row.implicitWidth + 28 + 2
            height: row.implicitHeight + 14 + 2
            radius: height / 2
            color: Style.surface
            border.width: 1
            border.color: Theme.purple
            opacity: root.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyph
                    color: Theme.purple
                    font.family: Theme.fontMono
                    font.pixelSize: 16
                }

                Rectangle {
                    visible: root.device === ""
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    height: 4
                    radius: 2
                    color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.2)

                    Rectangle {
                        width: root.muted ? 0 : parent.width * Math.min(root.level, 1)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.purple

                        Behavior on width {
                            NumberAnimation {
                                duration: 140
                            }
                        }
                    }
                }

                // FiraCode is monospaced, so its digits are already tabular.
                Text {
                    visible: root.device === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.level * 100) + "%"
                    color: root.muted ? Theme.comment : Theme.foreground
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: root.device !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.device
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }
    }
}
