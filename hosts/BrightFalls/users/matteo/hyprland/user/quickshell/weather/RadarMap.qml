import QtQuick
import QtQuick.Shapes
import qs
import qs.common
import "paths.js" as P

// The radar map, 392 × 252: a 390 × 250 view inside a 1 px rounded frame,
// cut from a block of Web Mercator tiles around `centre`. Under the radar
// tiles, the sea, a graticule (every 2° of longitude, 1° of latitude) and
// the land of `coast`, an array of rings of [lon, lat] (the generated coast
// file); over them its outline, a ring 100 km from `centre`, a marker on it,
// the legend and `note`.
//
// `block` is {zoom, tile, x0, y0, cols, rows} (the helper's radar event; null
// for the helper's fixed block), `centre` [x, y] in pixels from the block's
// top-left corner, or null for none (the view is then the block's middle,
// with no ring or marker). The view stays inside the block, so near its edge
// the marker leaves the middle. `frames` holds every frame directory, each
// with <dir>/<x>_<y>.png for the block's tiles; all of them stay loaded, and
// only the one equal to `frameDir` shows. Nothing moves.
Item {
    id: root

    property var coast: []
    property var block: null
    property var centre: null
    property var frames: []
    property string frameDir: ""
    property string note: ""

    readonly property int viewWidth: 390
    readonly property int viewHeight: 250
    // `block`, or the helper's fixed block while there is none.
    readonly property var b: block ?? {
        zoom: 6,
        tile: 256,
        x0: 30,
        y0: 18,
        cols: 3,
        rows: 4
    }
    readonly property real k: b.tile / 256
    readonly property real centreX: centre ? centre[0] : b.cols * b.tile / 2
    readonly property real centreY: centre ? centre[1] : b.rows * b.tile / 2
    // The view's top-left corner in block pixels.
    readonly property real viewLeft: Math.max(0, Math.min(centreX - viewWidth / 2, b.cols * b.tile - viewWidth))
    readonly property real viewTop: Math.max(0, Math.min(centreY - viewHeight / 2, b.rows * b.tile - viewHeight))
    readonly property real ringRadius: 100000 / P.metresPerPixel(P.latitude(b.y0 * 256 + centreY / k, b.zoom), b.zoom) * k

    // [lon, lat] to view pixels.
    function place(lon, lat) {
        const w = P.project(lon, lat, b.zoom);
        return [w[0] * k - b.x0 * b.tile - viewLeft, w[1] * k - b.y0 * b.tile - viewTop];
    }

    readonly property string coastPath: coast.map(ring => ring.map((p, i) => {
            const v = place(p[0], p[1]);
            return (i ? "L" : "M") + v[0].toFixed(1) + " " + v[1].toFixed(1);
        }).join(" ") + " Z").join(" ")

    readonly property string gridPath: {
        const s = [];
        for (let lon = -10; lon <= 4; lon += 2) {
            const x = place(lon, 55)[0];
            s.push(`M${x} 0 V${viewHeight}`);
        }
        for (let lat = 50; lat <= 58; lat++) {
            const y = place(0, lat)[1];
            s.push(`M0 ${y} H${viewWidth}`);
        }
        return s.join(" ");
    }

    // The block's tiles that reach into the view, at view positions.
    readonly property var tiles: {
        const out = [];
        for (let c = 0; c < b.cols; c++)
            for (let r = 0; r < b.rows; r++) {
                const x = c * b.tile - viewLeft, y = r * b.tile - viewTop;
                if (x < viewWidth && x + b.tile > 0 && y < viewHeight && y + b.tile > 0)
                    out.push({
                        name: `${b.x0 + c}_${b.y0 + r}.png`,
                        x: x,
                        y: y
                    });
            }
        return out;
    }

    implicitWidth: viewWidth + 2
    implicitHeight: viewHeight + 2

    Item {
        x: 1
        y: 1
        width: root.viewWidth
        height: root.viewHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Tints.sea
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, 0.25)
                strokeWidth: 1

                PathSvg {
                    path: root.gridPath
                }
            }

            ShapePath {
                fillColor: Tints.land
                strokeColor: "transparent"
                fillRule: ShapePath.WindingFill

                PathSvg {
                    path: root.coastPath
                }
            }
        }

        Repeater {
            model: root.frames

            Item {
                id: frame

                required property string modelData

                anchors.fill: parent
                visible: modelData === root.frameDir

                Repeater {
                    model: root.tiles

                    Image {
                        required property var modelData

                        x: modelData.x
                        y: modelData.y
                        width: root.b.tile
                        height: root.b.tile
                        source: "file://" + frame.modelData + "/" + modelData.name
                        asynchronous: true
                        // Held by this item while the frame is listed; a
                        // dropped frame's tiles leave memory with it.
                        cache: false
                    }
                }
            }
        }

        // The coastline over the rain, so it stays visible under echoes.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.comment
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: root.coastPath
                }
            }
        }

        Shape {
            anchors.fill: parent
            visible: root.centre !== null
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.3)
                strokeWidth: 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 4]

                PathSvg {
                    path: P.circle(root.centreX - root.viewLeft, root.centreY - root.viewTop, root.ringRadius)
                }
            }
        }

        Text {
            visible: root.centre !== null
            x: root.centreX - root.viewLeft + root.ringRadius + 3.4
            y: root.centreY - root.viewTop + 3.5 - baselineOffset
            text: "100 km"
            color: Style.soft
            opacity: 0.8
            font.family: Theme.fontMono
            font.pixelSize: 10
        }

        Rectangle {
            visible: root.centre !== null
            x: root.centreX - root.viewLeft - 5.5
            y: root.centreY - root.viewTop - 5.5
            width: 11
            height: 11
            radius: 5.5
            antialiasing: true
            color: Theme.background
            border.width: 2
            border.color: Theme.purple

            Rectangle {
                anchors.centerIn: parent
                width: 3.6
                height: 3.6
                radius: 1.8
                antialiasing: true
                color: Theme.purple
            }
        }

        // The legend on a backing of the sea's colour, readable over echoes.
        Rectangle {
            x: 4
            y: root.viewHeight - 22
            width: legendText.x + legendText.implicitWidth + 4
            height: 18
            radius: 4
            color: Qt.rgba(Tints.sea.r, Tints.sea.g, Tints.sea.b, 0.85)

            Row {
                x: 4
                y: 6
                spacing: 1

                Repeater {
                    model: Tints.radarSteps

                    Rectangle {
                        required property color modelData

                        width: 12
                        height: 6
                        radius: 1.5
                        color: modelData
                    }
                }
            }

            Text {
                id: legendText

                x: 4 + Tints.radarSteps.length * 13 + 5
                y: 12 - baselineOffset
                text: "light to heavy"
                color: Style.soft
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }

        Text {
            visible: root.note !== ""
            x: 14
            y: Math.round(root.viewHeight * 0.12)
            width: root.viewWidth - 28
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.note
            textFormat: Text.PlainText
            color: Style.soft
            font.family: Theme.fontUi
            font.pixelSize: 13
        }
    }

    // The frame's rounded corners: the card's own fill over the view's
    // square corners (odd-even: the box minus the rounded box), then the
    // 1 px line. Over the card, the fill's 4 % show-through of the view
    // instead of the desktop is not visible.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Style.surface
            fillRule: ShapePath.OddEvenFill

            PathSvg {
                path: `M0 0 H${root.width} V${root.height} H0 Z ` + `M8 0 H${root.width - 8} A8 8 0 0 1 ${root.width} 8 V${root.height - 8} A8 8 0 0 1 ${root.width - 8} ${root.height} H8 A8 8 0 0 1 0 ${root.height - 8} V8 A8 8 0 0 1 8 0 Z`
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: 1
        border.color: Theme.currentLine
    }
}
