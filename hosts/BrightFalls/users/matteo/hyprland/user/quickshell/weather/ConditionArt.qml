import QtQuick
import QtQuick.Shapes
import qs
import qs.common
import "paths.js" as P

// One weather condition drawn in layers, `size` px square: `kind` is one of
// sunny, clear-night, partlycloudy, partlycloudy-night, cloudy, rainy,
// pouring, lightning-rainy, snowy, snowy-rainy, fog, windy; any other draws
// nothing. It has no motion.
Item {
    id: root

    property string kind
    property real size: 22

    readonly property var art: P.art(kind)

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 64
        height: 64
        scale: root.size / 64
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.orange
            strokeWidth: 2.6
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: root.art.rays
            }
        }

        ArtSun {
            disc: root.art.sun
        }

        ArtMoon {
            disc: root.art.moon
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: Theme.foreground

            PathSvg {
                path: root.art.stars
            }
        }

        ArtCloud {
            layer: root.art.clouds[0]
        }

        ArtCloud {
            layer: root.art.clouds[1]
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: Theme.yellow

            PathSvg {
                path: root.art.bolt
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.cyan
            strokeWidth: 2.4
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: root.art.drops
            }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: Theme.foreground

            PathSvg {
                path: root.art.flakes
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Style.soft
            strokeWidth: 2.6
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: root.art.bars + " " + root.art.wind
            }
        }
    }
}
