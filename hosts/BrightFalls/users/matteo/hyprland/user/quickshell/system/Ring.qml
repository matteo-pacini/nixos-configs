import QtQuick
import QtQuick.Shapes
import qs

// A percentage ring with its figure inside and a label under it. `value`
// 0..100, or null for not known yet (an empty ring and a dash). Purple,
// pink from 90%.
Column {
    id: root

    property var value: null
    property string label
    property string centre: value === null ? "–" : Math.round(value) + "%"

    readonly property real fraction: value === null ? 0 : Math.max(0, Math.min(1, value / 100))

    width: 66
    spacing: 1

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 62
        height: 62

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.darker(Theme.background, 1.5)
                strokeWidth: 6

                PathAngleArc {
                    centerX: 31
                    centerY: 31
                    radiusX: 25
                    radiusY: 25
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.value !== null && root.value >= 90 ? Theme.pink : Theme.purple
                strokeWidth: root.fraction > 0.005 ? 6 : 0
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: 31
                    centerY: 31
                    radiusX: 25
                    radiusY: 25
                    startAngle: -90
                    sweepAngle: 360 * root.fraction
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.centre
            color: Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label.toUpperCase()
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 10
        font.letterSpacing: 0.6
    }
}
