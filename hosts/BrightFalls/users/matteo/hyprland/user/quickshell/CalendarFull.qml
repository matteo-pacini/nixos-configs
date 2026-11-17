import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.calendar
import qs.common
import "calendar/queries.js" as Q

// The calendar's big view: the month as a card 80 % of the focused monitor,
// each day naming its events, the selected day's list beside it. The rest of
// the monitor is dimmed here and blurred by Hyprland (the layer rule for
// desk-calendar-full in hypr/rules.lua). Toggled over IPC:
//   qs ipc call calendarfull toggle
// or from the drop-down with F, and F here goes back to it on the same day.
// The same data, sync and web calendar as the drop-down (CalendarPanel,
// calendar/CalendarActions.qml); queries.js decides what a cell shows and
// what each key does.
Scope {
    id: root

    readonly property bool open: CalendarFullShared.screen !== ""

    readonly property var data: CalendarPanel.data
    readonly property date now: CalendarPanel.now
    property date selected: new Date()

    readonly property int year: selected.getFullYear()
    readonly property int month: selected.getMonth()
    readonly property var grid: Q.monthGrid(year, month)
    readonly property var legend: data ? Q.monthCalendars(data, year, month + 1) : []
    readonly property var events: Q.dayEvents(data, selected)
    readonly property string stale: Q.staleText(data, now)

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("calendarfull");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        selected = Q.addDays(now, 0);
        CalendarPanel.reload();
        CalendarFullShared.screen = window.screen.name;
    }

    function close(): void {
        CalendarFullShared.screen = "";
    }

    function select(date: date): void {
        selected = date;
    }

    // Closed first: the drop-down's opening closes every other open one.
    function showDropdown(): void {
        const screen = CalendarFullShared.screen;
        close();
        CalendarPanel.showRequested(screen, Q.ymd(selected));
    }

    // Does what queries.js's bigViewKey() answered; false for "none".
    function act(action: var): bool {
        switch (action.do) {
        case "close":
            close();
            break;
        case "move":
        case "today":
            select(Q.bigViewMove(selected, action, now));
            break;
        case "sync":
            actions.sync();
            break;
        case "web":
            actions.openWeb(selected);
            break;
        case "dropdown":
            showDropdown();
            break;
        default:
            return false;
        }
        return true;
    }

    onSelectedChanged: eventsView.contentY = 0

    CalendarActions {
        id: actions

        active: root.open
    }

    Component.onCompleted: Dropdowns.add("calendarfull", CalendarFullShared)

    Connections {
        target: CalendarFullShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
        function onShowRequested(screen, day) {
            if (!root.open)
                root.toggle(screen);
            root.select(Q.parseLocal(day));
        }
    }

    IpcHandler {
        target: "calendarfull"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    PanelWindow {
        id: window

        visible: root.open
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "desk-calendar-full"
        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: Style.veil
        }

        // A click off the card closes.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            readonly property var names: ({
                    [Qt.Key_Escape]: "Esc",
                    [Qt.Key_Left]: "Left",
                    [Qt.Key_Right]: "Right",
                    [Qt.Key_Up]: "Up",
                    [Qt.Key_Down]: "Down",
                    [Qt.Key_PageUp]: "PgUp",
                    [Qt.Key_PageDown]: "PgDn",
                    [Qt.Key_Return]: "Enter",
                    [Qt.Key_Enter]: "Enter",
                    [Qt.Key_T]: "T",
                    [Qt.Key_R]: "R",
                    [Qt.Key_O]: "O",
                    [Qt.Key_F]: "F"
                })

            focus: true
            Keys.onPressed: event => {
                const name = names[event.key];
                if (name === undefined)
                    return;
                // A held key's auto-repeat acts only for the moving keys; the
                // others' are swallowed.
                if (event.isAutoRepeat && !Q.bigViewRepeats(name)) {
                    event.accepted = true;
                    return;
                }
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                if (root.act(Q.bigViewKey(name, plain)))
                    event.accepted = true;
            }
        }

        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            offset.y: 18
            blur: 50
            color: Qt.rgba(0, 0, 0, 0.55)
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: Math.round(parent.width * 0.8)
            height: Math.round(parent.height * 0.8)
            radius: Style.radius
            clip: true
            color: Style.surface
            border.width: 1
            border.color: Theme.purple

            // Keeps clicks on the card from reaching the close area behind it.
            MouseArea {
                anchors.fill: parent
            }

            // Month and week.
            Item {
                id: header

                x: 1
                y: 1
                width: parent.width - 2
                height: monthTitle.implicitHeight + 28

                Text {
                    id: monthTitle

                    x: 20
                    y: 16
                    text: Q.monthTitle(root.year, root.month)
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.baseline: monthTitle.baseline
                    text: Q.headerNote(actions.syncing || actions.timerSyncing, root.selected, root.now)
                    color: Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }
            }

            Item {
                id: body

                x: 1
                anchors.top: header.bottom
                anchors.bottom: footer.top
                width: parent.width - 2

                // The month grid: week numbers, then Monday to Sunday, the
                // rows sharing the height.
                Item {
                    id: monthGrid

                    readonly property real weekWidth: 40
                    readonly property real gap: 4
                    readonly property real headHeight: 24
                    readonly property real cellWidth: (width - weekWidth - 7 * gap) / 7
                    readonly property real cellHeight: (height - headHeight - root.grid.length * gap) / root.grid.length

                    x: 16
                    width: (side.visible ? side.x : parent.width) - x - 16
                    height: parent.height - 12

                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                        Text {
                            required property string modelData
                            required property int index

                            x: monthGrid.weekWidth + monthGrid.gap + index * (monthGrid.cellWidth + monthGrid.gap)
                            width: monthGrid.cellWidth
                            height: monthGrid.headHeight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: index > 4 ? Theme.pink : Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    Repeater {
                        model: root.grid

                        Item {
                            id: week

                            required property var modelData
                            required property int index

                            y: monthGrid.headHeight + monthGrid.gap + index * (monthGrid.cellHeight + monthGrid.gap)
                            width: monthGrid.width
                            height: monthGrid.cellHeight

                            Text {
                                width: monthGrid.weekWidth
                                height: parent.height
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: week.modelData.week
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }

                            Repeater {
                                model: week.modelData.days

                                MonthCell {
                                    required property var modelData
                                    required property int index

                                    x: monthGrid.weekWidth + monthGrid.gap + index * (monthGrid.cellWidth + monthGrid.gap)
                                    width: monthGrid.cellWidth
                                    height: week.height
                                    day: modelData
                                    source: root.data
                                    inMonth: modelData.getMonth() === root.month
                                    weekend: index > 4
                                    today: Q.ymd(modelData) === Q.ymd(root.now)
                                    chosen: Q.ymd(modelData) === Q.ymd(root.selected)
                                    onPicked: root.select(modelData)
                                }
                            }
                        }
                    }
                }

                // The selected day: its events, then which colour is which
                // calendar.
                Item {
                    id: side

                    visible: CalendarPanel.present
                    x: parent.width - width
                    width: 400
                    height: parent.height

                    Rectangle {
                        width: 1
                        height: parent.height
                        color: Theme.currentLine
                    }

                    Item {
                        id: dayHead

                        x: 1
                        width: parent.width - 1
                        height: dayTitle.implicitHeight + 16

                        Text {
                            id: dayTitle

                            x: 14
                            y: 6
                            text: Q.longDate(root.selected)
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.baseline: dayTitle.baseline
                            text: Q.dayLine(root.events.length, root.selected, root.now)
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }

                    Text {
                        visible: root.events.length === 0
                        x: 1
                        anchors.top: dayHead.bottom
                        leftPadding: 14
                        topPadding: 6
                        text: Q.inWindow(root.data, root.selected) ? "Nothing on this day." : "Outside the synced months."
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                    }

                    // Scrolls when the day has more events than fit.
                    Flickable {
                        id: eventsView

                        visible: root.events.length > 0
                        x: 9
                        width: parent.width - 17
                        anchors.top: dayHead.bottom
                        anchors.bottom: legendFlow.top
                        anchors.bottomMargin: 8
                        clip: true
                        contentWidth: width
                        contentHeight: eventList.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: eventList

                            width: eventsView.width
                            spacing: 2

                            Repeater {
                                model: root.events

                                Item {
                                    id: event

                                    required property var modelData
                                    readonly property var shown: Q.row(modelData, root.selected, root.now)

                                    width: eventList.width
                                    height: Math.max(26, eventText.implicitHeight, eventTime.implicitHeight) + 12
                                    opacity: shown.over ? 0.5 : 1

                                    Rectangle {
                                        x: 8
                                        y: 6
                                        width: 4
                                        height: parent.height - 12
                                        radius: 2
                                        color: event.modelData.color
                                    }

                                    Column {
                                        id: eventTime

                                        x: 22
                                        width: 104
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            text: event.shown.time
                                            color: Style.soft
                                            font.family: Theme.fontMono
                                            font.pixelSize: 12
                                        }

                                        Text {
                                            visible: event.shown.tzUnknown
                                            text: "time zone unknown"
                                            color: Theme.orange
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                        }
                                    }

                                    Column {
                                        id: eventText

                                        x: 22 + 104 + 8
                                        width: parent.width - x - 8
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: event.modelData.title
                                            textFormat: Text.PlainText
                                            color: Theme.foreground
                                            font.family: Theme.fontUi
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: event.shown.sub
                                            textFormat: Text.PlainText
                                            color: Theme.comment
                                            font.family: Theme.fontMono
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Which colour is which calendar, wrapping.
                    Flow {
                        id: legendFlow

                        visible: root.legend.length > 0
                        x: 15
                        width: parent.width - 29
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        spacing: 14

                        Repeater {
                            model: root.legend

                            Row {
                                id: legendEntry

                                required property var modelData

                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: legendEntry.modelData.color
                                }

                                Text {
                                    width: Math.min(implicitWidth, legendFlow.width - 11)
                                    elide: Text.ElideRight
                                    text: legendEntry.modelData.name
                                    textFormat: Text.PlainText
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }

            // Keys, or the state of the data.
            KeyHints {
                id: footer

                x: 1
                width: parent.width - 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                keys: [["←→↑↓", "day"], ["PgUp PgDn", "month"], ["T", "today"], ["F", "drop-down"], ["O", "open in Nextcloud"], ["Esc", "close"], ["R", "sync"]]
                message: actions.flash !== "" ? actions.flash : !CalendarPanel.present ? "No calendar is set up. Events appear once the sync service has run." : root.stale
                messageColor: actions.flash !== "" ? Theme.yellow : CalendarPanel.present ? Theme.orange : Theme.comment
            }
        }
    }
}
