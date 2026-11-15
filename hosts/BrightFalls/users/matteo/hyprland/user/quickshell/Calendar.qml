import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.audio
import qs.bluetooth
import qs.calendar
import qs.network
import qs.system
import "calendar/queries.js" as Q

// The calendar panel, hanging under the bar's clock on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call calendar toggle
// A month with ISO weeks and one dot per calendar with events on a day, and
// the selected day's events under it. Read-only: events come from the export
// calendar-sync writes (CalendarPanel), R runs that sync now, and Enter or O
// opens the day in the Nextcloud web calendar.
Scope {
    id: root

    readonly property bool open: CalendarPanel.screen !== ""
    // Bar.qml: 6 px margin plus the bar's 34 px, then the 8 px gap that
    // everything under the bar keeps.
    readonly property int top: 6 + 34 + 8
    readonly property int panelWidth: 360

    // ~/.local/share/desk/calendar/source.json names the file holding the
    // CalDAV base; that address is a secret, read only when O is pressed.
    readonly property string sourcePath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/calendar/source.json"

    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))
    readonly property color dim: Qt.tint(Theme.background, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.55))

    readonly property var data: CalendarPanel.data
    readonly property date now: CalendarPanel.now
    property date selected: new Date()
    property string flash: ""
    property bool syncing: false
    property bool timerSyncing: false

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
        if (Panel.screen !== "")
            Panel.toggleRequested(Panel.screen);
        if (AudioPanel.screen !== "")
            AudioPanel.toggleRequested(AudioPanel.screen);
        if (SystemPanel.screen !== "")
            SystemPanel.toggleRequested(SystemPanel.screen);
        if (Bt.screen !== "")
            Bt.toggleRequested(Bt.screen);
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        selected = Q.addDays(now, 0);
        flash = "";
        CalendarPanel.reload();
        CalendarPanel.screen = window.screen.name;
        activeQuery.running = true;
    }

    function close(): void {
        CalendarPanel.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function select(date: date): void {
        selected = date;
    }

    function sync(): void {
        if (syncing)
            return;
        syncing = true;
        syncProc.running = true;
    }

    function openWeb(): void {
        sourceFile.reload();
        let urlFile = "";
        try {
            urlFile = JSON.parse(sourceFile.text()).url_file ?? "";
        } catch (e) {}
        if (typeof urlFile !== "string" || urlFile === "") {
            say("No calendar server is set up yet.");
            return;
        }
        webProc.day = selected;
        webProc.command = ["head", "-n", "1", urlFile];
        webProc.running = true;
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
            sync();
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || (k === Qt.Key_O && plain)) {
            openWeb();
        } else {
            return false;
        }
        return true;
    }

    Timer {
        id: flashTimer

        interval: 3500
        onTriggered: root.flash = ""
    }

    // Catches syncs the service's timer starts while the panel is open.
    Timer {
        interval: 3000
        running: root.open
        repeat: true
        onTriggered: activeQuery.running = true
    }

    Process {
        id: activeQuery

        command: ["systemctl", "--user", "is-active", "calendar-sync.service"]
        stdout: StdioCollector {
            onStreamFinished: root.timerSyncing = text.trim() === "activating"
        }
    }

    // A oneshot: start returns when the sync and the export have finished.
    Process {
        id: syncProc

        command: ["systemctl", "--user", "start", "calendar-sync.service"]
        onExited: code => {
            root.syncing = false;
            if (code === 5)
                root.say("Calendar sync is not installed yet.");
            else if (code !== 0)
                root.say("Sync failed: journalctl --user -u calendar-sync says why.");
        }
    }

    Process {
        id: webProc

        property date day

        // SplitParser, not StdioCollector: the address is used once and not
        // kept in a property.
        stdout: SplitParser {
            onRead: line => {
                const url = Q.webUrl(line, webProc.day);
                if (url === "")
                    root.say("The calendar server address is not a Nextcloud one.");
                else
                    Quickshell.execDetached(["uwsm", "app", "--", "xdg-open", url]);
            }
        }
        onExited: code => {
            if (code !== 0)
                root.say("The calendar server address cannot be read.");
        }
    }

    FileView {
        id: sourceFile

        path: root.sourcePath
        printErrors: false
        blockLoading: true
    }

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
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                if (root.key(event.key, plain))
                    event.accepted = true;
            }
        }

        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            offset.y: 12
            blur: 36
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Rectangle {
            id: card

            readonly property real centre: root.open ? CalendarPanel.iconCentre(CalendarPanel.screen) : -1

            x: centre < 0 ? Math.round((window.width - width) / 2) : Math.max(6, Math.min(window.width - width - 6, Math.round(centre - width / 2)))
            y: root.top
            width: root.panelWidth
            height: content.implicitHeight + 2
            radius: 10
            clip: true
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.96)
            border.width: 1
            border.color: Theme.purple

            Behavior on height {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutQuint
                }
            }

            // Keeps clicks on the panel from reaching the close area.
            MouseArea {
                anchors.fill: parent
            }

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
                            if (root.syncing || root.timerSyncing)
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
                                        color: Theme.foreground
                                        font.family: Theme.fontUi
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Mono {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: event.shown.sub
                                    }
                                }
                            }
                        }
                    }
                }

                // Keys, or the state of the data.
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.currentLine
                }

                Item {
                    readonly property string message: root.flash !== "" ? root.flash : !CalendarPanel.present ? "No calendar is set up. Events appear once the sync service has run." : root.stale

                    width: parent.width
                    height: (message !== "" ? messageText.implicitHeight : hints.implicitHeight) + 16

                    Flow {
                        id: hints

                        visible: parent.message === ""
                        x: 14
                        y: 8
                        width: parent.width - 28
                        spacing: 14

                        Repeater {
                            model: [["←→↑↓", "day"], ["PgUp PgDn", "month"], ["T", "today"], ["O", "open in Nextcloud"], ["Esc", "close"], ["R", "sync"]]

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

                    Mono {
                        id: messageText

                        visible: parent.message !== ""
                        x: 14
                        y: 8
                        width: parent.width - 28
                        wrapMode: Text.Wrap
                        text: parent.message
                        color: root.flash !== "" ? Theme.yellow : CalendarPanel.present ? Theme.orange : Theme.comment
                    }
                }
            }
        }
    }
}
