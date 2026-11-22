import QtQuick
import QtQuick.Shapes

// A warning triangle with an exclamation mark, `size` px square, stroked in
// `color`.
Item {
    id: root

    property color color
    property real size: 15

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 16
        height: 16
        scale: root.size / 16
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: 1.6
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: "M8 1.8 L15 14 H1 Z"
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.color
            strokeWidth: 1.6
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: "M8 6.4 V10.1 M8 12 V12.3"
            }
        }
    }
}
