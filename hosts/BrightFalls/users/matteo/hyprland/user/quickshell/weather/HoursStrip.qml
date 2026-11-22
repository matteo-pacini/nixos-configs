import QtQuick
import QtQuick.Shapes
import qs
import qs.common

// The next hours, 392 × 112: per column the hour's label, its art, the
// temperature on a curve and a bar for the precipitation. `hours` is up to
// 8 of {label, art, tempText, temp, precip, precipText, now}: `art` a
// ConditionArt kind, `temp` in °C, `precip` in mm (0 draws an empty track),
// `now` true draws that label brighter. Bars scale to the wettest hour, or
// to 2.5 mm if none is wetter.
Item {
    id: root

    property var hours: []

    readonly property real columnWidth: width / 8
    readonly property real low: Math.min(...hours.map(h => h.temp))
    readonly property real high: Math.max(...hours.map(h => h.temp))
    readonly property real wettest: Math.max(2.5, ...hours.map(h => h.precip))

    function cx(i) {
        return columnWidth * (i + 0.5);
    }

    function cy(temp) {
        return 70 - (temp - low) / (high - low || 1) * 14;
    }

    readonly property string curve: hours.map((h, i) => (i ? "L" : "M") + cx(i) + " " + cy(h.temp)).join(" ")

    implicitWidth: 392
    implicitHeight: 112

    Shape {
        anchors.fill: parent
        visible: root.hours.length > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.rgba(Theme.orange.r, Theme.orange.g, Theme.orange.b, 0.07)

            PathSvg {
                path: root.hours.length ? `${root.curve} L${root.cx(root.hours.length - 1)} 84 L${root.cx(0)} 84 Z` : ""
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.orange
            strokeWidth: 2
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: root.curve
            }
        }
    }

    Repeater {
        model: root.hours

        Item {
            id: column

            required property var modelData
            required property int index

            readonly property real mid: root.cx(index)
            readonly property real dotY: root.cy(modelData.temp)
            readonly property real bar: Math.max(2, modelData.precip / root.wettest * 14)

            anchors.fill: parent

            Text {
                x: column.mid - implicitWidth / 2
                y: 11 - baselineOffset
                text: column.modelData.label
                textFormat: Text.PlainText
                color: column.modelData.now ? Theme.foreground : Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            ConditionArt {
                x: column.mid - 11
                y: 16
                kind: column.modelData.art
                size: 22
            }

            Rectangle {
                x: column.mid - 2.6
                y: column.dotY - 2.6
                width: 5.2
                height: 5.2
                radius: 2.6
                antialiasing: true
                color: Theme.background
                border.width: 1.6
                border.color: Theme.orange
            }

            Text {
                x: column.mid - implicitWidth / 2
                y: column.dotY - 7 - baselineOffset
                text: column.modelData.tempText
                textFormat: Text.PlainText
                color: Theme.foreground
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Rectangle {
                x: column.mid - 9
                y: column.modelData.precip > 0 ? 98 - column.bar : 96
                width: 18
                height: column.modelData.precip > 0 ? column.bar : 2
                radius: column.modelData.precip > 0 ? 2 : 1
                color: column.modelData.precip > 0 ? Theme.cyan : Style.track
                opacity: column.modelData.precip > 0 ? 0.75 : 1
            }

            Text {
                visible: column.modelData.precip > 0
                x: column.mid - implicitWidth / 2
                y: 110 - baselineOffset
                text: column.modelData.precipText
                textFormat: Text.PlainText
                color: Theme.cyan
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }
    }
}
