import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import qs.weather
import "weather/weather.js" as W

// The weather panel, hanging under the bar's weather item on one monitor.
// Toggled over IPC (on the focused monitor) or from the bar:
//   qs ipc call weather toggle
// The sky over the house, the figures, any warnings, then the next hours, six
// days, the air quality and the outdoor sensor's battery and link; M swaps
// the lower half for the rain radar's past frames. weather.js decides everything drawn and what each key does; this
// file draws its views and passes keys on.
Scope {
    id: root

    readonly property bool open: WeatherShared.open
    readonly property int panelWidth: 420

    readonly property var st: WeatherShared.st
    readonly property var ui: WeatherShared.ui
    readonly property bool radarPage: ui !== null && ui.page === "radar"

    // Views as JSON strings first: a string property notifies only when it
    // changes, so the once-a-second tick rebuilds nothing that stayed the
    // same (the hour columns, the radar's tiles).
    readonly property string viewJson: open && ui ? JSON.stringify(W.view(st, ui.now)) : ""
    readonly property var v: viewJson !== "" ? JSON.parse(viewJson) : null
    readonly property string radarJson: radarPage ? JSON.stringify(W.radarView(st, ui.now, ui.frame, ui.playing)) : ""
    readonly property var rv: radarJson !== "" ? JSON.parse(radarJson) : null
    readonly property string framesJson: rv ? JSON.stringify(rv.frames.map(f => f.dir)) : "[]"
    readonly property var frameDirs: JSON.parse(framesJson)
    readonly property string blockJson: rv && rv.block ? JSON.stringify(rv.block) : ""
    readonly property var block: blockJson !== "" ? JSON.parse(blockJson) : null
    readonly property string hintsJson: open && ui ? JSON.stringify(W.hints(ui, st)) : ""
    readonly property var hints: hintsJson !== "" ? JSON.parse(hintsJson) : null

    // weather.js's tone names.
    function tone(name: string): color {
        switch (name) {
        case "soft":
            return Style.soft;
        case "dim":
            return Theme.comment;
        case "yellow":
            return Theme.yellow;
        case "orange":
            return Theme.orange;
        case "red":
            return Theme.red;
        case "green":
            return Theme.green;
        case "cyan":
            return Theme.cyan;
        case "pink":
            return Theme.pink;
        default:
            return Theme.foreground;
        }
    }

    // For outside text placed inside styled text.
    function esc(text: string): string {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("weather");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        WeatherShared.screen = window.screen.name;
    }

    function close(): void {
        WeatherShared.screen = "";
    }

    // Returns true when the key was used.
    function key(event: var): bool {
        const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const always = {
            [Qt.Key_Escape]: "Esc",
            [Qt.Key_Left]: "Left",
            [Qt.Key_Right]: "Right"
        };
        const letters = {
            [Qt.Key_R]: "R",
            [Qt.Key_M]: "M",
            [Qt.Key_W]: "W",
            [Qt.Key_Space]: "Space"
        };
        const name = always[event.key] ?? (plain ? letters[event.key] : undefined);
        if (name === undefined)
            return false;
        if (WeatherShared.key(name, event.isAutoRepeat) === "close")
            close();
        return true;
    }

    Component.onCompleted: Dropdowns.add("weather", WeatherShared)

    Connections {
        target: WeatherShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "weather"

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
        WlrLayershell.namespace: "desk-weather"
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

        DropCard {
            centre: root.open ? Dropdowns.centre("weather", WeatherShared.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // The helper or settings error, alone.
                Text {
                    visible: root.v !== null && root.v.single !== ""
                    width: parent.width
                    padding: 14
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: root.v ? root.v.singleParts.map(p => p.code ? `<font face="${Theme.fontMono}" color="${Theme.foreground}">${root.esc(p.text)}</font>` : root.esc(p.text)).join("") : ""
                    color: Style.soft
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }

                Column {
                    visible: root.v !== null && root.v.single === ""
                    width: parent.width

                    // The sky, with the large figure and its source over it.
                    Item {
                        width: parent.width
                        height: 170

                        SkyScene {
                            anchors.fill: parent
                            blank: root.v && root.v.scene ? root.v.scene.blank : true
                            day: root.v && root.v.scene ? root.v.scene.day : false
                            frac: root.v && root.v.scene ? root.v.scene.frac : 0
                            edge: root.v && root.v.scene ? root.v.scene.edge : false
                            cloud: root.v && root.v.scene ? root.v.scene.cloud : 0
                            rain: root.v && root.v.scene ? root.v.scene.rain : 0
                            snow: root.v && root.v.scene ? root.v.scene.snow : false
                            fog: root.v && root.v.scene ? root.v.scene.fog : false
                            lit: root.v && root.v.scene ? root.v.scene.lit : false
                            seed: 21
                            running: root.open
                        }

                        // Darker on the left, under the figures.
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: Qt.rgba(18 / 255, 19 / 255, 27 / 255, 0.62)
                                }

                                GradientStop {
                                    position: 0.46
                                    color: Qt.rgba(18 / 255, 19 / 255, 27 / 255, 0.18)
                                }

                                GradientStop {
                                    position: 0.64
                                    color: Qt.rgba(18 / 255, 19 / 255, 27 / 255, 0)
                                }
                            }
                        }

                        Text {
                            x: 14
                            y: 11
                            text: "WEATHER"
                            color: Style.soft
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            font.letterSpacing: 0.88
                        }

                        Text {
                            x: parent.width - 14 - width
                            y: 11
                            width: Math.min(implicitWidth, 300)
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.Wrap
                            text: root.v && root.v.hero ? root.v.hero.age : ""
                            textFormat: Text.PlainText
                            color: root.v && root.v.hero ? root.tone(root.v.hero.ageTone) : Style.soft
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.5)
                        }

                        Text {
                            x: 13
                            y: 78 - baselineOffset
                            text: root.v && root.v.hero ? root.v.hero.big : ""
                            color: root.v && root.v.hero ? root.tone(root.v.hero.bigTone) : Theme.foreground
                            font.family: Theme.fontUi
                            font.pixelSize: 58
                            font.weight: Font.Light
                            font.letterSpacing: -1.5
                        }

                        Column {
                            x: 15
                            y: 94
                            width: 215
                            spacing: 2

                            Text {
                                visible: text !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: root.v && root.v.hero ? root.v.hero.condition : ""
                                textFormat: Text.PlainText
                                color: Theme.foreground
                                font.family: Theme.fontUi
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.4)
                            }

                            Text {
                                visible: text !== ""
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: root.v && root.v.hero ? root.v.hero.range : ""
                                textFormat: Text.PlainText
                                color: Style.soft
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }
                        }
                    }

                    // One strip per warning, most severe first.
                    Repeater {
                        model: root.v && root.v.warnings ? root.v.warnings : []

                        Rectangle {
                            id: strip

                            required property var modelData
                            readonly property color ink: root.tone(modelData.tone)

                            width: parent.width
                            height: stripText.implicitHeight + 15
                            color: root.alpha(ink, 0.13)

                            WarnTriangle {
                                x: 14
                                y: 9
                                color: strip.ink
                            }

                            Column {
                                id: stripText

                                x: 38
                                y: 7
                                width: parent.width - 38 - 14
                                spacing: 1

                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: strip.modelData.title
                                    textFormat: Text.PlainText
                                    color: strip.ink
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: strip.modelData.detail
                                    textFormat: Text.PlainText
                                    color: Style.soft
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: root.alpha(strip.ink, 0.32)
                            }
                        }
                    }

                    // The four figures.
                    Item {
                        width: parent.width
                        height: 50

                        Repeater {
                            model: root.v && root.v.stats ? root.v.stats : []

                            Item {
                                id: stat

                                required property var modelData
                                required property int index

                                x: index * parent.width / 4
                                width: parent.width / 4
                                height: parent.height

                                Rectangle {
                                    visible: stat.index > 0
                                    width: 1
                                    height: parent.height
                                    color: Theme.currentLine
                                }

                                Text {
                                    x: 14
                                    y: 9
                                    text: stat.modelData.label
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.letterSpacing: 0.8
                                }

                                Row {
                                    x: 14
                                    y: 24
                                    spacing: 4

                                    Text {
                                        id: statValue

                                        text: stat.modelData.value
                                        color: root.tone(stat.modelData.tone)
                                        font.family: Theme.fontUi
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        anchors.baseline: statValue.baseline
                                        text: stat.modelData.unit
                                        color: Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.currentLine
                        }
                    }

                    // With no forecast to show, one line in its place.
                    Text {
                        visible: !root.radarPage && root.v !== null && root.v.body === "message"
                        width: parent.width
                        padding: 14
                        wrapMode: Text.Wrap
                        text: root.v && root.v.message ? root.v.message : ""
                        textFormat: Text.PlainText
                        color: Style.soft
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }

                    Column {
                        visible: !root.radarPage && root.v !== null && root.v.body === "forecast"
                        width: parent.width

                        SectionLine {
                            title: root.v && root.v.hoursHead ? root.v.hoursHead : ""
                            note: root.v && root.v.precipHead ? root.v.precipHead : ""
                        }

                        HoursStrip {
                            x: 14
                            width: 392
                            height: 112
                            hours: root.v && root.v.hours ? root.v.hours : []
                        }

                        SectionLine {
                            title: "6 DAYS"
                        }

                        Column {
                            x: 14
                            width: parent.width - 28
                            bottomPadding: 6

                            Repeater {
                                model: root.v && root.v.days ? root.v.days : []

                                Item {
                                    id: day

                                    required property var modelData
                                    readonly property real barX: 180
                                    readonly property real barWidth: width - 180 - 38

                                    width: parent.width
                                    height: 28

                                    // A warning covers this day.
                                    Rectangle {
                                        visible: day.modelData.mark !== ""
                                        x: -8
                                        y: 7
                                        width: 3
                                        height: 14
                                        radius: 1.5
                                        color: root.tone(day.modelData.mark)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 38
                                        text: day.modelData.label
                                        color: day.modelData.today ? Theme.foreground : Style.soft
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: day.modelData.today ? Font.DemiBold : Font.Normal
                                    }

                                    ConditionArt {
                                        x: 46
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: day.modelData.art ?? ""
                                        size: 22
                                    }

                                    Text {
                                        x: 80
                                        width: 54
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: day.modelData.precipText
                                        color: day.modelData.dry ? Theme.currentLine : Theme.cyan
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        x: 142
                                        width: 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: day.modelData.loText
                                        color: Theme.comment
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }

                                    // The day's range on the rows' common
                                    // scale, its colour from where it sits
                                    // on that scale.
                                    Shape {
                                        x: day.barX
                                        y: (parent.height - 5) / 2
                                        width: day.barWidth
                                        height: 5
                                        preferredRendererType: Shape.CurveRenderer

                                        ShapePath {
                                            strokeColor: "transparent"
                                            fillColor: Style.track

                                            PathRectangle {
                                                width: day.barWidth
                                                height: 5
                                                radius: 2.5
                                            }
                                        }

                                        ShapePath {
                                            strokeColor: "transparent"
                                            fillGradient: LinearGradient {
                                                x1: 0
                                                y1: 0
                                                x2: day.barWidth
                                                y2: 0

                                                GradientStop {
                                                    position: 0
                                                    color: Theme.cyan
                                                }

                                                GradientStop {
                                                    position: 0.55
                                                    color: Theme.yellow
                                                }

                                                GradientStop {
                                                    position: 1
                                                    color: Theme.orange
                                                }
                                            }

                                            PathRectangle {
                                                x: day.modelData.start === null ? 0 : day.modelData.start * day.barWidth
                                                width: day.modelData.start === null ? 0 : Math.max(5, (day.modelData.end - day.modelData.start) * day.barWidth)
                                                height: 5
                                                radius: 2.5
                                            }
                                        }
                                    }

                                    Text {
                                        x: parent.width - 30
                                        width: 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: day.modelData.hiText
                                        color: Theme.foreground
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }

                        SectionLine {
                            title: "AIR QUALITY"
                            note: root.v && root.v.air && root.v.air.shown ? root.v.air.head : ""
                        }

                        Text {
                            visible: root.v !== null && root.v.air !== null && !root.v.air.shown
                            x: 14
                            width: parent.width - 28
                            bottomPadding: 6
                            wrapMode: Text.Wrap
                            text: root.v && root.v.air ? root.v.air.message : ""
                            textFormat: Text.PlainText
                            color: root.v && root.v.air ? root.tone(root.v.air.messageTone) : Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }

                        Column {
                            id: airRow

                            readonly property var air: root.v && root.v.air && root.v.air.shown ? root.v.air : null

                            visible: air !== null
                            width: parent.width

                            Item {
                                id: aq

                                readonly property real scaleX: 14 + 30 + 10 + 96 + 10
                                readonly property real scaleWidth: width - scaleX - 14

                                width: parent.width
                                height: 27

                                Text {
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: airRow.air ? airRow.air.value : ""
                                    color: airRow.air ? root.tone(airRow.air.tone) : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    x: 14 + 30 + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: airRow.air ? airRow.air.word : ""
                                    color: airRow.air ? root.tone(airRow.air.tone) : Theme.foreground
                                    font.family: Theme.fontUi
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                Repeater {
                                    model: airRow.air ? airRow.air.bands : []

                                    Rectangle {
                                        required property var modelData
                                        required property int index

                                        x: aq.scaleX + index * (aq.scaleWidth + 2) / 6
                                        y: (aq.height - 6) / 2
                                        width: (aq.scaleWidth - 10) / 6
                                        height: 6
                                        radius: 2
                                        color: root.tone(modelData.tone)
                                        opacity: modelData.on ? 1 : 0.3
                                    }
                                }

                                Rectangle {
                                    visible: airRow.air !== null
                                    x: aq.scaleX + (airRow.air ? airRow.air.marker : 0) * aq.scaleWidth - 1.5
                                    y: (aq.height - 6) / 2 - 4
                                    width: 3
                                    height: 14
                                    radius: 1.5
                                    color: Theme.foreground
                                }
                            }

                            Text {
                                readonly property var air: airRow.air

                                x: 14
                                width: parent.width - 28
                                bottomPadding: 6
                                wrapMode: Text.Wrap
                                textFormat: Text.StyledText
                                text: {
                                    if (!air)
                                        return "";
                                    const b = s => `<font color="${Style.soft}">${root.esc(s)}</font>`;
                                    return air.parts.map(p => `${root.esc(p.label)} ${b(p.value)}`).join(" · ") + ` ${root.esc(air.unit)}` + (air.highest ? ` · highest: ${b(air.highest)}` : "") + (air.pollen ? ` · ${b(air.pollen)}` : "");
                                }
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                lineHeight: 1.25
                            }
                        }
                    }

                    // Under the air row, or under the message when there is
                    // no forecast; not on the radar page.
                    SensorRow {
                        readonly property var sensor: root.v && root.v.sensor ? root.v.sensor : null

                        visible: !root.radarPage && sensor !== null
                        battery: sensor ? sensor.battery : null
                        link: sensor ? sensor.link : null
                        message: sensor ? sensor.message : ""
                        messageTone: sensor ? sensor.messageTone : "dim"
                        heard: sensor ? sensor.heard : ""
                        heardTone: sensor ? sensor.heardTone : "dim"
                    }

                    // The radar page, in place of the hours, days and air.
                    Column {
                        visible: root.rv !== null
                        width: parent.width

                        SectionLine {
                            title: "RAIN RADAR"
                            note: root.rv ? root.rv.head : ""
                        }

                        Item {
                            width: parent.width
                            height: map.implicitHeight + 4

                            RadarMap {
                                id: map

                                x: 13
                                y: 4
                                coast: WeatherShared.coast
                                block: root.block
                                centre: root.block ? root.block.centre : null
                                frames: root.frameDirs
                                frameDir: root.rv ? root.rv.frameDir : ""
                                note: root.rv ? root.rv.note : ""
                            }
                        }

                        Column {
                            visible: root.rv !== null && root.rv.timeline
                            x: 14
                            width: parent.width - 28
                            topPadding: 8
                            bottomPadding: 2
                            spacing: 5

                            Item {
                                width: parent.width
                                height: 6

                                Repeater {
                                    model: root.rv ? root.rv.ticks : []

                                    Rectangle {
                                        required property string modelData
                                        required property int index
                                        readonly property int count: root.rv ? root.rv.ticks.length : 1

                                        x: index * (parent.width + 3) / count
                                        width: (parent.width + 3) / count - 3
                                        height: 6
                                        radius: 2
                                        color: modelData === "on" ? Theme.purple : modelData === "past" ? Theme.currentLine : Style.track
                                    }
                                }
                            }

                            Item {
                                width: parent.width
                                height: frameLabel.implicitHeight

                                Text {
                                    text: root.rv ? root.rv.left : ""
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }

                                Text {
                                    id: frameLabel

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.rv ? root.rv.label : ""
                                    color: root.rv ? root.tone(root.rv.labelTone) : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }

                                Text {
                                    anchors.right: parent.right
                                    text: root.rv ? root.rv.right : ""
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    // Where each part comes from and how old it is.
                    Text {
                        readonly property string line: root.rv ? root.rv.source : root.v && root.v.source ? root.v.source : ""
                        readonly property string lineTone: root.rv ? root.rv.sourceTone : root.v && root.v.sourceTone ? root.v.sourceTone : "normal"

                        visible: line !== ""
                        x: 14
                        width: parent.width - 28
                        topPadding: 6
                        bottomPadding: 9
                        wrapMode: Text.Wrap
                        text: line
                        textFormat: Text.PlainText
                        color: lineTone === "orange" ? Theme.orange : Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                KeyHints {
                    visible: root.hints !== null
                    keys: root.hints ? root.hints.keys : []
                    message: root.hints ? root.hints.message : ""
                    messageColor: root.hints ? root.tone(root.hints.tone) : Theme.comment
                }
            }
        }
    }
}
