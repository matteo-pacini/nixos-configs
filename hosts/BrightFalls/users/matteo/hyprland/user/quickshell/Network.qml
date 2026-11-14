import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import qs.network

// The network panel, hanging under the bar's network icon on one monitor.
// Toggled over IPC (on the focused monitor) or by clicking the icon:
//   qs ipc call network toggle
// Wired devices, then the settings Nix fixes (from
// ~/.local/share/desk/network/locked.json, absent with no file). S runs a
// speed test over the connection carrying the default route; each completed
// run is appended to ~/.local/state/desk/speedtests.jsonl.
Scope {
    id: root

    readonly property bool open: Panel.screen !== ""
    // Bar.qml: 6 px margin plus the bar's 34 px, then the 8 px gap that
    // everything under the bar keeps.
    readonly property int top: 6 + 34 + 8
    readonly property int panelWidth: 380
    readonly property int gaugeHeight: 252
    // Full scales the gauges may take, in Mb/s.
    readonly property var gaugeCeilings: [100, 250, 500, 1000, 2500, 5000, 10000]
    // The gauges' shared full scale: the negotiated link speed of the
    // interface under test, or, while that is unknown, the smallest ceiling
    // that holds the best figure stored for the connection. Either way it
    // grows to the smallest ceiling holding a reading that exceeds it.
    readonly property real gaugeTop: {
        const reading = Math.max(isNaN(download) ? 0 : download, isNaN(upload) ? 0 : upload);
        const link = wired.find(d => d.name === testInterface)?.linkSpeed ?? 0;
        if (link > 0 && reading <= link)
            return link;
        const need = Math.max(reading, link > 0 ? 0 : best[testConnection] ?? 0);
        return gaugeCeilings.find(c => c >= need) ?? gaugeCeilings[gaugeCeilings.length - 1];
    }

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/desk"
    readonly property string lockedPath: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/desk/network/locked.json"

    readonly property color soft: Qt.tint(Theme.foreground, Qt.rgba(Theme.comment.r, Theme.comment.g, Theme.comment.b, 0.3))

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            ethernet: "\u{f0200}",
            tailscale: "\u{f0499}",
            ipv6: "\u{f0317}",
            wol: "\u{f0425}",
            hostname: "\u{f048b}",
            firewall: "\u{f099d}",
            locked: "\u{f033e}"
        })

    readonly property var wired: Networking.devices.values.filter(d => d.type === DeviceType.Wired).sort((a, b) => a.name.localeCompare(b.name))
    // Interface -> { connection, addresses, gateway, dns }, from nmcli.
    property var info: ({})
    // Interface -> "full" / "half", from sysfs.
    property var duplex: ({})
    property string routeDevice: ""
    // Connection name -> newest stored record.
    property var latest: ({})
    // Connection name -> highest download or upload stored for it, in Mb/s.
    property var best: ({})
    property var locked: []
    property bool lockedPresent: false

    readonly property var rows: wired.map(d => ({
                kind: "wired",
                device: d
            })).concat(lockedPresent ? locked.map(l => ({
                    kind: "nix",
                    entry: l
                })) : [])
    property int current: 0
    property string expanded: ""
    property string flash: ""
    // The connection whose figures were just measured, until the panel closes.
    property string fresh: ""
    property date now: new Date()

    // list, out, run, hold, failed, back: see startTest() and back().
    property string phase: "list"
    property bool showGauges: false
    property bool gaugesIn: false
    property bool listIn: true
    property string testConnection: ""
    property string testInterface: ""
    property real ping: NaN
    property real download: NaN
    property real upload: NaN
    property string measuring: ""
    property string failure: ""
    property string savedAt: ""

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        current = Math.max(0, rows.findIndex(r => r.kind === "wired" && r.device.connected));
        expanded = "";
        flash = "";
        fresh = "";
        now = new Date();
        infoQuery.running = true;
        records.reload();
        lockedFile.reload();
        Panel.screen = window.screen.name;
    }

    function close(): void {
        if (speedTest.running)
            speedTest.cancel();
        resetTest();
        Panel.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function activate(): void {
        const row = rows[current];
        if (!row)
            return;
        if (row.kind === "nix") {
            say(`Set in ${row.entry.file}. Change it there and deploy.`);
        } else if (row.device.connected) {
            expanded = expanded === row.device.name ? "" : row.device.name;
        } else {
            say(row.device.hasLink ? `${row.device.name} is not connected.` : `No cable in ${row.device.name}.`);
        }
    }

    function linkText(mbps: int): string {
        return mbps >= 1000 ? `${Math.round(mbps / 100) / 10} Gb/s` : `${mbps} Mb/s`;
    }

    function age(at: string): string {
        const seconds = (now - new Date(at)) / 1000;
        if (isNaN(seconds))
            return "";
        if (seconds < 60)
            return "just now";
        if (seconds < 3600)
            return `${Math.floor(seconds / 60)} min ago`;
        if (seconds < 86400)
            return `${Math.floor(seconds / 3600)} h ago`;
        return `${Math.floor(seconds / 86400)} d ago`;
    }

    // ISO 8601 with the local offset, which toISOString() does not give.
    function isoNow(): string {
        const d = new Date();
        const offset = -d.getTimezoneOffset();
        const pad = n => String(Math.floor(Math.abs(n))).padStart(2, "0");
        return Qt.formatDateTime(d, "yyyy-MM-ddTHH:mm:ss") + (offset >= 0 ? "+" : "-") + pad(offset / 60) + ":" + pad(offset % 60);
    }

    function resetTest(): void {
        outTimer.stop();
        startTimer.stop();
        holdTimer.stop();
        backTimer.stop();
        phase = "list";
        download = NaN;
        upload = NaN;
        showGauges = false;
        gaugesIn = false;
        listIn = true;
    }

    function startTest(): void {
        if (!open || phase !== "list")
            return;
        expanded = "";
        phase = "out";
        listIn = false;
        outTimer.start();
    }

    function runTest(): void {
        ping = NaN;
        download = NaN;
        upload = NaN;
        measuring = "";
        failure = "";
        savedAt = "";
        testInterface = routeDevice;
        testConnection = info[routeDevice]?.connection ?? "";
        if (routeDevice === "" || testConnection === "") {
            fail(routeDevice === "" ? "No default route" : `${routeDevice} has no NetworkManager connection`);
            return;
        }
        phase = "run";
        measuring = "latency";
        speedTest.start();
    }

    function fail(reason: string): void {
        measuring = "";
        ping = NaN;
        download = NaN;
        upload = NaN;
        failure = reason;
        phase = "failed";
    }

    // Back to the list: gauges out, height back, list in. Cancels a run in
    // progress, which then stores nothing.
    function back(): void {
        outTimer.stop();
        startTimer.stop();
        holdTimer.stop();
        if (speedTest.running)
            speedTest.cancel();
        phase = "back";
        gaugesIn = false;
        backTimer.start();
    }

    Timer {
        id: outTimer

        interval: 210
        onTriggered: {
            root.ping = NaN;
            root.failure = "";
            root.savedAt = "";
            root.testInterface = root.routeDevice;
            root.testConnection = root.info[root.routeDevice]?.connection ?? "";
            root.showGauges = true;
            root.gaugesIn = true;
            startTimer.start();
        }
    }

    Timer {
        id: startTimer

        interval: 380
        onTriggered: root.runTest()
    }

    Timer {
        id: holdTimer

        interval: 1500
        onTriggered: root.back()
    }

    Timer {
        id: backTimer

        interval: 210
        onTriggered: {
            // Cleared while hidden, so the next run's gauges start at zero.
            root.download = NaN;
            root.upload = NaN;
            root.showGauges = false;
            root.listIn = true;
            root.phase = "list";
        }
    }

    Timer {
        id: flashTimer

        interval: 2500
        onTriggered: root.flash = ""
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.open
        onTriggered: root.now = new Date()
    }

    SpeedTest {
        id: speedTest

        onLatency: ms => {
            root.ping = ms;
            root.measuring = "download";
        }
        onProgress: (direction, mbps) => {
            root.measuring = direction;
            if (direction === "download")
                root.download = mbps;
            else
                root.upload = mbps;
        }
        onDirectionDone: (direction, mbps) => {
            if (direction === "download")
                root.download = mbps;
            else
                root.upload = mbps;
        }
        onFinished: (download, upload, ping) => {
            root.download = download;
            root.upload = upload;
            root.ping = ping;
            root.measuring = "";
            const record = {
                at: root.isoNow(),
                connection: root.testConnection,
                interface: root.testInterface,
                download_mbps: Math.round(download * 10) / 10,
                upload_mbps: Math.round(upload * 10) / 10,
                ping_ms: Math.round(ping * 10) / 10,
                tool: speedTest.tool
            };
            store.command = ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" >> "$1/speedtests.jsonl"', "sh", root.stateDir, JSON.stringify(record)];
            store.running = true;
            const latest = Object.assign({}, root.latest);
            latest[record.connection] = record;
            root.latest = latest;
            const best = Object.assign({}, root.best);
            best[record.connection] = Math.max(best[record.connection] ?? 0, download, upload);
            root.best = best;
            root.fresh = record.connection;
            root.now = new Date();
            root.savedAt = Qt.formatDateTime(new Date(), "HH:mm");
            root.phase = "hold";
            holdTimer.start();
        }
        onFailed: reason => root.fail(reason)
    }

    Process {
        id: store

        onExited: code => {
            if (code !== 0)
                console.warn("network: could not append to", root.stateDir + "/speedtests.jsonl");
        }
    }

    // Read on open only. nmcli has the addresses NetworkManager holds,
    // ip the route the kernel uses, sysfs the duplex.
    Process {
        id: infoQuery

        command: ["sh", "-c", "nmcli -t -m multiline -f GENERAL.DEVICE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show; echo @route; ip -j route show default; echo @duplex; grep -H . /sys/class/net/*/duplex 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [nm, rest] = text.split("\n@route\n");
                const [route, sys] = (rest ?? "").split("\n@duplex\n");
                const info = {};
                let dev = null;
                for (const line of nm.split("\n")) {
                    const at = line.indexOf(":");
                    if (at < 0)
                        continue;
                    const key = line.slice(0, at).replace(/\[\d+\]$/, "");
                    const value = line.slice(at + 1).replace(/\\(.)/g, "$1");
                    if (key === "GENERAL.DEVICE") {
                        dev = info[value] = {
                            connection: "",
                            addresses: [],
                            gateway: "",
                            dns: []
                        };
                    } else if (dev && value !== "") {
                        if (key === "GENERAL.CONNECTION")
                            dev.connection = value;
                        else if (key === "IP4.ADDRESS")
                            dev.addresses.push(value);
                        else if (key === "IP4.GATEWAY")
                            dev.gateway = value;
                        else if (key === "IP4.DNS")
                            dev.dns.push(value);
                    }
                }
                root.info = info;
                try {
                    const routes = JSON.parse(route || "[]").sort((a, b) => (a.metric ?? 0) - (b.metric ?? 0));
                    root.routeDevice = routes[0]?.dev ?? "";
                } catch (e) {
                    console.warn("network: ip route:", e.message);
                    root.routeDevice = "";
                }
                const duplex = {};
                for (const line of (sys ?? "").split("\n")) {
                    const m = line.match(/^\/sys\/class\/net\/([^/]+)\/duplex:(\w+)$/);
                    if (m)
                        duplex[m[1]] = m[2];
                }
                root.duplex = duplex;
            }
        }
    }

    FileView {
        id: records

        path: root.stateDir + "/speedtests.jsonl"
        printErrors: false
        blockLoading: true
        onLoaded: {
            const latest = {}, best = {};
            for (const line of text().split("\n")) {
                if (line.trim() === "")
                    continue;
                try {
                    const r = JSON.parse(line);
                    if (typeof r.connection !== "string")
                        continue;
                    latest[r.connection] = r;
                    best[r.connection] = Math.max(best[r.connection] ?? 0, Number(r.download_mbps) || 0, Number(r.upload_mbps) || 0);
                } catch (e) {
                    console.warn("network: speedtests.jsonl:", e.message);
                }
            }
            root.latest = latest;
            root.best = best;
        }
        onLoadFailed: {
            root.latest = {};
            root.best = {};
        }
    }

    FileView {
        id: lockedFile

        path: root.lockedPath
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.locked = Array.isArray(parsed) ? parsed.filter(r => typeof r.label === "string") : [];
                root.lockedPresent = true;
            } catch (e) {
                console.warn("network: locked.json:", e.message);
                root.locked = [];
                root.lockedPresent = false;
            }
        }
        onLoadFailed: {
            root.locked = [];
            root.lockedPresent = false;
        }
    }

    Connections {
        target: Panel

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "network"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
    }

    component SectionHeader: Text {
        leftPadding: 14
        topPadding: 10
        bottomPadding: 3
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 11
        font.weight: Font.Medium
        font.letterSpacing: 0.88
    }

    component Small: Text {
        width: parent.width
        elide: Text.ElideRight
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 12
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
        WlrLayershell.namespace: "desk-network"

        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        // A click off the panel closes it, the bar's icon included.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys

            focus: true
            Keys.onPressed: event => {
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                if (event.key === Qt.Key_Escape) {
                    if (root.phase === "list") {
                        if (root.expanded !== "")
                            root.expanded = "";
                        else
                            root.close();
                    } else if (root.phase !== "back") {
                        root.back();
                    }
                } else if (root.phase === "failed" && enter) {
                    root.runTest();
                } else if (root.phase !== "list") {
                    // Keys wait while the gauges show.
                } else if (event.key === Qt.Key_Down) {
                    root.current = Math.min(root.current + 1, root.rows.length - 1);
                } else if (event.key === Qt.Key_Up) {
                    root.current = Math.max(root.current - 1, 0);
                } else if (enter) {
                    root.activate();
                } else if (event.key === Qt.Key_S && plain) {
                    root.startTest();
                } else {
                    return;
                }
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

            readonly property real centre: root.open ? Panel.iconCentre(Panel.screen) : -1

            x: centre < 0 ? window.width - width - 6 : Math.max(6, Math.min(window.width - width - 6, Math.round(centre - width / 2)))
            y: root.top
            width: root.panelWidth
            height: root.showGauges ? root.gaugeHeight : list.implicitHeight + 2
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
                id: list

                x: 1
                y: 1
                width: parent.width - 2
                visible: !root.showGauges
                opacity: root.listIn ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                SectionHeader {
                    text: "WIRED"
                }

                Column {
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.wired

                        Column {
                            id: wiredRow

                            required property NetworkDevice modelData
                            required property int index
                            readonly property var nm: root.info[modelData.name] ?? null
                            readonly property string connection: nm?.connection ?? ""
                            readonly property var record: connection !== "" ? root.latest[connection] ?? null : null
                            readonly property bool up: modelData.connected

                            width: parent.width - 12
                            spacing: 2

                            Rectangle {
                                width: parent.width
                                height: wiredText.implicitHeight + 14
                                radius: 6
                                color: root.current === wiredRow.index ? Theme.currentLine : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.current = wiredRow.index;
                                        root.activate();
                                    }
                                }

                                Text {
                                    id: wiredIcon

                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.glyph.ethernet
                                    color: wiredRow.up ? Theme.green : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 16
                                }

                                Column {
                                    id: wiredText

                                    anchors.left: wiredIcon.right
                                    anchors.leftMargin: 10
                                    anchors.right: status.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: wiredRow.modelData.name
                                        color: Theme.foreground
                                        font.family: Theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: Font.Medium
                                    }

                                    Small {
                                        text: {
                                            const d = wiredRow.modelData;
                                            if (!d.hasLink)
                                                return "no cable";
                                            const parts = [];
                                            if (d.linkSpeed > 0)
                                                parts.push(root.linkText(d.linkSpeed));
                                            if (wiredRow.up && wiredRow.nm?.addresses.length)
                                                parts.push(wiredRow.nm.addresses[0].split("/")[0]);
                                            if (!wiredRow.up)
                                                parts.push("not connected");
                                            return parts.join(" · ");
                                        }
                                    }

                                    Row {
                                        visible: wiredRow.up
                                        width: parent.width

                                        Small {
                                            width: undefined
                                            text: wiredRow.record ? `↓ ${Math.round(wiredRow.record.download_mbps)}  ↑ ${Math.round(wiredRow.record.upload_mbps)} Mb/s · ${Math.round(wiredRow.record.ping_ms)} ms ` : "↓ --  ↑ --  Mb/s "
                                            color: wiredRow.record && root.fresh === wiredRow.connection ? Theme.cyan : root.soft
                                        }

                                        Small {
                                            width: undefined
                                            text: "· " + (wiredRow.record ? root.age(wiredRow.record.at) : "never run")
                                        }
                                    }
                                }

                                Text {
                                    id: status

                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wiredRow.up ? "connected" : ""
                                    color: Theme.green
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }

                            Column {
                                visible: root.expanded === wiredRow.modelData.name && wiredRow.up
                                x: 28
                                width: parent.width - 28
                                bottomPadding: 4

                                Rectangle {
                                    width: 2
                                    height: details.implicitHeight + 4
                                    color: Theme.currentLine

                                    Column {
                                        id: details

                                        x: 12
                                        y: 2

                                        Repeater {
                                            model: {
                                                const d = wiredRow.modelData, nm = wiredRow.nm;
                                                const duplex = root.duplex[d.name];
                                                return [["address", nm?.addresses.join(", ") || "–"], ["gateway", nm?.gateway || "–"], ["dns", nm?.dns.join(", ") || "–"], ["mac", d.address.toLowerCase() || "–"], ["link", d.linkSpeed > 0 ? `${d.linkSpeed} Mb/s${duplex === "full" || duplex === "half" ? ` ${duplex} duplex` : ""}` : "–"]];
                                            }

                                            Row {
                                                required property var modelData

                                                Text {
                                                    width: 72
                                                    text: parent.modelData[0]
                                                    color: Theme.comment
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 12
                                                    lineHeight: 1.7
                                                }

                                                Text {
                                                    text: parent.modelData[1]
                                                    color: root.soft
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 12
                                                    lineHeight: 1.7
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionHeader {
                    visible: root.lockedPresent && root.locked.length > 0
                    text: "SET IN NIX"
                }

                Column {
                    visible: root.lockedPresent && root.locked.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.lockedPresent ? root.locked : []

                        Rectangle {
                            id: lockedRow

                            required property var modelData
                            required property int index
                            readonly property int row: root.wired.length + index

                            width: parent.width - 12
                            height: lockedLabel.implicitHeight + 14
                            radius: 6
                            color: root.current === row ? Theme.currentLine : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.current = lockedRow.row;
                                    root.activate();
                                }
                            }

                            Text {
                                id: lockedIcon

                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                horizontalAlignment: Text.AlignHCenter
                                text: root.glyph[lockedRow.modelData.id] ?? root.glyph.locked
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 16
                            }

                            Text {
                                id: lockedLabel

                                anchors.left: lockedIcon.right
                                anchors.leftMargin: 10
                                anchors.right: tag.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: lockedRow.modelData.label
                                color: Theme.comment
                                font.family: Theme.fontUi
                                font.pixelSize: 15
                            }

                            Rectangle {
                                id: tag

                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: tagText.implicitWidth + 10
                                height: tagText.implicitHeight + 2
                                radius: 4
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.currentLine

                                Text {
                                    id: tagText

                                    anchors.centerIn: parent
                                    text: "nix"
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.currentLine
                }

                Item {
                    width: parent.width
                    height: Math.max(hints.implicitHeight, flashText.implicitHeight) + 16

                    Row {
                        id: hints

                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.flash === ""
                        spacing: 14

                        Repeater {
                            model: [["Enter", "select"], ["S", "speed test"], ["Esc", root.expanded !== "" ? "back" : "close"]]

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

                    Text {
                        id: flashText

                        x: 14
                        width: parent.width - 28
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.flash !== ""
                        text: root.flash
                        wrapMode: Text.Wrap
                        color: Theme.yellow
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            Column {
                x: 1
                y: 1
                width: parent.width - 2
                height: parent.height - 2
                visible: root.showGauges
                opacity: root.gaugesIn ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Item {
                    width: parent.width
                    height: parent.height

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 4

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Gauge {
                                label: "Download"
                                doneColor: Theme.purple
                                full: root.gaugeTop
                                value: root.download
                                active: root.phase === "run" && root.measuring === "download"
                            }

                            Gauge {
                                label: "Upload"
                                doneColor: Theme.pink
                                full: root.gaugeTop
                                value: root.upload
                                active: root.phase === "run" && root.measuring === "upload"
                            }
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: 10
                            spacing: 16

                            Repeater {
                                model: {
                                    if (root.phase === "failed")
                                        return [];
                                    const pairs = [["latency", isNaN(root.ping) ? "measuring…" : `${Math.round(root.ping)} ms`], ["via", root.testInterface || "–"]];
                                    if (root.savedAt !== "")
                                        pairs.push(["saved", root.savedAt]);
                                    return pairs;
                                }

                                Text {
                                    required property var modelData

                                    text: `${modelData[0]} <font color="${root.soft}">${modelData[1]}</font>`
                                    textFormat: Text.StyledText
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Text {
                            visible: root.phase === "failed"
                            width: parent.width
                            topPadding: 10
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: `${root.failure}. Enter retries, Esc returns.`
                            color: Theme.red
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
