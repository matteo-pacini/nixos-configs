import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.calendar
import qs.common
import "calendar/queries.js" as Q

// The calendar panel, hanging under the bar's clock on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call calendar toggle
// A month with ISO weeks and one dot per calendar with events on a day, and
// the selected day's events under it. Read-only: events come from the export
// calendar-sync writes (CalendarPanel), R runs that sync now, Enter or O
// opens the day in the Nextcloud web calendar, and F swaps this panel for the
// big view (CalendarFull.qml) on the same day.
Scope {
    id: root

    readonly property bool open: CalendarPanel.screen !== ""
    readonly property int panelWidth: 360

    readonly property color soft: Style.soft
    readonly property color dim: Qt.tint(Theme.background, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.55))

    readonly property var data: CalendarPanel.data
    readonly property date now: CalendarPanel.now
    property date selected: new Date()

    readonly property int year: selected.getFullYear()
    readonly property int month: selected.getMonth()
    readonly property var grid: Q.monthGrid(year, month)
    readonly property bool thisMonth: year === now.getFullYear() && month === now.getMonth()
    readonly property var dots: data ? Q.monthDots(data, year, month + 1, 3) : ({})
    readonly property var legend: data ? Q.monthCalendars(data, year, month + 1) : []
    readonly property var events: Q.dayEvents(data, selected)
    readonly property string stale: Q.staleText(data, now)

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("calendar");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        selected = Q.addDays(now, 0);
        CalendarPanel.reload();
        CalendarPanel.screen = window.screen.name;
    }

    function close(): void {
        CalendarPanel.screen = "";
    }

    function select(date: date): void {
        selected = date;
    }

    // Closed first: the big view's opening closes every open drop-down.
    function showFull(): void {
        const screen = CalendarPanel.screen;
        close();
        CalendarFullShared.showRequested(screen, Q.ymd(selected));
    }

    // Returns true when the key was used.
    function key(k: int, plain: bool): bool {
        if (k === Qt.Key_Escape) {
            close();
        } else if (k === Qt.Key_Left) {
            select(Q.addDays(selected, -1));
        } else if (k === Qt.Key_Right) {
            select(Q.addDays(selected, 1));
        } else if (k === Qt.Key_Up) {
            select(Q.addDays(selected, -7));
        } else if (k === Qt.Key_Down) {
            select(Q.addDays(selected, 7));
        } else if (k === Qt.Key_PageUp) {
            select(Q.addMonths(selected, -1));
        } else if (k === Qt.Key_PageDown) {
            select(Q.addMonths(selected, 1));
        } else if (k === Qt.Key_T && plain) {
            select(Q.addDays(now, 0));
        } else if (k === Qt.Key_R && plain) {
            actions.sync();
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_O && plain)) {
            actions.openWeb(selected);
        } else if (k === Qt.Key_F && plain) {
            showFull();
        } else {
            return false;
        }
        return true;
    }

    CalendarActions {
        id: actions

        active: root.open
    }

    Component.onCompleted: Dropdowns.add("calendar", CalendarPanel)

    Connections {
        target: CalendarPanel

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
        target: "calendar"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    // The two lines of an event row, for the empty day's height.
    FontMetrics {
        id: titleMetrics

        font.family: Theme.fontUi
        font.pixelSize: 14
        font.weight: Font.Medium
    }

    FontMetrics {
        id: subMetrics

        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // One dot per calendar, in its own colour. On the purple today cell each
    // gets a ring in the background colour so a dark or purple calendar
    // colour still shows.
    component Dots: Row {
        property var cals: []
        property bool onToday

        spacing: 2

        Repeater {
            model: parent.cals

            Rectangle {
                required property var modelData

                width: parent.onToday ? 6 : 4
                height: width
                radius: width / 2
                color: modelData.color
                border.width: parent.onToday ? 1 : 0
                border.color: Theme.background
            }
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
        WlrLayershell.namespace: "desk-calendar"
        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // A click off the panel closes it, the bar's clock included.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                // Of a held key's auto-repeats, only the moving keys' act.
                if (event.isAutoRepeat && ![Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown].includes(event.key))
                    return;
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                if (root.key(event.key, plain))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("calendar", CalendarPanel.screen) : -1
            centredFallback: true
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // Month and week.
                Item {
                    width: parent.width
                    height: monthTitle.implicitHeight + 16

                    Text {
                        id: monthTitle

                        x: 14
                        y: 12
                        text: Q.monthTitle(root.year, root.month)
                        color: Theme.foreground
                        font.family: Theme.fontUi
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Mono {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.baseline: monthTitle.baseline
                        font.pixelSize: 12
                        text: {
                            if (actions.syncing || actions.timerSyncing)
                                return "syncing…";
                            if (root.thisMonth)
                                return `week ${Q.isoWeek(root.selected)}`;
                            return `weeks ${root.grid[0].week} to ${root.grid[root.grid.length - 1].week}`;
                        }
                    }
                }

                // The month grid: week numbers, then Monday to Sunday.
                Grid {
                    id: monthGrid

                    readonly property real cellWidth: (width - 26 - 7 * 2) / 7

                    x: 12
                    width: parent.width - 24
                    topPadding: 4
                    bottomPadding: 8
                    columns: 8
                    columnSpacing: 2
                    rowSpacing: 2

                    Item {
                        width: 26
                        height: 20
                    }

                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]

                        Mono {
                            required property string modelData
                            required property int index

                            width: monthGrid.cellWidth
                            height: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: index > 4 ? Theme.pink : Theme.comment
                            opacity: index > 4 ? 0.75 : 1
                        }
                    }

                    Repeater {
                        model: root.grid.length * 8

                        Item {
                            id: cell

                            required property int index
                            readonly property int column: index % 8
                            readonly property var week: root.grid[Math.floor(index / 8)]
                            readonly property date day: column > 0 ? week.days[column - 1] : new Date(0)
                            readonly property bool inMonth: column > 0 && day.getMonth() === root.month
                            readonly property bool weekend: column > 5
                            readonly property bool today: column > 0 && Q.ymd(day) === Q.ymd(root.now)
                            readonly property bool chosen: column > 0 && Q.ymd(day) === Q.ymd(root.selected)

                            width: column === 0 ? 26 : monthGrid.cellWidth
                            height: 30

                            Mono {
                                visible: cell.column === 0
                                anchors.centerIn: parent
                                text: cell.week.week
                                font.pixelSize: 10
                            }

                            Rectangle {
                                visible: cell.column > 0
                                anchors.fill: parent
                                radius: 6
                                color: cell.today && cell.inMonth ? Theme.purple : dayArea.containsMouse ? Theme.currentLine : "transparent"
                                border.width: cell.chosen ? 1 : 0
                                border.color: Theme.pink

                                Text {
                                    anchors.centerIn: parent
                                    text: cell.day.getDate()
                                    color: cell.today && cell.inMonth ? Theme.background : !cell.inMonth ? (cell.weekend ? Qt.tint(root.dim, Qt.rgba(Theme.pink.r, Theme.pink.g, Theme.pink.b, 0.25)) : root.dim) : cell.weekend ? Theme.pink : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 13
                                    font.weight: cell.today && cell.inMonth ? Font.DemiBold : Font.Normal
                                }

                                Dots {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: onToday ? 2 : 3
                                    cals: cell.inMonth ? root.dots[cell.day.getDate()] ?? [] : []
                                    onToday: cell.today
                                }

                                MouseArea {
                                    id: dayArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.select(cell.day)
                                }
                            }
                        }
                    }
                }

                // Which colour is which calendar, on one line.
                Row {
                    visible: root.legend.length > 0
                    x: 14
                    width: parent.width - 28
                    clip: true
                    bottomPadding: 8
                    spacing: 14

                    Repeater {
                        model: root.legend

                        Row {
                            required property var modelData

                            spacing: 5

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: parent.modelData.color
                            }

                            Mono {
                                text: parent.modelData.name
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                // The selected day's events.
                Column {
                    visible: CalendarPanel.present
                    width: parent.width

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.currentLine
                    }

                    Item {
                        width: parent.width
                        height: dayTitle.implicitHeight + 12

                        Text {
                            id: dayTitle

                            x: 14
                            y: 8
                            text: Q.longDate(root.selected)
                            color: Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Mono {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.baseline: dayTitle.baseline
                            font.pixelSize: 12
                            text: Q.dayLine(root.events.length, root.selected, root.now)
                        }
                    }

                    // As tall as a one-event list, so stepping between empty
                    // days and single-event days, the common case, keeps the
                    // panel still.
                    Mono {
                        visible: root.events.length === 0
                        height: Math.max(26, Math.ceil(titleMetrics.height) + Math.ceil(subMetrics.height)) + 12 + 6
                        leftPadding: 14
                        bottomPadding: 6
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        text: Q.inWindow(root.data, root.selected) ? "Nothing on this day." : "Outside the synced months."
                    }

                    Column {
                        visible: root.events.length > 0
                        x: 8
                        width: parent.width - 16
                        bottomPadding: 6
                        spacing: 2

                        Repeater {
                            model: root.events

                            Item {
                                id: event

                                required property var modelData
                                readonly property var shown: Q.row(modelData, root.selected, root.now)

                                width: parent.width
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
                                        color: root.soft
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }

                                    Mono {
                                        visible: event.shown.tzUnknown
                                        text: "time zone unknown"
                                        color: Theme.orange
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

                                    Mono {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: event.shown.sub
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }
                }

                // Keys, or the state of the data.
                KeyHints {
                    keys: [["←→↑↓", "day"], ["PgUp PgDn", "month"], ["T", "today"], ["F", "full screen"], ["O", "open in Nextcloud"], ["Esc", "close"], ["R", "sync"]]
                    message: actions.flash !== "" ? actions.flash : !CalendarPanel.present ? "No calendar is set up. Events appear once the sync service has run." : root.stale
                    messageColor: actions.flash !== "" ? Theme.yellow : CalendarPanel.present ? Theme.orange : Theme.comment
                }
            }
        }
    }
}
