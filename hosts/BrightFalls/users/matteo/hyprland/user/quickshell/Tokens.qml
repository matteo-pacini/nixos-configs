import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.tokens
import "tokens/tokens.js" as T

// The token panel, hanging under the bar's token item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call tokens toggle
// Four pages: the overview with the plan limits, the projects of a period,
// one project, the last 14 days. tokens.js decides everything drawn and what
// each key does; this file draws its view and passes keys on.
Scope {
    id: root

    readonly property bool open: TokensShared.open
    readonly property int panelWidth: 420

    readonly property var v: open ? T.view(TokensShared.st, TokensShared.limits, TokensShared.plan) : null

    // The views' colour keys.
    function tone(name: string): color {
        switch (name) {
        case "purple":
            return Theme.purple;
        case "pink":
            return Theme.pink;
        case "cyan":
            return Theme.cyan;
        case "green":
            return Theme.green;
        case "orange":
            return Theme.orange;
        case "red":
            return Theme.red;
        case "grey":
        case "muted":
            return Theme.comment;
        default:
            return Theme.foreground;
        }
    }

    // For view text placed inside styled text ("<1%").
    function esc(text: string): string {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("tokens");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        TokensShared.screen = window.screen.name;
    }

    function close(): void {
        TokensShared.screen = "";
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const k = event.key;
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const always = {
            [Qt.Key_Escape]: "Esc",
            [Qt.Key_Up]: "Up",
            [Qt.Key_Down]: "Down",
            [Qt.Key_PageUp]: "PgUp",
            [Qt.Key_PageDown]: "PgDn",
            [Qt.Key_Return]: "Enter",
            [Qt.Key_Enter]: "Enter"
        };
        const letters = {
            [Qt.Key_Tab]: "Tab",
            [Qt.Key_P]: "P",
            [Qt.Key_D]: "D",
            [Qt.Key_R]: "R",
            [Qt.Key_S]: "S"
        };
        const name = always[k] ?? (plain ? letters[k] : undefined);
        if (name === undefined)
            return false;
        return TokensShared.key(name, event.isAutoRepeat);
    }

    Component.onCompleted: Dropdowns.add("tokens", TokensShared)

    Connections {
        target: TokensShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "tokens"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component Label: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.88
    }

    component Small: Text {
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        color: Theme.comment
        font.family: Theme.fontUi
        font.pixelSize: 12
    }

    // A section: a line over it, then its label and its rows.
    component Section: Column {
        id: section

        property string label
        property string chip
        default property alias body: inner.data

        width: parent ? parent.width : 0
        spacing: 0

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.currentLine
        }

        Item {
            width: 1
            height: 8
        }

        Row {
            visible: section.label !== ""
            spacing: 6
            bottomPadding: 4

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: section.label.toUpperCase()
            }

            Rectangle {
                visible: section.chip !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: chipText.implicitWidth + 10
                height: chipText.implicitHeight + 2
                radius: 5
                color: "transparent"
                border.width: 1
                border.color: Theme.currentLine

                Text {
                    id: chipText

                    anchors.centerIn: parent
                    text: section.chip
                    color: Theme.comment
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                }
            }
        }

        Column {
            id: inner

            width: parent.width
            spacing: 2
        }
    }

    // A label on the left, a value on the right; the value wraps when it
    // does not fit beside the label.
    component Pair: Item {
        id: pair

        property string name
        property string value
        property string note
        property color colour: Theme.foreground
        property real size: 13

        width: parent ? parent.width : 0
        height: Math.max(leftText.implicitHeight, rightText.implicitHeight)

        Text {
            id: leftText

            width: Math.min(implicitWidth, pair.width * 0.6)
            text: pair.name
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: pair.colour
            font.family: Theme.fontUi
            font.pixelSize: pair.size
        }

        Text {
            id: rightText

            anchors.right: parent.right
            width: Math.min(implicitWidth, pair.width - leftText.width - 10)
            horizontalAlignment: Text.AlignRight
            text: pair.note === "" ? root.esc(pair.value) : `${root.esc(pair.value)} <font color="${Theme.comment}">${root.esc(pair.note)}</font>`
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            color: pair.colour
            font.family: Theme.fontUi
            font.pixelSize: pair.size
        }
    }

    // A project name, which may elide, and a value that keeps its place, with
    // a muted note before it.
    component NameValue: Item {
        id: nv

        property string name
        property string value
        property string note

        width: parent ? parent.width : 0
        height: values.implicitHeight

        Text {
            width: nv.width - values.implicitWidth - 10
            text: nv.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontUi
            font.pixelSize: 13
        }

        Row {
            id: values

            anchors.right: parent.right
            spacing: 10

            Text {
                visible: nv.note !== ""
                text: nv.note
                textFormat: Text.PlainText
                color: Theme.comment
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            Text {
                text: nv.value
                textFormat: Text.PlainText
                color: Theme.foreground
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
        }
    }

    component Meter: Rectangle {
        property real frac
        property color fill

        width: parent ? parent.width : 0
        height: 8
        radius: 4
        color: Style.track

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.frac))
            height: parent.height
            radius: parent.radius
            color: parent.fill
        }
    }

    // Segments side by side, each its share of the width.
    component SplitBar: Row {
        id: split

        property var parts: []
        property real barHeight: 12

        width: parent ? parent.width : 0
        height: barHeight

        Repeater {
            model: split.parts

            Rectangle {
                required property var modelData

                width: split.width * modelData.frac
                height: split.barHeight
                color: root.tone(modelData.colour)
            }
        }
    }

    // Fourteen days of output, oldest first, with the dates under them.
    component Bars: Column {
        id: bars

        property var info: null

        width: parent ? parent.width : 0
        spacing: 2

        Item {
            id: plot

            width: parent.width
            height: 46

            Repeater {
                model: bars.info ? bars.info.bars : []

                Rectangle {
                    required property var modelData
                    required property int index

                    readonly property real slot: (plot.width + 2) / 14

                    x: index * slot
                    width: slot - 2
                    height: 42 * modelData.frac
                    y: plot.height - height
                    radius: 1.5
                    color: root.tone(modelData.colour)
                }
            }
        }

        Item {
            width: parent.width
            height: Math.max(leftDay.implicitHeight, middleDay.implicitHeight)

            Small {
                id: leftDay

                width: implicitWidth
                text: bars.info ? bars.info.left : ""
            }

            Small {
                id: middleDay

                width: Math.min(implicitWidth, parent.width - leftDay.implicitWidth - rightDay.implicitWidth - 20)
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: bars.info ? bars.info.middle : ""
            }

            Small {
                id: rightDay

                width: implicitWidth
                anchors.right: parent.right
                text: bars.info ? bars.info.right : ""
            }
        }
    }

    // The first read's progress, in place of what it has not reached.
    component Building: Section {
        id: build

        property var info: null

        label: info ? info.label : ""

        Pair {
            name: build.info ? build.info.line : ""
            value: build.info ? build.info.pct : ""
            colour: Theme.comment
        }

        Meter {
            frac: build.info ? build.info.frac : 0
            fill: Theme.purple
        }

        Small {
            topPadding: 2
            text: build.info ? build.info.note : ""
        }
    }

    // Today, 7 days, 30 days; the one shown is lit.
    component Periods: Rectangle {
        id: seg

        property var periods: []

        width: segRow.implicitWidth + 2
        height: segRow.implicitHeight + 2
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: Theme.currentLine
        clip: true

        Row {
            id: segRow

            x: 1
            y: 1

            Repeater {
                model: seg.periods

                Rectangle {
                    required property var modelData

                    width: segText.implicitWidth + 14
                    height: segText.implicitHeight + 2
                    color: modelData.on ? Theme.currentLine : "transparent"

                    Text {
                        id: segText

                        anchors.centerIn: parent
                        text: parent.modelData.label
                        color: parent.modelData.on ? Theme.foreground : Theme.comment
                        font.family: Theme.fontUi
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // The title, and on the right either a muted line or the periods. Only a
    // project name in the title may elide.
    component Head: Item {
        id: head

        property string title
        property string meta
        property var periods: null

        width: parent ? parent.width : 0
        height: Math.max(titleText.implicitHeight, right.height) + 6

        Text {
            id: titleText

            width: Math.min(implicitWidth, head.width - right.width - 10)
            anchors.verticalCenter: right.verticalCenter
            text: head.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Item {
            id: right

            anchors.right: parent.right
            width: head.periods ? seg.width : metaText.implicitWidth
            height: head.periods ? seg.height : metaText.implicitHeight

            Periods {
                id: seg

                visible: head.periods !== null
                periods: head.periods ?? []
            }

            Text {
                id: metaText

                visible: head.periods === null
                text: head.meta
                color: Theme.comment
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
        }
    }

    // A grid row of fixed columns; `cells` are [text, width, right-aligned,
    // colour], a width of 0 takes what the others leave.
    component GridRow: Item {
        id: gr

        property var cells: []
        property real size: 12
        property bool header: false

        width: parent ? parent.width : 0
        height: probe.implicitHeight + 2

        Text {
            id: probe

            visible: false
            text: "0"
            font.family: Theme.fontMono
            font.pixelSize: gr.size
        }

        Repeater {
            model: gr.cells

            Text {
                required property var modelData
                required property int index

                readonly property real fixed: gr.cells.reduce((sum, c) => sum + c[1], 0)
                readonly property real spare: gr.width - fixed - 8 * (gr.cells.length - 1)

                x: gr.cells.slice(0, index).reduce((sum, c) => sum + (c[1] > 0 ? c[1] : spare) + 8, 0)
                width: modelData[1] > 0 ? modelData[1] : spare
                horizontalAlignment: modelData[2] ? Text.AlignRight : Text.AlignLeft
                text: modelData[0]
                textFormat: Text.PlainText
                color: gr.header ? Theme.comment : root.tone(modelData[3] ?? "fg")
                font.family: Theme.fontMono
                font.pixelSize: gr.header ? 11 : gr.size
            }
        }
    }

    // One project on the projects page.
    component ProjectRow: Rectangle {
        id: pr

        property var row

        width: parent ? parent.width : 0
        height: prColumn.implicitHeight + 9
        radius: 6
        color: row.selected ? Theme.currentLine : "transparent"

        Rectangle {
            visible: pr.row.selected
            width: 3
            height: parent.height
            radius: 1.5
            color: Theme.purple
        }

        Column {
            id: prColumn

            x: 8
            y: 4
            width: parent.width - 14
            spacing: 2

            Item {
                width: parent.width
                height: outputText.implicitHeight

                Text {
                    width: parent.width - outputText.implicitWidth - 10
                    text: pr.row.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                Text {
                    id: outputText

                    anchors.right: parent.right
                    text: `${root.esc(pr.row.output)} <font color="${Theme.comment}">${root.esc(pr.row.share)}</font>`
                    textFormat: Text.StyledText
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
            }

            Rectangle {
                width: parent.width
                height: 3
                radius: 1.5
                color: Style.track

                Rectangle {
                    width: parent.width * pr.row.shareFrac
                    height: parent.height
                    radius: parent.radius
                    color: Theme.purple
                }
            }

            // The line wraps, never the cost, when both do not fit.
            Item {
                width: parent.width
                height: Math.max(6, lineText.implicitHeight, rowCost.implicitHeight)

                SplitBar {
                    width: 40
                    barHeight: 6
                    anchors.verticalCenter: lineText.lineCount > 1 ? undefined : parent.verticalCenter
                    y: lineText.lineCount > 1 ? 4 : 0
                    parts: pr.row.split
                }

                Text {
                    id: lineText

                    x: 46
                    width: parent.width - 46 - (rowCost.text !== "" ? rowCost.implicitWidth + 10 : 0)
                    text: pr.row.line
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.comment
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                }

                Text {
                    id: rowCost

                    anchors.right: parent.right
                    text: pr.row.cost
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                }
            }
        }
    }

    component Card: DropCard {
        cardWidth: root.panelWidth
        contentHeight: content.implicitHeight

        Column {
            id: content

            x: 1
            y: 1
            width: parent.width - 2

            // Only this when the helper cannot run.
            Text {
                visible: root.v !== null && root.v.single !== ""
                width: parent.width
                padding: 14
                text: root.v ? root.v.single : ""
                wrapMode: Text.Wrap
                color: Style.soft
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            Column {
                id: page

                visible: root.v !== null && root.v.single === ""
                x: 14
                width: parent.width - 28
                topPadding: 12
                bottomPadding: 10
                spacing: 8

                Column {
                    id: overview

                    readonly property var o: root.v ? root.v.overview : null

                    visible: o !== null
                    width: parent.width
                    spacing: 8

                    Head {
                        title: overview.o ? overview.o.title : ""
                        meta: overview.o ? overview.o.meta : ""
                    }

                    Small {
                        visible: text !== ""
                        text: overview.o ? overview.o.error : ""
                        color: Theme.orange
                    }

                    Section {
                        id: limitsSection

                        readonly property var l: overview.o ? overview.o.limits : null

                        label: overview.o ? overview.o.labels.limits : ""
                        chip: l && l.chip ? overview.o.labels.chip : ""

                        Text {
                            visible: limitsSection.l !== null && !limitsSection.l.known
                            width: parent.width
                            text: limitsSection.l ? limitsSection.l.line : ""
                            wrapMode: Text.Wrap
                            color: Theme.comment
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                        }

                        LimitRow {
                            row: limitsSection.l ? limitsSection.l.main : null
                        }

                        Meter {
                            visible: limitsSection.l !== null && limitsSection.l.meter !== null
                            frac: limitsSection.l?.meter?.frac ?? 0
                            fill: root.tone(limitsSection.l?.meter?.colour ?? "purple")
                        }

                        LimitRow {
                            row: limitsSection.l ? limitsSection.l.model : null
                        }

                        // The 5-hour row in the small size.
                        LimitRow {
                            row: limitsSection.l ? limitsSection.l.fiveHour : null
                            size: 12
                        }

                        Small {
                            visible: text !== ""
                            text: limitsSection.l ? limitsSection.l.foot : ""
                        }
                    }

                    Building {
                        visible: overview.o !== null && overview.o.olderBefore === "today"
                        info:overview.o ? overview.o.older : null
                    }

                    Section {
                        visible: overview.o !== null && overview.o.today !== null
                        label: overview.o ? overview.o.labels.today : ""

                        Pair {
                            name: overview.o ? overview.o.labels.output : ""
                            value: overview.o?.today?.output ?? ""
                        }

                        Pair {
                            name: overview.o ? overview.o.labels.cache : ""
                            value: overview.o?.today?.cache ?? ""
                            colour: Theme.comment
                        }

                        Pair {
                            visible: value !== ""
                            name: overview.o ? overview.o.labels.price : ""
                            value: overview.o?.today?.cost ?? ""
                        }
                    }

                    Building {
                        visible: overview.o !== null && overview.o.olderBefore === "last14"
                        info:overview.o ? overview.o.older : null
                    }

                    Section {
                        visible: overview.o !== null && overview.o.last14 !== null
                        label: overview.o ? overview.o.labels.last14 : ""

                        Bars {
                            info:overview.o ? overview.o.last14 : null
                        }
                    }

                    Building {
                        visible: overview.o !== null && overview.o.olderBefore === "last30"
                        info:overview.o ? overview.o.older : null
                    }

                    Section {
                        id: last30

                        readonly property var d: overview.o ? overview.o.last30 : null

                        visible: d !== null
                        label: overview.o ? overview.o.labels.last30 : ""

                        SplitBar {
                            parts: last30.d ? last30.d.split : []
                        }

                        Small {
                            topPadding: 2
                            text: last30.d ? last30.d.sentence : ""
                        }

                        Pair {
                            name: overview.o ? overview.o.labels.cacheHit : ""
                            value: last30.d ? last30.d.cacheHit : ""
                        }

                        Pair {
                            name: overview.o ? overview.o.labels.subagents : ""
                            value: last30.d ? last30.d.subagents : ""
                        }

                        Pair {
                            name: overview.o ? overview.o.labels.price : ""
                            value: last30.d ? last30.d.price : ""
                            note: last30.d ? last30.d.plan : ""
                        }

                        // Cost by type, then by model family: each name in
                        // its bar colour, tokens or share, the cost.
                        Item {
                            visible: last30.d !== null && last30.d.byType !== null
                            width: 1
                            height: 4
                        }

                        SplitBar {
                            visible: last30.d !== null && last30.d.byType !== null
                            barHeight: 8
                            parts: last30.d?.byType?.bar ?? []
                        }

                        Repeater {
                            model: last30.d?.byType?.rows ?? []

                            GridRow {
                                required property var modelData

                                cells: [[modelData.label, 0, false, modelData.colour], [modelData.tokens, 64, true, "muted"], [modelData.cost, 148, true]]
                            }
                        }

                        Item {
                            visible: last30.d !== null && last30.d.families !== null
                            width: 1
                            height: 4
                        }

                        Repeater {
                            model: last30.d?.families ?? []

                            GridRow {
                                required property var modelData

                                cells: [[modelData.name, 0, false, modelData.colour], [modelData.share, 64, true, "muted"], [modelData.cost, 148, true]]
                            }
                        }

                        Small {
                            visible: text !== ""
                            text: last30.d ? last30.d.unpriced : ""
                        }
                    }

                    Building {
                        visible: overview.o !== null && overview.o.olderBefore === "top7"
                        info:overview.o ? overview.o.older : null
                    }

                    Section {
                        id: top7

                        readonly property var d: overview.o ? overview.o.top7 : null

                        visible: d !== null
                        label: overview.o ? overview.o.labels.top7 : ""

                        Repeater {
                            model: top7.d ? top7.d.rows : []

                            NameValue {
                                required property var modelData

                                name: modelData.name
                                value: modelData.value
                                note: modelData.cost
                            }
                        }

                        Small {
                            visible: text !== ""
                            text: top7.d ? (top7.d.empty || top7.d.more) : ""
                        }
                    }

                    Small {
                        visible: text !== ""
                        text: overview.o ? overview.o.unreadable : ""
                    }
                }

                Column {
                    id: projects

                    readonly property var p: root.v ? root.v.projects : null

                    visible: p !== null
                    width: parent.width
                    spacing: 6

                    Head {
                        title: projects.p ? projects.p.title : ""
                        periods: projects.p ? projects.p.periods : []
                    }

                    Item {
                        visible: projects.p !== null && projects.p.state === "list"
                        width: parent.width
                        height: Math.max(summaryText.implicitHeight, rangeText.implicitHeight)

                        Small {
                            id: summaryText

                            width: Math.min(implicitWidth, parent.width - rangeText.implicitWidth - 10)
                            text: projects.p ? projects.p.summary : ""
                        }

                        Small {
                            id: rangeText

                            width: implicitWidth
                            anchors.right: parent.right
                            text: projects.p ? projects.p.range : ""
                        }
                    }

                    Section {
                        visible: projects.p !== null && projects.p.state === "list"

                        Repeater {
                            model: projects.p ? projects.p.rows : []

                            ProjectRow {
                                required property var modelData

                                row: modelData
                            }
                        }
                    }

                    Small {
                        visible: text !== ""
                        text: projects.p ? projects.p.unpriced : ""
                    }

                    Section {
                        visible: projects.p !== null && projects.p.state === "empty"

                        Text {
                            width: parent.width
                            topPadding: 14
                            bottomPadding: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: projects.p ? projects.p.empty.join("\n") : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.comment
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                        }
                    }

                    Building {
                        visible: projects.p !== null && projects.p.state === "building"
                        info:projects.p ? projects.p.building : null
                    }

                    Small {
                        visible: text !== ""
                        text: projects.p ? projects.p.error : ""
                        font.pixelSize: 13
                    }
                }

                Column {
                    id: detail

                    readonly property var d: root.v ? root.v.detail : null
                    readonly property bool shown: d !== null && d.state === "shown"
                    // The Cost header is "" while no session has a cost.
                    readonly property bool withCost: d !== null && d.columns[3] !== ""

                    visible: d !== null
                    width: parent.width
                    spacing: 2

                    Head {
                        title: detail.d ? detail.d.title : ""
                        periods: detail.d ? detail.d.periods : []
                    }

                    Pair {
                        visible: detail.shown
                        name: detail.d ? detail.d.labels.output : ""
                        value: detail.d ? detail.d.output : ""
                    }

                    Pair {
                        visible: detail.shown
                        name: detail.d ? detail.d.labels.sessions : ""
                        value: detail.d ? detail.d.sessions : ""
                    }

                    Pair {
                        visible: detail.shown
                        name: detail.d ? detail.d.labels.subagents : ""
                        value: detail.d ? detail.d.subagents : ""
                    }

                    Pair {
                        visible: detail.shown && value !== ""
                        name: detail.d ? detail.d.labels.cost : ""
                        value: detail.d ? detail.d.cost : ""
                    }

                    Item {
                        visible: detail.shown
                        width: 1
                        height: 4
                    }

                    SplitBar {
                        visible: detail.shown
                        barHeight: 10
                        parts: detail.d ? detail.d.split : []
                    }

                    Small {
                        visible: detail.shown && text !== ""
                        text: detail.d ? detail.d.sentence : ""
                    }

                    Item {
                        visible: detail.shown
                        width: 1
                        height: 6
                    }

                    Section {
                        visible: detail.shown && detail.d.byType !== null
                        label: detail.d ? detail.d.labels.byType : ""

                        SplitBar {
                            barHeight: 8
                            parts: detail.d?.byType?.bar ?? []
                        }

                        Item {
                            width: 1
                            height: 2
                        }

                        Repeater {
                            model: detail.d?.byType?.rows ?? []

                            GridRow {
                                required property var modelData

                                cells: [[modelData.label, 0, false, modelData.colour], [modelData.tokens, 64, true, "muted"], [modelData.cost, 148, true]]
                            }
                        }
                    }

                    Item {
                        visible: detail.shown && detail.d.byType !== null
                        width: 1
                        height: 6
                    }

                    Section {
                        visible: detail.shown
                        label: detail.d ? detail.d.labels.last14 : ""

                        Bars {
                            info:detail.d ? detail.d.last14 : null
                        }
                    }

                    Item {
                        visible: detail.shown
                        width: 1
                        height: 6
                    }

                    Section {
                        visible: detail.shown
                        label: detail.d ? detail.d.labels.rows : ""

                        GridRow {
                            readonly property var c: detail.d ? detail.d.columns : []

                            header: true
                            cells: detail.withCost ? [[c[0], 72, false], [c[1], 76, false], [c[2], 56, true], [c[3], 0, true]] : [[c[0] ?? "", 72, false], [c[1] ?? "", 0, false], [c[2] ?? "", 56, true]]
                        }

                        // The cost takes the spare width: "≈ $4.37 + unpriced"
                        // is the widest cell. Without costs (an older helper)
                        // the last reply takes it.
                        Repeater {
                            model: detail.d ? detail.d.rows : []

                            Column {
                                required property var modelData

                                width: parent.width
                                bottomPadding: 3

                                GridRow {
                                    cells: detail.withCost ? [[parent.modelData.started, 72, false], [parent.modelData.last, 76, false, "muted"], [parent.modelData.output, 56, true], [parent.modelData.cost, 0, true]] : [[parent.modelData.started, 72, false], [parent.modelData.last, 0, false, "muted"], [parent.modelData.output, 56, true]]
                                }

                                Text {
                                    text: parent.modelData.line
                                    textFormat: Text.PlainText
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Small {
                            topPadding: 4
                            text: detail.d ? detail.d.note : ""
                        }
                    }

                    Small {
                        visible: detail.shown && text !== ""
                        topPadding: 4
                        text: detail.d ? detail.d.unpriced : ""
                    }

                    Building {
                        visible: detail.d !== null && detail.d.state === "building"
                        info:detail.d ? detail.d.building : null
                    }

                    Small {
                        visible: text !== ""
                        text: detail.d ? detail.d.error : ""
                        font.pixelSize: 13
                    }
                }

                Column {
                    id: days

                    readonly property var d: root.v ? root.v.days : null

                    visible: d !== null
                    width: parent.width
                    spacing: 6

                    Head {
                        title: days.d ? days.d.title : ""
                        meta: days.d ? days.d.meta : ""
                    }

                    Column {
                        visible: days.d !== null && days.d.state === "shown"
                        width: parent.width
                        spacing: 2

                        DayRow {
                            header: true
                            cells: days.d ? days.d.columns : []
                            withCost: days.d !== null && days.d.columns[3] !== ""
                        }

                        Repeater {
                            model: days.d ? days.d.rows : []

                            DayRow {
                                required property var modelData

                                row: modelData
                                withCost: days.d !== null && days.d.columns[3] !== ""
                            }
                        }
                    }

                    Building {
                        visible: days.d !== null && days.d.state === "building"
                        info:days.d ? days.d.building : null
                    }

                    Small {
                        visible: text !== ""
                        text: days.d ? days.d.error : ""
                        font.pixelSize: 13
                    }
                }

                Small {
                    readonly property var shown: root.v ? (root.v.overview ?? root.v.projects ?? root.v.detail ?? root.v.days) : null

                    visible: text !== ""
                    text: shown ? shown.estimate : ""
                }
            }

            KeyHints {
                visible: root.v !== null
                keys: root.v ? root.v.hints : []
                message: TokensShared.said
                messageColor: Theme.comment
            }
        }
    }

    // A limits row, or nothing for a null row.
    component LimitRow: Pair {
        property var row: null
        size: 13

        visible: row !== null
        name: row ? row.label : ""
        value: row ? row.value : ""
        note: row ? row.note : ""
        colour: row ? root.tone(row.colour) : Theme.foreground
    }

    // One day: name, a bar of its output, output, cost, sessions, top
    // project. A cost too wide for its column wraps.
    component DayRow: Item {
        id: dr

        property var row: null
        property bool header: false
        property var cells: []
        // False drops the cost column (its header is "" while no day has a
        // cost) and gives its width to the bar.
        property bool withCost: true

        readonly property real dayWidth: 52
        readonly property real outputWidth: 52
        // -8 takes the gap after the column away too.
        readonly property real costWidth: withCost ? 76 : -8
        readonly property real sessionsWidth: 56
        readonly property real topWidth: 76
        readonly property real barWidth: width - dayWidth - outputWidth - costWidth - sessionsWidth - topWidth - 40

        width: parent ? parent.width : 0
        height: Math.max(dayText.implicitHeight, costCell.implicitHeight) + 2

        Text {
            id: dayText

            width: dr.dayWidth
            text: dr.header ? dr.cells[0] ?? "" : dr.row.day
            color: dr.header ? Theme.comment : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: dr.header ? 11 : 12
        }

        Text {
            visible: dr.header
            x: dr.dayWidth + 8
            text: dr.cells[1] ?? ""
            color: Theme.comment
            font.family: Theme.fontMono
            font.pixelSize: 11
        }

        Rectangle {
            visible: !dr.header
            x: dr.dayWidth + 8
            y: (dayText.implicitHeight - height) / 2
            width: dr.header ? 0 : dr.barWidth * dr.row.frac
            height: 8
            radius: 2
            color: dr.header ? "transparent" : root.tone(dr.row.colour)
        }

        Text {
            x: dr.dayWidth + 8 + dr.barWidth + 8
            width: dr.outputWidth
            horizontalAlignment: Text.AlignRight
            text: dr.header ? dr.cells[2] ?? "" : dr.row.output
            color: dr.header ? Theme.comment : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: dr.header ? 11 : 12
        }

        Text {
            id: costCell

            visible: dr.withCost
            x: dr.dayWidth + 8 + dr.barWidth + 8 + dr.outputWidth + 8
            width: dr.costWidth
            horizontalAlignment: Text.AlignRight
            text: dr.header ? dr.cells[3] ?? "" : dr.row.cost
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: dr.header ? Theme.comment : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: dr.header ? 11 : 12
        }

        Text {
            x: dr.dayWidth + 8 + dr.barWidth + 8 + dr.outputWidth + 8 + dr.costWidth + 8
            width: dr.sessionsWidth
            horizontalAlignment: Text.AlignRight
            text: dr.header ? dr.cells[4] ?? "" : dr.row.sessions
            color: dr.header ? Theme.comment : Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: dr.header ? 11 : 12
        }

        Text {
            x: dr.width - dr.topWidth
            width: dr.topWidth
            text: dr.header ? dr.cells[5] ?? "" : dr.row.top
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.comment
            font.family: Theme.fontUi
            font.pixelSize: dr.header ? 11 : 12
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
        WlrLayershell.namespace: "desk-tokens"
        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // A click off the panel closes it, the bar's item included.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                if (root.key(event))
                    event.accepted = true;
            }
        }

        Card {
            centre: root.open ? Dropdowns.centre("tokens", TokensShared.screen) : -1
        }
    }
}
