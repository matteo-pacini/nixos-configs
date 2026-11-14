import QtQuick
import QtQuick.Shapes
import qs

// A speed gauge: a 240 degree arc, linear from 0 to `full` Mb/s. A value
// above `full` fills the arc and still shows its own number. A change of
// `full` eases the arc to the new scale and fades the tick labels in.
Item {
    id: root

    required property string label
    // The colour of a finished reading.
    required property color doneColor
    required property real full
    // NaN while there is no reading.
    property real value: NaN
    property bool active: false

    // The mockup's 120 x 96 SVG, scaled.
    readonly property real s: 1.4
    readonly property real cx: 60 * s
    readonly property real cy: 58 * s
    readonly property real r: 44 * s
    readonly property bool hasValue: !isNaN(value)
    // What the arc and the number show: eases toward each new reading, and
    // back to 0 when the reading is cleared.
    property real shown: hasValue ? value : 0
    property real shownFull: full
    property color arcColor: active ? Theme.cyan : doneColor

    Behavior on shownFull {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    Behavior on shown {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutCubic
        }
    }

    Behavior on arcColor {
        ColorAnimation {
            duration: 300
        }
    }

    implicitWidth: 120 * s
    implicitHeight: 96 * s + caption.implicitHeight - 4

    Shape {
        width: 120 * root.s
        height: 96 * root.s
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.currentLine
            strokeWidth: 9 * root.s
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.r
                radiusY: root.r
                startAngle: 150
                sweepAngle: 240
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.arcColor
            strokeWidth: 9 * root.s
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.r
                radiusY: root.r
                startAngle: 150
                sweepAngle: 240 * Math.min(Math.max(root.shown, 0), root.shownFull) / root.shownFull
            }
        }
    }

    Item {
        id: ticks

        anchors.fill: parent

        NumberAnimation {
            id: tickFade

            target: ticks
            property: "opacity"
            from: 0
            to: 1
            duration: 450
            easing.type: Easing.OutCubic
        }

        Connections {
            target: root

            function onFullChanged() {
                tickFade.restart();
            }
        }

        Repeater {
            model: 5

            Text {
                required property int index
                readonly property real tick: root.full * index / 4
                readonly property real angle: (150 + 240 * index / 4) * Math.PI / 180

                x: root.cx + (root.r - 12 * root.s) * Math.cos(angle) - width / 2
                y: root.cy + (root.r - 12 * root.s) * Math.sin(angle) - height / 2
                // Thousands as "k" only where that stays short: whole
                // thousands, and the top of the scale (2.5k).
                text: tick >= 1000 && (tick % 1000 === 0 || index === 4) ? `${tick / 1000}k` : String(Math.round(tick * 10) / 10)
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: Math.round(8 * root.s)
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.left
        anchors.horizontalCenterOffset: root.cx
        anchors.baseline: parent.top
        anchors.baselineOffset: root.cy + 8 * root.s
        text: root.hasValue || root.shown >= 0.5 ? String(Math.round(root.shown)) : "–"
        color: root.hasValue || root.shown >= 0.5 ? Theme.foreground : Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: Math.round(25 * root.s)
        font.weight: Font.DemiBold
    }

    Text {
        anchors.horizontalCenter: parent.left
        anchors.horizontalCenterOffset: root.cx
        anchors.baseline: parent.top
        anchors.baselineOffset: root.cy + 22 * root.s
        text: "Mb/s"
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: Math.round(9 * root.s)
    }

    Text {
        id: caption

        anchors.horizontalCenter: parent.horizontalCenter
        y: 96 * root.s - 4
        text: root.label.toUpperCase() + (root.active ? " · MEASURING" : "")
        color: root.active ? Theme.cyan : Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.88

        Behavior on color {
            ColorAnimation {
                duration: 300
            }
        }
    }
}
