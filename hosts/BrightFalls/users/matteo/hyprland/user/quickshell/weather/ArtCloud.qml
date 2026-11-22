import QtQuick
import QtQuick.Shapes

// One cloud of the condition art, for a Shape: `layer` is a cloud from
// paths.js art() (path, top and bottom of its gradient, tone light, dark
// or black).
ShapePath {
    id: cloud

    property var layer

    readonly property var stops: layer.tone === "black" ? Tints.cloudBlack : layer.tone === "dark" ? Tints.cloudDark : Tints.cloud

    strokeColor: "transparent"
    fillGradient: LinearGradient {
        x1: 0
        y1: cloud.layer.y1
        x2: 0
        y2: cloud.layer.y2

        GradientStop {
            position: 0
            color: cloud.stops[0]
        }

        GradientStop {
            position: 1
            color: cloud.stops[1]
        }
    }

    PathSvg {
        path: cloud.layer.path
    }
}
