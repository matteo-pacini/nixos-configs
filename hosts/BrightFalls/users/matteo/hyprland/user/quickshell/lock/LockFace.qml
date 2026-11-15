import QtQuick
import qs

// What one monitor shows while locked: the clock, the week dots and the date,
// and on the main monitor the password field, its notes and the count of
// waiting notifications. `lock` is the lock.qml root, which holds the state
// and takes the keys; every monitor forwards its keys there, because the
// compositor gives the keyboard to whichever lock surface the pointer is on.
//
// Motion is decoration only: keys reach `lock` from the first frame whatever
// is still easing in, and nothing here delays the unlock.
Rectangle {
    id: face

    required property var lock
    // Shows the field, its notes and the notification count.
    property bool main: false

    // Sizes follow the monitor's width, as in the approved mockup.
    readonly property real u: width / 100
    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))
    readonly property color backdrop: Qt.darker(Theme.background, 1.35)
    readonly property int weekday: (lock.now.getDay() + 6) % 7

    // 0 to 1: the clock and date, then the field a beat later.
    property real intro: 0
    property real fieldIntro: 0
    property real shake: 0
    // Dots drawn; follows lock.length except while they collapse after Esc.
    property int dots: 0
    // The note's text, kept while it fades out.
    property string note: ""

    // Black, the colour Hyprland paints before a lock surface's first frame,
    // and opaque from that frame on: the session-lock protocol has the
    // desktop drawn under the lock until the compositor confirms it, so only
    // the content may fade, never the surface.
    color: "black"

    function enter(): void {
        enterAnimation.restart();
    }

    Keys.onPressed: event => face.lock.key(event)
    Component.onCompleted: {
        forceActiveFocus();
        enter();
    }

    Connections {
        target: face.lock

        function onLengthChanged() {
            // Only Esc while typing collapses; the buffer emptied for PAM
            // goes at once, so "checking…" shows without a gap.
            if (face.lock.length === 0 && face.dots > 0 && face.lock.phase === "idle")
                collapse.restart();
            else {
                collapse.stop();
                dotRow.scale = 1;
                dotRow.opacity = 1;
                face.dots = face.lock.length;
            }
        }
        function onPhaseChanged() {
            if (face.lock.phase === "wrong")
                shakeAnimation.restart();
        }
        function onNoteChanged() {
            if (face.lock.note !== "")
                face.note = face.lock.note;
        }
        function onReplay() {
            face.enter();
        }
    }

    ParallelAnimation {
        id: enterAnimation

        ColorAnimation {
            target: face
            property: "color"
            from: "black"
            to: face.backdrop
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: face
            property: "intro"
            from: 0
            to: 1
            duration: 260
            easing.type: Easing.OutQuint
        }
        SequentialAnimation {
            PropertyAction {
                target: face
                property: "fieldIntro"
                value: 0
            }
            PauseAnimation {
                duration: 120
            }
            NumberAnimation {
                target: face
                property: "fieldIntro"
                to: 1
                duration: 300
                easing.type: Easing.OutQuint
            }
        }
        onFinished: face.color = Qt.binding(() => face.backdrop)
    }

    SequentialAnimation {
        id: shakeAnimation

        NumberAnimation {
            target: face
            property: "shake"
            to: -1
            duration: 50
            easing.type: Easing.OutSine
        }
        NumberAnimation {
            target: face
            property: "shake"
            to: 1
            duration: 80
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: face
            property: "shake"
            to: -0.6
            duration: 70
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: face
            property: "shake"
            to: 0.3
            duration: 60
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: face
            property: "shake"
            to: 0
            duration: 60
            easing.type: Easing.OutSine
        }
    }

    ParallelAnimation {
        id: collapse

        NumberAnimation {
            target: dotRow
            property: "scale"
            to: 0
            duration: 140
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: dotRow
            property: "opacity"
            to: 0
            duration: 140
        }
        onFinished: {
            face.dots = 0;
            dotRow.scale = 1;
            dotRow.opacity = 1;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: face.forceActiveFocus()
    }

    Column {
        anchors.centerIn: parent
        spacing: face.u * 1.1

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: face.u * 1.1
            opacity: face.intro
            transform: Translate {
                y: (1 - face.intro) * face.u * 0.8
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(face.lock.now, "HH:mm")
                color: Theme.foreground
                font.family: Theme.fontUi
                font.weight: Font.Light
                font.pixelSize: Math.round(face.u * 10)
                font.letterSpacing: -face.u * 0.2
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: face.u * 0.8

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: face.u * 0.35

                    Repeater {
                        model: 7

                        Rectangle {
                            required property int index
                            readonly property bool today: index === face.weekday

                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(face.u * (today ? 0.62 : 0.45))
                            height: width
                            radius: width / 2
                            color: today ? Theme.purple : index < face.weekday ? Theme.comment : "transparent"
                            border.width: 1
                            border.color: today ? Theme.purple : Theme.comment
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(face.lock.now, "dddd d MMMM")
                    color: face.soft
                    font.family: Theme.fontUi
                    font.pixelSize: Math.round(face.u * 1.25)
                }
            }
        }

        Item {
            visible: face.main
            width: 1
            height: face.u * 1.2
        }

        Column {
            visible: face.main
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: face.u * 1.1
            opacity: face.fieldIntro
            transform: Translate {
                y: (1 - face.fieldIntro) * face.u * 1.5
            }

            Rectangle {
                id: field

                readonly property string state: face.lock.fieldState
                readonly property color tone: state === "typing" ? Theme.purple : state === "wrong" ? Theme.red : state === "checking" || state === "unlocking" ? Theme.cyan : state === "heldoff" ? Theme.orange : Theme.currentLine

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(face.u * 16, label.implicitWidth + face.u * 3)
                height: Math.round(face.u * 2.3)
                radius: height / 2
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.75)
                border.width: 1
                border.color: tone
                transform: Translate {
                    x: face.shake * face.u * 0.45
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutQuint
                    }
                }

                Row {
                    id: dotRow

                    visible: field.state === "typing" || collapse.running
                    anchors.centerIn: parent
                    spacing: face.u * 0.35

                    Repeater {
                        // At most as many dots as fit in the field.
                        model: Math.min(face.dots, 16)

                        Rectangle {
                            width: Math.round(face.u * 0.5)
                            height: width
                            radius: width / 2
                            color: Theme.foreground

                            NumberAnimation on scale {
                                from: 0.3
                                to: 1
                                duration: 160
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }

                Text {
                    id: label

                    visible: field.state !== "typing" && !collapse.running
                    anchors.centerIn: parent
                    text: {
                        switch (field.state) {
                        case "checking":
                            return "checking…";
                        case "wrong":
                            return "wrong password";
                        case "unlocking":
                            return "unlocked";
                        case "heldoff":
                            return face.lock.systemMessage || "try again later";
                        default:
                            return "password";
                        }
                    }
                    color: field.state === "waiting" ? Theme.comment : field.tone
                    font.family: Theme.fontMono
                    font.pixelSize: Math.round(face.u * 0.8)

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // While checking: a short segment sweeping along the inside
                // of the field's lower edge.
                Item {
                    visible: field.state === "checking"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: field.radius
                    anchors.rightMargin: field.radius
                    anchors.bottomMargin: Math.round(face.u * 0.3)
                    height: 2
                    clip: true

                    Rectangle {
                        width: parent.width * 0.25
                        height: parent.height
                        radius: 1
                        color: Theme.cyan
                        opacity: 0.8

                        NumberAnimation on x {
                            running: field.state === "checking"
                            loops: Animation.Infinite
                            from: -field.width * 0.25
                            to: field.width
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: face.note
                opacity: face.lock.note !== "" ? 1 : 0
                color: face.lock.noteTone === "red" ? Theme.red : Theme.orange
                font.family: Theme.fontMono
                font.pixelSize: Math.round(face.u * 0.68)

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Text {
        visible: face.main && face.lock.waiting > 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: face.u * 1.6
        anchors.bottomMargin: face.u * 1.3
        opacity: face.intro
        text: face.lock.waiting === 1 ? "1 notification" : face.lock.waiting + " notifications"
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: Math.round(face.u * 0.62)
    }
}
