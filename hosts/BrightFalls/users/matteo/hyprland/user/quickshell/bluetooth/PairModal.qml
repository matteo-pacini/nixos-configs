import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs
import "services.js" as S

// The centred modal for one agent request: a code to compare or type, a
// pairing without a code, or a service the device wants. Shown while
// `request` is set; answers come only from the user's keys or clicks.
PanelWindow {
    id: modal

    // The agent request on screen, or null.
    property var request: null
    property string deviceName: "A device"
    property string kindLabel: "device"
    property string glyph: "\u{f00af}"
    // True when this computer started the pairing (the panel's Enter).
    property bool initiated: false

    readonly property string method: request?.method ?? ""
    readonly property bool typing: method === "RequestPasskey" || method === "RequestPinCode"
    readonly property bool display: method === "DisplayPasskey" || method === "DisplayPinCode"
    readonly property var service: method === "AuthorizeService" ? S.describe(request.uuid, deviceName) : null
    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))

    // accept: the answer; extra: { passkey } or { pin }; trust: also trust
    // the device. For a display request, accept false means stop pairing.
    signal decided(bool accept, var extra, bool trust)

    function spaced(code: string): string {
        return code.length === 6 ? code.slice(0, 3) + " " + code.slice(3) : code;
    }

    function submit(): void {
        if (method === "RequestPasskey") {
            if (/^\d{1,6}$/.test(input.text))
                decided(true, {
                    passkey: Number(input.text)
                }, false);
        } else if (method === "RequestPinCode") {
            if (input.text !== "")
                decided(true, {
                    pin: input.text
                }, false);
        } else if (!display) {
            decided(true, {}, false);
        }
    }

    visible: request !== null
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
    WlrLayershell.namespace: "desk-bluetooth-pair"

    onRequestChanged: {
        input.text = "";
        if (typing)
            input.forceActiveFocus();
        else
            keys.forceActiveFocus();
    }

    // Swallows clicks on the scrim: a stray click must not answer.
    MouseArea {
        anchors.fill: parent
    }

    Item {
        id: keys

        focus: true
        Keys.onPressed: event => {
            const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
            if (event.key === Qt.Key_Escape)
                modal.decided(false, {}, false);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                modal.submit();
            else if (event.key === Qt.Key_T && plain && modal.service !== null)
                modal.decided(true, {}, true);
            else
                return;
            event.accepted = true;
        }
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
        width: Math.min(380, parent.width - 24)
        height: column.implicitHeight + 30
        radius: 10
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
        border.width: 1
        border.color: Theme.purple

        Column {
            id: column

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modal.glyph
                color: Theme.purple
                font.family: Theme.fontMono
                font.pixelSize: 26
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: {
                    if (modal.service)
                        return modal.service.known ? modal.service.name : `${modal.deviceName} asks for an unlisted service`;
                    if (modal.initiated)
                        return `Pair ${modal.deviceName}`;
                    return `${modal.deviceName} wants to pair`;
                }
                color: Theme.foreground
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                visible: modal.service !== null && !modal.service.known
                anchors.horizontalCenter: parent.horizontalCenter
                text: `UUID ${modal.service?.short ?? ""}`
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: {
                    const m = modal.method;
                    if (modal.service)
                        return modal.service.question;
                    if (m === "RequestConfirmation")
                        return modal.initiated ? `Does the ${modal.kindLabel} show this code?` : `Pair only if you started this on the ${modal.kindLabel} and it shows the same code.`;
                    if (m === "RequestAuthorization")
                        return modal.initiated ? "It shows no code. Pair?" : "It shows no code. Pair only if you started this on it.";
                    if (modal.display)
                        return `Type this code on the ${modal.kindLabel}, then press Enter on it.`;
                    if (m === "RequestPasskey")
                        return `Type the six digits the ${modal.kindLabel} shows.`;
                    if (m === "RequestPinCode")
                        return `Type the PIN for the ${modal.kindLabel} (often 0000 or 1234, or the one it shows).`;
                    return "";
                }
                color: modal.soft
                font.family: Theme.fontUi
                font.pixelSize: 14
            }

            Text {
                readonly property string code: modal.request?.passkey ?? modal.request?.pincode ?? ""

                visible: modal.method === "RequestConfirmation" || modal.display
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                text: /^\d{6}$/.test(code) ? "six-digit code" : `${code.length}-character PIN`
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            Text {
                visible: modal.method === "RequestConfirmation" || modal.display
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 0
                bottomPadding: 4
                text: modal.spaced(modal.request?.passkey ?? modal.request?.pincode ?? "")
                color: Theme.foreground
                font.family: Theme.fontMono
                font.pixelSize: 28
                font.weight: Font.DemiBold
                font.letterSpacing: 5
            }

            Text {
                visible: modal.method === "DisplayPasskey" && (modal.request?.entered ?? 0) > 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${modal.request?.entered ?? 0} of 6 typed`
                color: Theme.cyan
                font.family: Theme.fontMono
                font.pixelSize: 12
            }

            Rectangle {
                visible: modal.typing
                anchors.horizontalCenter: parent.horizontalCenter
                width: 180
                height: input.implicitHeight + 16
                radius: 8
                color: "transparent"
                border.width: 1
                border.color: input.activeFocus ? Theme.pink : Theme.currentLine

                TextInput {
                    id: input

                    anchors.centerIn: parent
                    width: parent.width - 20
                    horizontalAlignment: TextInput.AlignHCenter
                    maximumLength: modal.method === "RequestPasskey" ? 6 : 16
                    validator: RegularExpressionValidator {
                        regularExpression: modal.method === "RequestPasskey" ? /\d*/ : /.*/
                    }
                    color: Theme.foreground
                    font.family: Theme.fontMono
                    font.pixelSize: 20
                    font.letterSpacing: 3
                    cursorDelegate: Rectangle {
                        width: 1
                        color: Theme.pink
                        visible: input.cursorVisible
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape)
                            modal.decided(false, {}, false);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            modal.submit();
                        else
                            return;
                        event.accepted = true;
                    }
                }
            }

            Text {
                visible: modal.service !== null
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: `Trusting ${modal.deviceName} stops these questions.`
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 4
                spacing: 14

                Repeater {
                    model: {
                        const m = modal.method;
                        if (modal.service)
                            return [["Enter", "allow"], ["T", "allow and trust"], ["Esc", "deny"]];
                        if (modal.display)
                            return [["Esc", "cancel"]];
                        if (modal.typing)
                            return [["Enter", "pair"], ["Esc", "cancel"]];
                        if (m === "RequestConfirmation" && modal.initiated)
                            return [["Enter", "yes, pair"], ["Esc", "no"]];
                        return [["Enter", "pair"], ["Esc", "refuse"]];
                    }

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
