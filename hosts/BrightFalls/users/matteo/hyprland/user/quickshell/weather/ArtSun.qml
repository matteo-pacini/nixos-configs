import QtQuick
import QtQuick.Shapes
import qs
import "paths.js" as P

// The sun's disc, for a Shape: `disc` is [cx, cy, r], or null for none.
ShapePath {
    id: sun

    property var disc: null

    readonly property var d: disc || [0, 0, 1]

    strokeColor: "transparent"
    // SVG's radialGradient cx .38, cy .36, r .8 of the disc's box.
    fillGradient: RadialGradient {
        centerX: sun.d[0] - 0.24 * sun.d[2]
        centerY: sun.d[1] - 0.28 * sun.d[2]
        centerRadius: 1.6 * sun.d[2]
        focalX: centerX
        focalY: centerY

        GradientStop {
            position: 0
            color: Tints.sunCore
        }

        GradientStop {
            position: 0.55
            color: Theme.yellow
        }

        GradientStop {
            position: 1
            color: Theme.orange
        }
    }

    PathSvg {
        path: sun.disc ? P.circle(sun.d[0], sun.d[1], sun.d[2]) : ""
    }
}
