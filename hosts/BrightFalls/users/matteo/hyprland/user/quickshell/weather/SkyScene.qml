import QtQuick
import QtQuick.Shapes
import qs
import qs.common
import "paths.js" as P

// The sky over a row of houses, 420 × 170 unless sized otherwise. `blank`
// draws only the ground and an empty sky. Otherwise: `day` picks sun or moon
// and the sky (`edge`, sunrise or sunset, gives the dusk sky), which sits
// `frac` (0..1) along its arc; `cloud` (0..1) is the cover, `rain` (0..n)
// the rain's strength, `snow` and `fog` add theirs, and `lit` lights the
// windows. `seed` places stars, clouds, rain and snow, the same way every
// time. Rain and snow fall, clouds and fog drift and stars twinkle only
// while `running`.
Item {
    id: root

    property bool blank: false
    property bool day: true
    property real frac: 0.5
    property bool edge: false
    property real cloud: 0
    property real rain: 0
    property bool snow: false
    property bool fog: false
    property bool lit: false
    property int seed: 11
    property bool running: false

    // Seconds of motion so far; it stands still while not running.
    property real t: 0

    readonly property var placed: P.sceneLayout({
        blank: blank,
        day: day,
        cloud: cloud,
        rain: rain,
        snow: snow,
        fog: fog,
        seed: seed,
        w: width,
        h: height
    })
    readonly property var sky: blank ? Tints.skyBlank : !day ? Tints.skyNight : edge ? Tints.skyEdge : Tints.skyDay
    readonly property var body: P.skyPoint(width, height, frac)
    readonly property var land: P.skyline(width, height)
    readonly property color cloudFill: !day ? Tints.sceneCloudNight : rain > 0 || snow ? Tints.sceneCloudWet : edge ? Tints.sceneCloudEdge : Tints.sceneCloudDay
    readonly property real drift: 16 * P.swing(t, 24)
    readonly property real twinkle: P.swing(t, 3)

    implicitWidth: 420
    implicitHeight: 170
    clip: true

    // Stepped, not every frame: each step redraws the panel's window, which
    // is most of the motion's cost. 10 steps a second while rain (34 px/s)
    // or snow falls; otherwise 5, as drift and twinkle move well under a
    // pixel a step.
    Timer {
        interval: root.rain > 0 || root.snow ? 100 : 200
        running: root.running && !root.blank
        repeat: true
        onTriggered: root.t += interval / 1000
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height

                GradientStop {
                    position: 0
                    color: root.sky[0]
                }

                GradientStop {
                    position: 0.62
                    color: root.sky[1]
                }

                GradientStop {
                    position: 1
                    color: root.sky[2]
                }
            }

            PathRectangle {
                width: root.width
                height: root.height
            }
        }
    }

    Repeater {
        model: root.placed.stars

        Rectangle {
            required property var modelData

            x: modelData.x - modelData.r
            y: modelData.y - modelData.r
            width: 2 * modelData.r
            height: width
            radius: modelData.r
            antialiasing: true
            color: Theme.foreground
            opacity: modelData.twinkle ? modelData.opacity + (0.25 - modelData.opacity) * root.twinkle : modelData.opacity
        }
    }

    Shape {
        anchors.fill: parent
        visible: !root.blank
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.2)
            strokeWidth: 1.5
            capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            // In stroke widths: 1.5 and 5 px.
            dashPattern: [1, 5 / 1.5]

            PathSvg {
                path: P.skyArc(root.width, root.height)
            }
        }
    }

    Shape {
        anchors.fill: parent
        visible: !root.blank
        opacity: 1 - root.cloud * 0.55
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.body[0]
                centerY: root.body[1]
                centerRadius: root.day ? 30 : 26
                focalX: centerX
                focalY: centerY

                GradientStop {
                    position: 0
                    color: root.day ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.5) : Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0.42)
                }

                GradientStop {
                    position: 1
                    color: root.day ? Qt.rgba(Theme.orange.r, Theme.orange.g, Theme.orange.b, 0) : Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0)
                }
            }

            PathSvg {
                path: P.circle(root.body[0], root.body[1], root.day ? 30 : 26)
            }
        }

        ArtSun {
            disc: root.day ? [root.body[0], root.body[1], 9.5] : null
        }

        // The art's moon at half size, drawn 16 px up and left of the point
        // as the design places it.
        ArtMoon {
            disc: root.day ? null : [root.body[0] - 1.5, root.body[1] + 0.5, 8]
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.blank && root.cloud > 0
        color: root.day ? Tints.veilDay : Tints.veilNight
        opacity: root.cloud * (root.day ? 0.55 : 0.45)
    }

    Item {
        width: root.width
        height: root.height
        x: root.drift

        Repeater {
            model: root.placed.clouds

            Shape {
                required property var modelData

                x: modelData.x
                y: modelData.y
                width: 64
                height: 64
                scale: modelData.scale
                transformOrigin: Item.TopLeft
                opacity: modelData.opacity
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.cloudFill

                    PathSvg {
                        path: P.cloud(0, 0, 1)
                    }
                }
            }
        }
    }

    Repeater {
        model: root.placed.fog

        Rectangle {
            required property var modelData

            x: modelData.x + root.drift
            y: modelData.y
            width: root.width + 40
            height: 9
            radius: 4.5
            color: Style.soft
            opacity: modelData.opacity
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Tints.ground
            fillRule: ShapePath.WindingFill

            PathSvg {
                path: root.land.path
            }
        }
    }

    Repeater {
        model: root.land.windows

        Rectangle {
            required property var modelData
            required property int index

            // The first and third houses light up; the third not at dusk.
            readonly property bool on: !root.blank && (index === 0 && root.lit || index === 2 && root.lit && !root.edge)

            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            color: on ? Theme.yellow : Tints.windowDark
            opacity: on ? 0.9 : 1
        }
    }

    // The lines in six phase groups: one shape per group, not per line.
    Repeater {
        model: P.rainGroups(root.placed.rain, 6)

        Shape {
            id: drop

            required property var modelData

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(Theme.cyan.r, Theme.cyan.g, Theme.cyan.b, 0.5)
                strokeWidth: 1.2
                capStyle: ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                // 8 px on, 14 off, moving 22 px each 0.65 s; in stroke
                // widths, and counted down so the offset stays positive.
                dashPattern: [8 / 1.2, 14 / 1.2]
                dashOffset: 22 / 1.2 * (1 - (root.t + drop.modelData.delay) % 0.65 / 0.65)

                PathSvg {
                    path: drop.modelData.path
                }
            }
        }
    }

    Repeater {
        model: root.placed.snow

        Rectangle {
            required property var modelData

            // Each flake falls 28 px and drifts 5 px right every 3.2 s.
            readonly property real fall: (root.t + modelData.delay) % 3.2 / 3.2

            x: modelData.x + 5 * fall - modelData.r
            y: modelData.y - 14 + 28 * fall - modelData.r
            width: 2 * modelData.r
            height: width
            radius: modelData.r
            antialiasing: true
            color: Theme.foreground
            opacity: modelData.opacity
        }
    }
}
