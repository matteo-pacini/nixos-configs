import QtQuick
import qs

// A separator and a line of key hints, `keys` as [key, action] pairs, for
// the bottom of a panel screen.
Column {
    id: root

    property var keys: []

    width: parent.width

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.currentLine
    }

    Item {
        width: parent.width
        height: hints.implicitHeight + 16

        Row {
            id: hints

            x: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Repeater {
                model: root.keys

                Text {
                    required property var modelData

                    text: `<font color="${Theme.cyan}">${modelData[0]}</font> ${modelData[1]}`
                    textFormat: Text.StyledText
                    color: Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }
    }
}
