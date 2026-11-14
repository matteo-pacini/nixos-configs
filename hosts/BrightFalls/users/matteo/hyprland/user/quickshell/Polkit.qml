import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland

// The session's polkit authentication agent: a dialog on the focused monitor
// for each request, one at a time in the order they arrive. The pending
// request can be cancelled over IPC:
//   qs ipc call polkit cancel
// Quickshell registers the agent once per process, when this first loads; if
// another agent held the session then, it takes a restart to register.
Scope {
    id: root

    readonly property AuthFlow flow: agent.flow
    // The mockup's "soft" text colour, between foreground and comment.
    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))

    function submit() {
        if (!flow || !flow.isResponseRequired)
            return;
        flow.submit(input.text);
        input.text = "";
    }

    function cancel() {
        input.text = "";
        flow?.cancelAuthenticationRequest();
    }

    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: {
            const name = Hyprland.focusedMonitor?.name;
            window.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
            input.text = "";
        }
        onIsRegisteredChanged: console.info("polkit: agent registered:", isRegistered)
    }

    IpcHandler {
        target: "polkit"

        function cancel(): void {
            root.cancel();
        }
    }

    PanelWindow {
        id: window

        visible: agent.isActive
        color: Qt.rgba(15 / 255, 16 / 255, 22 / 255, 0.5)
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "desk-polkit"

        onVisibleChanged: if (visible)
            input.forceActiveFocus()

        // Swallows clicks on the scrim: a stray click must not cancel.
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
            radius: 10
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
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
                            text: ""
                            color: Theme.purple
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                        }
                    }

                    Column {
                        width: parent.width - 52

                        Text {
                            text: "Authentication required"
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: root.flow?.message ?? ""
                            wrapMode: Text.Wrap
                            color: root.soft
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
                        anchors.right: who.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        readOnly: !(root.flow?.isResponseRequired ?? false)
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
                            if (event.key === Qt.Key_Escape)
                                root.cancel();
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                root.submit();
                            else
                                return;
                            event.accepted = true;
                        }

                        Text {
                            visible: input.text === ""
                            text: input.readOnly ? "Checking…" : "Password"
                            color: Theme.comment
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                        }
                    }

                    Text {
                        id: who

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.flow?.selectedIdentity?.string ?? ""
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.flow?.supplementaryIsError && root.flow.supplementaryMessage !== "" ? root.flow.supplementaryMessage : root.flow?.failed ? "Wrong password, try again." : ""
                    wrapMode: Text.Wrap
                    color: Theme.red
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

                    // No command line: Quickshell drops the request's
                    // details, which is where pkexec puts it.
                    Text {
                        width: parent.width
                        text: "action <font color=\"" + root.soft + "\">" + (root.flow?.actionId ?? "") + "</font>"
                        textFormat: Text.StyledText
                        wrapMode: Text.WrapAnywhere
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Repeater {
                        model: [
                            {
                                label: "Cancel",
                                primary: false
                            },
                            {
                                label: "Authenticate",
                                primary: true
                            }
                        ]

                        Rectangle {
                            id: button

                            required property var modelData

                            width: label.implicitWidth + 28
                            height: label.implicitHeight + 12
                            radius: 7
                            color: modelData.primary ? Theme.purple : "transparent"
                            border.width: 1
                            border.color: modelData.primary ? Theme.purple : Theme.currentLine
                            opacity: modelData.primary && input.readOnly ? 0.5 : 1

                            Text {
                                id: label

                                anchors.centerIn: parent
                                text: button.modelData.label
                                color: button.modelData.primary ? "#191a21" : Theme.foreground
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: button.modelData.primary ? Font.DemiBold : Font.Normal
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: button.modelData.primary ? root.submit() : root.cancel()
                            }
                        }
                    }
                }
            }
        }
    }
}
