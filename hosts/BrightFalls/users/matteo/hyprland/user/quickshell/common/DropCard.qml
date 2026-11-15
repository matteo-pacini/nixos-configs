import QtQuick
import QtQuick.Effects
import qs

// The card of a drop-down panel and its shadow, filling the panel's
// whole-monitor window. The card hangs Style.panelTop from the top, centred on
// its bar item and kept Style.edge from the monitor's sides; while the item's
// position is unknown it sits at the right edge, or in the middle with
// `centredFallback`. Its height follows `contentHeight`, eased over
// Style.growDuration.
// Children go inside the card; place them at x 1, y 1, inside the border.
// Clicks on the card stop there; clicks beside it reach the window.
Item {
    id: root

    // Horizontal centre of the bar item, in the window's coordinates, or -1.
    property real centre: -1
    property bool centredFallback: false
    property int cardWidth
    // Height of the children, border excluded.
    property real contentHeight

    default property alias content: card.data

    anchors.fill: parent

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        offset.y: 12
        blur: 36
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Rectangle {
        id: card

        x: root.centre < 0 ? (root.centredFallback ? Math.round((root.width - width) / 2) : root.width - width - Style.edge) : Math.max(Style.edge, Math.min(root.width - width - Style.edge, Math.round(root.centre - width / 2)))
        y: Style.panelTop
        width: root.cardWidth
        height: root.contentHeight + 2
        radius: Style.radius
        clip: true
        color: Style.surface
        border.width: 1
        border.color: Theme.purple

        Behavior on height {
            NumberAnimation {
                duration: Style.growDuration
                easing.type: Easing.OutQuint
            }
        }

        MouseArea {
            anchors.fill: parent
        }
    }
}
