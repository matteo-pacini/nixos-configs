import QtQuick
import QtQuick.Shapes
import qs
import qs.common

// The OUTDOOR SENSOR section, the panel's width: a battery icon and its
// percent, link bars and their figure, and on the right when the sensor was
// heard. `battery` is null (left out) or {text, tone, fill 0..1}; `link` null
// or {text, tone, bars 1..4}; a non-empty `message` is drawn in place of both.
// Tones are weather.js's names: "red", "orange", "yellow", "green", "dim",
// anything else the panel's soft text colour.
Item {
    id: root

    property var battery: null
    property var link: null
    property string message
    property string messageTone: "dim"
    property string heard
    property string heardTone: "dim"

    function tone(name: string): color {
        switch (name) {
        case "red":
            return Theme.red;
        case "orange":
            return Theme.orange;
        case "yellow":
            return Theme.yellow;
        case "green":
            return Theme.green;
        case "dim":
            return Theme.comment;
        default:
            return Style.soft;
        }
    }

    readonly property color batteryColor: battery ? tone(battery.tone) : Style.soft
    readonly property color linkColor: link ? tone(link.tone) : Style.soft

    width: parent ? parent.width : 0
    implicitHeight: header.height + line.height

    SectionLine {
        id: header

        title: "OUTDOOR SENSOR"
    }

    Item {
        id: line

        y: header.height
        width: parent.width
        height: Math.max(figures.height, heardText.implicitHeight) + 2 + 6

        Row {
            id: figures

            x: 14
            y: 2 + (line.height - 8 - height) / 2
            spacing: 26

            Text {
                visible: root.message !== ""
                text: root.message
                textFormat: Text.PlainText
                color: root.tone(root.messageTone)
                font.family: Theme.fontMono
                font.pixelSize: 12
            }

            Row {
                visible: root.message === "" && root.battery !== null
                spacing: 5

                // 20 × 11: the case, the terminal nub, the charge.
                Shape {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 11
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root.batteryColor
                        strokeWidth: 1.5

                        PathRectangle {
                            x: 0.75
                            y: 0.75
                            width: 16
                            height: 9.5
                            radius: 2.2
                        }
                    }

                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: root.batteryColor

                        PathRectangle {
                            x: 18
                            y: 3.5
                            width: 1.6
                            height: 4
                            radius: 0.8
                        }
                    }

                    // An empty battery draws no charge, not a sliver.
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: root.battery && root.battery.fill > 0 ? root.batteryColor : "transparent"

                        PathRectangle {
                            x: 2.6
                            y: 2.6
                            width: root.battery && root.battery.fill > 0 ? Math.max(1.5, 12.3 * root.battery.fill) : 0
                            height: 5.8
                            radius: 1
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.battery ? root.battery.text : ""
                    textFormat: Text.PlainText
                    color: root.batteryColor
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }
            }

            Row {
                visible: root.message === "" && root.link !== null
                spacing: 5

                // 15 × 11: four rising bars, the unlit ones faint.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15
                    height: 11

                    Repeater {
                        model: 4

                        Shape {
                            id: bar

                            required property int index

                            width: 15
                            height: 11
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: "transparent"
                                fillColor: Qt.rgba(root.linkColor.r, root.linkColor.g, root.linkColor.b, root.link && bar.index < root.link.bars ? 1 : 0.28)

                                PathRectangle {
                                    x: bar.index * 4
                                    y: 9 - bar.index * 2.6
                                    width: 2.6
                                    height: 2 + bar.index * 2.6
                                    radius: 0.8
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.link ? root.link.text : ""
                    textFormat: Text.PlainText
                    color: root.linkColor
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }
            }
        }

        Text {
            id: heardText

            x: parent.width - 14 - width
            y: 2
            width: Math.min(implicitWidth, parent.width - 28 - figures.width - 16)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            text: root.heard
            textFormat: Text.PlainText
            color: root.tone(root.heardTone)
            font.family: Theme.fontMono
            font.pixelSize: 12
        }
    }
}
