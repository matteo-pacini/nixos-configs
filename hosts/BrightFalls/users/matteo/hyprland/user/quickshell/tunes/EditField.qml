import QtQuick
import qs
import qs.common

// One field of the tunes genre editor: its label in capitals with a note at
// the right, the box (pink while it has the keyboard, red while bad), the
// text wrapping and the box growing with it, a placeholder while empty, and
// the error in red under the box. `spec` is tunes.js's { label, side,
// placeholder, error, bad }. With a `suffix` the text keeps to one line and
// the suffix follows it.
// The text is the user's: set() replaces it, and every change is reported
// through edited(). The field takes the keyboard whenever `wanted` turns
// true, and reports focused() when it takes it any other way (a click).
// Every key reaches keyPressed() before the field; accepting it there keeps
// it from the field.
Column {
    id: root

    property var spec: null
    property string suffix: ""
    property bool wanted: false
    property int fontSize: 14

    signal edited(string text)
    signal focused
    signal keyPressed(var event)

    function set(text: string): void {
        if (input.text !== text)
            input.text = text;
    }

    spacing: 4
    // Asked for in the same change that shows the editor: the field may not
    // be visible yet, and an invisible item cannot take the keyboard.
    onWantedChanged: if (wanted)
        Qt.callLater(() => input.forceActiveFocus())

    Item {
        width: parent.width
        height: Math.max(labelText.implicitHeight, sideText.implicitHeight)

        Text {
            id: labelText

            text: root.spec ? root.spec.label : ""
            color: Theme.comment
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: Font.Medium
            font.letterSpacing: 0.88
        }

        Text {
            id: sideText

            anchors.right: parent.right
            width: Math.min(implicitWidth, parent.width - labelText.implicitWidth - 8)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            text: root.spec ? root.spec.side : ""
            color: Theme.comment
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }

    Rectangle {
        width: parent.width
        height: input.implicitHeight + 14
        radius: 8
        color: "transparent"
        border.width: 1
        border.color: root.spec && root.spec.bad ? Theme.red : input.activeFocus ? Theme.pink : Theme.currentLine

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }

        TextEdit {
            id: input

            x: 10
            y: 7
            width: parent.width - 20 - (root.suffix !== "" ? suffixText.implicitWidth + 4 : 0)
            textFormat: TextEdit.PlainText
            wrapMode: root.suffix !== "" ? TextEdit.NoWrap : TextEdit.Wrap
            clip: root.suffix !== ""
            selectByMouse: true
            color: Theme.foreground
            selectionColor: Theme.currentLine
            selectedTextColor: Theme.foreground
            font.family: Theme.fontUi
            font.pixelSize: root.fontSize
            cursorDelegate: Rectangle {
                width: 1
                color: Theme.pink
                visible: input.cursorVisible
            }
            onTextChanged: root.edited(text)
            onActiveFocusChanged: if (activeFocus)
                root.focused()
            Keys.onPressed: event => root.keyPressed(event)

            Text {
                visible: input.text === ""
                width: parent.width
                wrapMode: Text.Wrap
                text: root.spec ? root.spec.placeholder : ""
                color: Theme.comment
                font.family: Theme.fontUi
                font.pixelSize: root.fontSize
            }
        }

        Text {
            id: suffixText

            visible: root.suffix !== ""
            x: input.x + Math.min(input.contentWidth, input.width) + 4
            y: input.y
            text: root.suffix
            color: Theme.comment
            font.family: Theme.fontUi
            font.pixelSize: root.fontSize
        }
    }

    Text {
        visible: text !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.spec ? root.spec.error : ""
        textFormat: Text.PlainText
        color: Theme.red
        font.family: Theme.fontMono
        font.pixelSize: 12
    }
}
