import QtQuick
import qs

// A separator and the key hints for the bottom of a drop-down panel, `keys`
// as [key, action] pairs, wrapping onto more lines when they need it. While
// `message` is not empty it shows in their place, in `messageColor`, wrapped;
// the footer's height follows whichever is shown.
Column {
    id: root

    property var keys: []
    property string message: ""
    property color messageColor: Theme.yellow

    width: parent.width

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.currentLine
    }

    Item {
        width: parent.width
        height: (root.message !== "" ? messageText.implicitHeight : hints.implicitHeight) + 16

        Flow {
            id: hints

            x: 14
            y: 8
            width: parent.width - 28
            visible: root.message === ""
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

        Text {
            id: messageText

            x: 14
            y: 8
            width: parent.width - 28
            visible: root.message !== ""
            text: root.message
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.messageColor
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }
}
