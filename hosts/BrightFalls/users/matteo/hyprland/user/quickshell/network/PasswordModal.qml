import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs
import qs.common
import "wifi.js" as Wifi

// The centred modal asking a Wi-Fi network's password for the network panel.
// Shown while `request` is set: { title, detail, error, hint, security }
// (security the WifiSecurityType name, for Wifi.passwordCheck()). Opens
// empty and masked every time; Tab shows or hides the text. Enter emits
// submitted() only when Wifi.passwordCheck() allows the text, Esc emits
// cancelled(). The owner reads the text once with take(), which empties the
// field; the field is also emptied whenever the modal closes.
PanelWindow {
    id: modal

    property var request: null
    property bool revealed: false
    readonly property color soft: Style.soft
    readonly property bool allowed: request !== null && Wifi.passwordCheck(request.security, input.text).ok

    signal submitted
    signal cancelled

    // The field's text, once: the field is empty afterwards.
    function take(): string {
        const text = input.text;
        input.text = "";
        return text;
    }

    // Returns true when the key was used; the rest go to the field.
    function key(k: int): bool {
        if (k === Qt.Key_Escape) {
            cancelled();
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (allowed)
                submitted();
        } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            revealed = !revealed;
        } else {
            return false;
        }
        return true;
    }

    visible: request !== null
    color: Style.scrim
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "desk-network-password"

    onRequestChanged: {
        input.text = "";
        revealed = false;
        if (request !== null)
            input.forceActiveFocus();
    }

    // Swallows clicks on the scrim: a stray click must not answer.
    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    RectangularShadow {
        anchors.fill: box
        radius: box.radius
        offset.y: 18
        blur: 50
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        id: box

        anchors.centerIn: parent
        width: Math.min(420, parent.width - 24)
        height: column.implicitHeight + 36
        radius: Style.radius
        color: Style.surface
        border.width: 1
        border.color: Theme.purple

        MouseArea {
            anchors.fill: parent
            onClicked: input.forceActiveFocus()
        }

        Column {
            id: column

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 14

            Row {
                width: parent.width
                spacing: 12

                Rectangle {
                    width: 40
                    height: 40
                    radius: 9
                    color: Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0928}"
                        color: Theme.purple
                        font.family: Theme.fontMono
                        font.pixelSize: 20
                    }
                }

                Column {
                    width: parent.width - 52

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: modal.request?.title ?? ""
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: modal.request?.detail ?? ""
                        color: modal.soft
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: input.implicitHeight + 18
                radius: 8
                color: "transparent"
                border.width: 1
                border.color: input.activeFocus ? Theme.pink : Theme.currentLine

                TextInput {
                    id: input

                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: modal.revealed ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.foreground
                    selectionColor: Theme.currentLine
                    selectedTextColor: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.letterSpacing: echoMode === TextInput.Password ? 3 : 0
                    clip: true
                    focus: true
                    cursorDelegate: Rectangle {
                        width: 1
                        color: Theme.pink
                        visible: input.cursorVisible
                    }

                    Keys.onPressed: event => {
                        // A held Esc, Enter or Tab acts once; typing repeats.
                        if (event.isAutoRepeat && [Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab].includes(event.key))
                            event.accepted = true;
                        else if (modal.key(event.key))
                            event.accepted = true;
                    }

                    Text {
                        visible: input.text === ""
                        text: "Password"
                        color: Theme.comment
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                    }
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: modal.request?.error ?? ""
                wrapMode: Text.Wrap
                color: Theme.red
                font.family: Theme.fontMono
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: modal.request?.hint ?? ""
                wrapMode: Text.Wrap
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 12
            }

            Column {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.currentLine
                }

                Flow {
                    width: parent.width
                    spacing: 14

                    Repeater {
                        model: [["Enter", "join"], ["Esc", "cancel"], ["Tab", "show/hide"]]

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
    }
}
