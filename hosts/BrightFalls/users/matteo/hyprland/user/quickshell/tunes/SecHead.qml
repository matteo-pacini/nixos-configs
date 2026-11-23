import QtQuick
import qs
import qs.common

// A section's heading in the tunes player: `title` in capitals at the left;
// at the right `side` (plain text, eliding), or with `toggle` the composer's
// switch, lit cyan while `on`, and `side` beside it in `sideColor`.
Item {
    id: root

    property string title: ""
    property string side: ""
    property color sideColor: Theme.comment
    property bool toggle: false
    property bool on: false

    width: parent ? parent.width : 0
    height: heading.implicitHeight + 14

    Text {
        id: heading

        x: 14
        y: 10
        text: root.title
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.88
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: heading.y
        height: heading.implicitHeight
        spacing: 6

        Rectangle {
            visible: root.toggle
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 12
            radius: 6
            color: root.on ? Style.switchOn : Theme.currentLine

            Rectangle {
                x: root.on ? 12 : 2
                y: 2
                width: 8
                height: 8
                radius: 4
                color: root.on ? Theme.cyan : Theme.comment
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - heading.implicitWidth - 50)
            elide: Text.ElideRight
            text: root.side
            textFormat: Text.PlainText
            color: root.sideColor
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }
}
