import QtQuick
import Quickshell.Services.Pipewire
import qs

// A live level bar for one node: green for the level now, a mark for the
// recent peak (held 1.5 s), red while clipping. Levels are on Quickshell's
// visual scale (cube root of the sample peak), 0..1. Capture runs only
// while `active`; inactive, the bar is flat with no mark.
Rectangle {
    id: root

    required property PwNode node
    property bool active: true
    // Multiplies the monitor's reading. A playback stream's monitor reads
    // the signal before the stream's own volume (Quickshell divides it
    // out), so a program row passes its volume here.
    property real gain: 1

    readonly property real level: active ? monitor.peak * gain : 0
    property real held: 0
    // A level held at full scale changes no more, so clipping is the level
    // now or a recent one.
    property bool clippedLately: false
    readonly property bool clipping: level >= 0.99 || clippedLately

    width: parent.width
    height: 3
    radius: 2
    color: Qt.darker(Theme.background, 1.5)

    onLevelChanged: {
        if (level >= held) {
            held = level;
            holdTimer.restart();
        }
        // 0.99 on this scale is 97% of full scale.
        if (level >= 0.99) {
            clippedLately = true;
            clipTimer.restart();
        }
    }
    onActiveChanged: if (!active) {
        held = 0;
        clippedLately = false;
    }

    PwNodePeakMonitor {
        id: monitor

        node: root.node
        enabled: root.active
    }

    Timer {
        id: holdTimer

        interval: 1500
        onTriggered: root.held = root.level
    }

    Timer {
        id: clipTimer

        interval: 2000
        onTriggered: root.clippedLately = false
    }

    Rectangle {
        width: parent.width * Math.min(1, root.level)
        height: parent.height
        radius: 2
        color: Theme.green
    }

    Rectangle {
        visible: root.held > 0.01
        x: Math.min(parent.width - width, parent.width * Math.min(1, root.held))
        width: 2
        height: parent.height
        color: root.clipping ? Theme.red : Theme.yellow
    }
}
