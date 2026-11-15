import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Widgets
import qs
import qs.common

// One notification: icon, summary, body, time and up to three actions.
// Left click invokes the default action (which dismisses it unless the sender
// marked it resident) or, with none, dismisses it; right or middle click
// dismisses it.
Rectangle {
    id: card

    required property Entry entry
    // Now, in ms since the epoch, for the relative time.
    property real now: Date.now()
    // Summary on one line instead of up to three.
    property bool oneLine: false
    // Notifications tucked behind this one, for the "N more" line; 0 hides it.
    property int more: 0
    // False while the card is only a strip peeking out behind a deck's front.
    property bool contentShown: true

    readonly property Notification notification: entry.notification
    readonly property bool active: contentShown && !entry.closing
    readonly property bool critical: notification.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: [...notification.actions].find(a => a.identifier === "default") ?? null
    readonly property var stripActions: [...notification.actions].filter(a => a.identifier !== "default").slice(0, 3)
    // Letter tile colour: red when critical, else picked by the app's name.
    readonly property color tile: critical ? Theme.red : [Theme.cyan, Theme.green, Theme.orange, Theme.pink, Theme.purple, Theme.yellow][[...notification.appName].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 6, 0)]
    readonly property color soft: Style.soft

    // The notification's image, else its icon, else the icon of the app's
    // desktop entry; "" leaves the letter tile.
    readonly property string iconSource: {
        // An image-path hint that is not a file: URL (notify-send --icon
        // sends one) arrives as image://icon/<name or path>, which shows a
        // missing-texture pattern rather than failing when there is no
        // such icon.
        const image = notification.image.startsWith("image://icon/") ? iconUrl(notification.image.slice("image://icon/".length)) : notification.image;
        if (image !== "")
            return image;
        const own = iconUrl(notification.appIcon);
        if (own !== "")
            return own;
        const desktop = DesktopEntries.byId(notification.desktopEntry) ?? DesktopEntries.heuristicLookup(notification.appName);
        return iconUrl(desktop?.icon ?? "");
    }

    // A symbolic icon is a dark one-colour glyph, drawn on the letter tile.
    readonly property bool symbolic: iconSource.includes("-symbolic")

    function iconUrl(icon) {
        if (icon.startsWith("file://"))
            return icon;
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon === "")
            return "";
        // Adwaita ships many names, audio-input-microphone and
        // x-office-calendar among them, only as <name>-symbolic.
        return Quickshell.iconPath(icon, true) || Quickshell.iconPath(icon + "-symbolic", true);
    }

    function ago() {
        const s = Math.max(0, (now - entry.time) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    implicitHeight: main.height + (strip.visible ? strip.height : 0) + 2
    radius: 10
    color: Style.surface
    border.width: 1
    border.color: critical ? Theme.red : Theme.purple
    // While a peek strip grows into a full card.
    clip: true

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        enabled: card.active
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton && card.defaultAction)
                card.defaultAction.invoke();
            else
                card.notification.dismiss();
        }
    }

    Item {
        id: main

        x: 1
        y: 1
        width: parent.width - 2
        height: Math.max(icon.height, column.height) + 24
        opacity: card.contentShown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }

        ClippingRectangle {
            id: icon

            x: 12
            y: 12
            width: 40
            height: 40
            radius: 9
            color: image.status === Image.Ready && !card.symbolic ? "transparent" : card.tile

            Image {
                id: image

                anchors.centerIn: parent
                width: card.symbolic ? 22 : 40
                height: width
                visible: !card.symbolic
                source: card.iconSource
                sourceSize.width: width
                sourceSize.height: height
                fillMode: card.notification.image !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            }

            // The glyph's shape in the background colour.
            Rectangle {
                id: glyphFill

                anchors.fill: image
                visible: false
                layer.enabled: true
                color: Theme.background
            }

            MultiEffect {
                anchors.fill: image
                visible: card.symbolic && image.status === Image.Ready
                source: glyphFill
                maskEnabled: true
                maskSource: image
            }

            Text {
                anchors.centerIn: parent
                visible: image.status !== Image.Ready
                text: (card.notification.appName[0] ?? "?").toUpperCase()
                color: Theme.background
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }

        Column {
            id: column

            x: icon.x + icon.width + 12
            y: 12
            width: parent.width - x - 12
            spacing: 2

            Item {
                width: parent.width
                height: summary.height

                Text {
                    id: summary

                    width: parent.width - stampWidth.width - 8
                    text: card.notification.summary
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: card.oneLine ? 1 : 3
                    elide: Text.ElideRight
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                // Every time label is three characters in a monospace font,
                // so the summary keeps one width through hover.
                TextMetrics {
                    id: stampWidth

                    font: stamp.font
                    text: "now"
                }

                Text {
                    id: stamp

                    anchors.right: parent.right
                    anchors.baseline: summary.baseline
                    text: hover.hovered && card.active ? "" : card.ago()
                    color: close.containsMouse ? Theme.foreground : Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 11

                    MouseArea {
                        id: close

                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: hover.hovered && card.active
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: card.notification.dismiss()
                    }
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: card.notification.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                // Two, or as many as the sender broke it into, up to eight.
                maximumLineCount: Math.min(8, Math.max(2, card.notification.body.split("\n").length))
                elide: Text.ElideRight
                color: card.soft
                font.family: Theme.fontUi
                font.pixelSize: 14
            }

            Text {
                visible: card.more > 0
                topPadding: 2
                text: card.more + " more from " + card.notification.appName
                color: Theme.purple
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }
    }

    Item {
        id: strip

        visible: card.stripActions.length > 0
        x: 1
        y: main.y + main.height
        width: parent.width - 2
        height: 1 + actions.height
        opacity: main.opacity

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.currentLine
        }

        Row {
            id: actions

            y: 1

            Repeater {
                model: card.stripActions

                Item {
                    id: action

                    required property NotificationAction modelData
                    required property int index

                    width: strip.width / card.stripActions.length
                    height: label.implicitHeight + 14

                    Rectangle {
                        visible: action.index > 0
                        width: 1
                        height: parent.height
                        color: Theme.currentLine
                    }

                    Text {
                        id: label

                        anchors.centerIn: parent
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        text: action.modelData.text
                        elide: Text.ElideRight
                        color: area.containsMouse ? Theme.foreground : Theme.cyan
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        enabled: card.active
                        hoverEnabled: true
                        onClicked: action.modelData.invoke()
                    }
                }
            }
        }
    }
}
