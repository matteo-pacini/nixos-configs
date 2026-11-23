import QtQuick
import qs

// A line over the panel's content in `ink` on a faint fill of it: a hold, a
// failure, a broken genres file. Its parent's width less 12 each side.
Rectangle {
    id: root

    property color ink: Theme.orange
    property string text: ""

    x: 12
    width: parent ? parent.width - 24 : 0
    height: label.implicitHeight + 12
    radius: 6
    color: Qt.rgba(ink.r, ink.g, ink.b, 0.13)

    Text {
        id: label

        x: 10
        y: 6
        width: parent.width - 20
        text: root.text
        textFormat: Text.PlainText
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        color: root.ink
        font.family: Theme.fontUi
        font.pixelSize: 12
    }
}
