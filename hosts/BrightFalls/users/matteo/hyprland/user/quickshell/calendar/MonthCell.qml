import QtQuick
import qs
import qs.common
import "queries.js" as Q

// One day of the big view's month grid (CalendarFull.qml): its number top
// left, on a purple pill for today, then as many of its events as fit as
// chips, and "N more" for the rest. Days outside the shown month show their
// number only. A click emits picked().
Rectangle {
    id: root

    property date day
    // CalendarPanel.data.
    property var source: null
    property bool inMonth
    property bool today
    property bool chosen
    property bool weekend

    signal picked

    readonly property int chipHeight: 20
    readonly property int chipGap: 2
    readonly property color dim: Qt.tint(Theme.background, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.55))
    readonly property bool todayHere: today && inMonth
    readonly property var view: inMonth ? Q.cellView(source, day, Q.fitRows(chipArea.height, chipHeight, chipGap)) : ({
            chips: [],
            more: 0
        })

    radius: 6
    color: todayHere ? Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0.16) : area.containsMouse ? Theme.currentLine : Qt.rgba(Theme.currentLine.r, Theme.currentLine.g, Theme.currentLine.b, inMonth ? 0.3 : 0.12)
    border.width: chosen ? 1 : 0
    border.color: Theme.pink

    Rectangle {
        id: number

        x: 6
        y: 6
        width: Math.max(height, numberText.implicitWidth + 12)
        height: numberText.implicitHeight + 4
        radius: height / 2
        color: root.todayHere ? Theme.purple : "transparent"

        Text {
            id: numberText

            anchors.centerIn: parent
            text: root.day.getDate()
            color: root.todayHere ? Theme.background : !root.inMonth ? (root.weekend ? Qt.tint(root.dim, Qt.rgba(Theme.pink.r, Theme.pink.g, Theme.pink.b, 0.25)) : root.dim) : root.weekend ? Theme.pink : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: 14
            font.weight: root.todayHere ? Font.DemiBold : Font.Normal
        }
    }

    Item {
        id: chipArea

        anchors.top: number.bottom
        anchors.topMargin: 4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 6
        clip: true

        Column {
            width: parent.width
            spacing: root.chipGap

            Repeater {
                model: root.view.chips

                Item {
                    id: chip

                    required property var modelData

                    width: chipArea.width
                    height: root.chipHeight

                    // All-day, or begun on an earlier day.
                    Rectangle {
                        visible: chip.modelData.filled
                        anchors.fill: parent
                        radius: 4
                        color: chip.modelData.color

                        Text {
                            x: 6
                            width: parent.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: chip.modelData.title
                            textFormat: Text.PlainText
                            color: Theme.background
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                        }
                    }

                    // Starts on this day.
                    Item {
                        visible: !chip.modelData.filled
                        anchors.fill: parent

                        Rectangle {
                            x: 0
                            y: 2
                            width: 3
                            height: parent.height - 4
                            radius: 1.5
                            color: chip.modelData.color
                        }

                        Text {
                            id: chipTime

                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.time
                            color: Style.soft
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }

                        Text {
                            x: chipTime.x + chipTime.implicitWidth + 6
                            width: parent.width - x
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: chip.modelData.title
                            textFormat: Text.PlainText
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                        }
                    }
                }
            }

            Text {
                visible: root.view.more > 0
                height: root.chipHeight
                leftPadding: 2
                verticalAlignment: Text.AlignVCenter
                text: Q.moreText(root.view.more)
                color: Theme.comment
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.picked()
    }
}
