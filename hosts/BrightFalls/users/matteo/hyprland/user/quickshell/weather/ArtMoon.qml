import QtQuick
import QtQuick.Shapes
import qs
import "paths.js" as P

// The crescent moon, for a Shape: `disc` is [cx, cy, r] of its circle, or
// null for none.
ShapePath {
    id: moon

    property var disc: null

    readonly property var d: disc || [0, 0, 1]

    strokeColor: "transparent"
    fillGradient: LinearGradient {
        x1: moon.d[0] - moon.d[2]
        y1: moon.d[1] - moon.d[2]
        x2: moon.d[0] + moon.d[2]
        y2: moon.d[1] + moon.d[2]

        GradientStop {
            position: 0
            color: Theme.foreground
        }

        GradientStop {
            position: 1
            color: Tints.moonShade
        }
    }

    PathSvg {
        path: moon.disc ? P.crescent(moon.d[0], moon.d[1], moon.d[2]) : ""
    }
}
