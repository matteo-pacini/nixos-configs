import QtQuick
import QtQuick.Shapes
import qs
import qs.common

// The desk's hardware stack from the front: a Magni 2 amplifier on a Modi 2
// converter. The Magni is analog and always drawn the same; `modi` is
// "play" (cyan light), "idle" (white light) or "off" (dashed and dim).
Item {
    id: root

    property string modi: "idle"

    // Anodised aluminium and recessed plastic, not palette colours: they
    // draw the hardware's own finish.
    readonly property color metal: "#3b3e4f"
    readonly property color metalHigh: "#565a70"
    readonly property color recess: "#2a2c39"
    readonly property color hole: "#191a21"
    readonly property color holeDeep: "#0f1015"
    readonly property color soft: Style.soft

    implicitWidth: 116
    implicitHeight: Math.round(implicitWidth * 126 / 200)

    component Circle: Rectangle {
        property real cx
        property real cy
        property real r

        x: cx - r
        y: cy - r
        width: 2 * r
        height: 2 * r
        radius: r
        antialiasing: true
    }

    component Label: Text {
        property real textBase

        x: 58
        y: textBase - baselineOffset
        color: root.soft
        font.family: Theme.fontMono
        font.pixelSize: 9
        font.letterSpacing: 1.5
    }

    // One box of the stack, its top edge at `edge`, in the 200 x 126 drawing.
    component Unit: Item {
        id: unit

        property real edge
        property bool dashed: false

        anchors.fill: parent

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.metal
                strokeColor: Theme.comment
                strokeWidth: 1.2
                strokeStyle: unit.dashed ? ShapePath.DashLine : ShapePath.SolidLine
                // In stroke widths: 4 and 3 drawing units.
                dashPattern: [4 / 1.2, 3 / 1.2]

                PathRectangle {
                    x: 8
                    y: unit.edge
                    width: 184
                    height: 50
                    radius: 5
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.metalHigh
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                startX: 13
                startY: unit.edge + 4.5

                PathLine {
                    x: 187
                    y: unit.edge + 4.5
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.recess
                strokeWidth: 1.5
                capStyle: ShapePath.RoundCap
                startX: 13
                startY: unit.edge + 45.5

                PathLine {
                    x: 187
                    y: unit.edge + 45.5
                }
            }
        }
    }

    Item {
        width: 200
        height: 126
        scale: root.width / 200
        transformOrigin: Item.TopLeft

        Item {
            anchors.fill: parent

            Unit {
                edge: 6
            }

            Circle {
                cx: 32
                cy: 31
                r: 8.5
                color: root.hole
                border.width: 1.2
                border.color: Theme.comment
            }

            Circle {
                cx: 32
                cy: 31
                r: 3.4
                color: root.holeDeep
            }

            Label {
                textBase: 34
                text: "MAGNI 2"
            }

            Circle {
                cx: 122
                cy: 31
                r: 2.2
                color: "transparent"
                border.width: 1
                border.color: root.soft
            }

            Circle {
                cx: 160
                cy: 31
                r: 16
                color: root.recess
                border.width: 1.2
                border.color: root.soft
            }

            Circle {
                cx: 160
                cy: 31
                r: 11.5
                color: root.metalHigh
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.foreground
                    strokeWidth: 2
                    capStyle: ShapePath.RoundCap
                    startX: 160
                    startY: 31

                    PathLine {
                        x: 152.5
                        y: 22.5
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: root.modi === "off" ? 0.38 : 1

            Unit {
                edge: 62
                dashed: root.modi === "off"
            }

            Circle {
                visible: root.modi === "play"
                cx: 32
                cy: 87
                r: 7
                color: Theme.cyan
                opacity: 0.22
            }

            Circle {
                cx: 32
                cy: 87
                r: 2.6
                color: root.modi === "play" ? Theme.cyan : root.modi === "off" ? "transparent" : Theme.foreground
                border.width: root.modi === "off" ? 1 : 0
                border.color: Theme.comment
            }

            Label {
                textBase: 90
                text: "MODI 2"
            }
        }

        Rectangle {
            x: 24
            y: 112
            width: 18
            height: 4
            radius: 1.5
            color: root.recess
        }

        Rectangle {
            x: 158
            y: 112
            width: 18
            height: 4
            radius: 1.5
            color: root.recess
        }
    }
}
