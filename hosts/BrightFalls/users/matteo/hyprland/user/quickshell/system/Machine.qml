import QtQuick
import QtQuick.Shapes
import qs
import qs.common

// The machine from the front: the UM890 Pro, the OCuLink cable, and the DEG1
// dock with the three-fan RX 6800 XT lying on it. Absent (`egpu` false), the
// dock and card are dashed and dim and the cable dotted. Fans turn at `rpm`
// scaled down, only while `running`, and stand still at 0; `hot` gives the
// card the pink accents of high load.
Item {
    id: root

    property bool egpu: true
    property real rpm: 0
    property bool hot: false
    property bool running: false

    // Anodised aluminium and recessed plastic, not palette colours: they
    // draw the hardware's own finish (as in audio/Stack.qml).
    readonly property color metal: "#3b3e4f"
    readonly property color metalHigh: "#565a70"
    readonly property color dark: "#20222c"
    readonly property color soft: Style.soft

    property real angle: 0

    implicitWidth: 392
    implicitHeight: Math.round(implicitWidth * 128 / 392)

    // 20 steps a second, not every frame: each step redraws the panel's
    // whole-monitor window. At one turn per 3000 rpm a step stays under 20°
    // (half the 40° blade spacing) up to the card's 3300 rpm, so the blades
    // never appear to turn backwards.
    Timer {
        interval: 50
        running: root.running && root.egpu && root.rpm > 0
        repeat: true
        onTriggered: root.angle = (root.angle + root.rpm / 3000 * 360 * interval / 1000) % 360
    }

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

    component Box: Shape {
        id: box

        property real bx
        property real by
        property real bw
        property real bh
        property real br: 0
        property color fill
        property color stroke: "transparent"
        property real line: 1
        property bool dashed: false

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: box.fill
            strokeColor: box.stroke
            strokeWidth: box.line
            strokeStyle: box.dashed ? ShapePath.DashLine : ShapePath.SolidLine
            // In stroke widths: 4 and 3 drawing units.
            dashPattern: [4 / box.line, 3 / box.line]

            PathRectangle {
                x: box.bx
                y: box.by
                width: box.bw
                height: box.bh
                radius: box.br
            }
        }
    }

    component Rule: Shape {
        id: rule

        property real x1
        property real x2
        property real ry
        property color stroke

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: rule.stroke
            strokeWidth: 1.5
            capStyle: ShapePath.RoundCap
            startX: rule.x1
            startY: rule.ry

            PathLine {
                x: rule.x2
                y: rule.ry
            }
        }
    }

    component Label: Text {
        property real cx
        property real base

        x: cx - implicitWidth / 2
        y: base - baselineOffset
        color: root.soft
        font.family: Theme.fontMono
        font.pixelSize: 8
        font.letterSpacing: 1
    }

    // One fan: nine curved blades round a hub, turned by `angle`.
    component Fan: Item {
        id: fan

        property real cx
        property real cy
        property real phase

        anchors.fill: parent

        Circle {
            cx: fan.cx
            cy: fan.cy
            r: 31
            color: root.dark
            border.width: 1
            border.color: Theme.comment
        }

        Shape {
            x: fan.cx - 31
            y: fan.cy - 31
            width: 62
            height: 62
            rotation: fan.phase + root.angle
            preferredRendererType: Shape.CurveRenderer
            opacity: root.rpm > 0 ? 0.55 : 0.35

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.rpm > 0 ? root.soft : Theme.comment
                strokeWidth: 3.2
                capStyle: ShapePath.RoundCap

                PathSvg {
                    // The mockup's blade, M0 -7 Q13 -15 5 -28 about the
                    // centre, every 40°.
                    path: {
                        const p = [];
                        const at = (x, y, a) => [31 + x * Math.cos(a) - y * Math.sin(a), 31 + x * Math.sin(a) + y * Math.cos(a)];
                        for (let b = 0; b < 9; b++) {
                            const a = b * 40 * Math.PI / 180;
                            const s = at(0, -7, a);
                            const c = at(13, -15, a);
                            const e = at(5, -28, a);
                            p.push(`M${s[0]} ${s[1]} Q${c[0]} ${c[1]} ${e[0]} ${e[1]}`);
                        }
                        return p.join(" ");
                    }
                }
            }
        }

        Circle {
            cx: fan.cx
            cy: fan.cy
            r: 7.5
            color: root.metalHigh
            border.width: 1.2
            border.color: root.hot ? Theme.pink : Theme.comment
        }
    }

    Item {
        width: 392
        height: 128
        scale: root.width / 392
        transformOrigin: Item.TopLeft

        // The mini PC.
        Box {
            bx: 10
            by: 44
            bw: 92
            bh: 54
            br: 9
            fill: root.metal
            stroke: Theme.comment
            line: 1.2
        }

        Rule {
            x1: 17
            x2: 95
            ry: 49
            stroke: root.metalHigh
        }

        Box {
            bx: 20
            by: 66
            bw: 14
            bh: 6
            br: 1.5
            fill: root.dark
            stroke: Theme.comment
            line: 0.8
        }

        Box {
            bx: 38
            by: 66
            bw: 14
            bh: 6
            br: 1.5
            fill: root.dark
            stroke: Theme.comment
            line: 0.8
        }

        Box {
            bx: 56
            by: 67
            bw: 9
            bh: 4
            br: 2
            fill: root.dark
            stroke: Theme.comment
            line: 0.8
        }

        Circle {
            cx: 73
            cy: 69
            r: 2.6
            color: root.dark
            border.width: 0.8
            border.color: Theme.comment
        }

        Circle {
            cx: 88
            cy: 69
            r: 5
            color: root.dark
            border.width: 1.2
            border.color: Theme.cyan
        }

        Rectangle {
            x: 22
            y: 98
            width: 14
            height: 3
            radius: 1.5
            color: root.dark
        }

        Rectangle {
            x: 76
            y: 98
            width: 14
            height: 3
            radius: 1.5
            color: root.dark
        }

        Label {
            cx: 56
            base: 114
            text: "UM890 PRO"
        }

        // The cable.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.egpu ? Theme.purple : Theme.currentLine
                strokeWidth: 2.2
                capStyle: ShapePath.RoundCap
                strokeStyle: root.egpu ? ShapePath.SolidLine : ShapePath.DashLine
                dashPattern: [3 / 2.2, 4 / 2.2]
                startX: 102
                startY: 82

                PathCubic {
                    control1X: 122
                    control1Y: 82
                    control2X: 122
                    control2Y: 104
                    x: 142
                    y: 104
                }
            }
        }

        Label {
            cx: 122
            base: 76
            text: "OCULINK"
            color: Theme.comment
            font.pixelSize: 7
        }

        // The dock and the card.
        Item {
            anchors.fill: parent
            opacity: root.egpu ? 1 : 0.35

            Box {
                bx: 138
                by: 98
                bw: 246
                bh: 9
                br: 3
                fill: root.dark
                stroke: Theme.comment
                dashed: !root.egpu
            }

            Rectangle {
                x: 150
                y: 107
                width: 16
                height: 3
                radius: 1.5
                color: root.dark
            }

            Rectangle {
                x: 356
                y: 107
                width: 16
                height: 3
                radius: 1.5
                color: root.dark
            }

            // Circuit board green, the card's own.
            Box {
                bx: 160
                by: 90
                bw: 190
                bh: 8
                fill: "#1f3a2a"
                stroke: "#2f6a45"
                line: 0.8
            }

            Rectangle {
                x: 146
                y: 18
                width: 8
                height: 80
                radius: 1.5
                color: root.metalHigh
            }

            Box {
                bx: 154
                by: 14
                bw: 222
                bh: 76
                br: 8
                fill: root.metal
                stroke: Theme.comment
                line: 1.2
                dashed: !root.egpu
            }

            Rule {
                x1: 162
                x2: 368
                ry: 19
                stroke: root.metalHigh
            }

            Fan {
                cx: 193
                cy: 53
                phase: 0
            }

            Fan {
                cx: 265
                cy: 53
                phase: 17
            }

            Fan {
                cx: 337
                cy: 53
                phase: 34
            }

            Box {
                visible: root.egpu && root.hot
                bx: 154
                by: 14
                bw: 222
                bh: 76
                br: 8
                fill: "transparent"
                stroke: Theme.pink
                opacity: 0.7
            }

            Label {
                cx: 265
                base: 122
                text: root.egpu ? "RX 6800 XT · DEG1" : "DEG1 · NO CARD SEEN"
            }
        }
    }
}
