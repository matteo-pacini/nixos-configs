import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import qs.common
import qs.network
import "network/wifi.js" as Wifi

// The network panel, hanging under the bar's network icon on one monitor.
// Toggled over IPC (on the focused monitor) or by clicking the icon:
//   qs ipc call network toggle
// Wired devices, then Wi-Fi (radio, scan, join, forget; decisions in
// network/wifi.js, the password in network/PasswordModal.qml), then the
// settings Nix fixes (from ~/.local/share/desk/network/locked.json, absent
// with no file). S opens a chooser of speed-test providers
// (network/SpeedTest.qml) or all of them in turn; tests run over the
// connection carrying the default route and each completed run is appended
// to ~/.local/state/desk/speedtests.jsonl.
Scope {
    id: root

    readonly property bool open: NetworkPanel.screen !== ""
    readonly property int panelWidth: 420
    // Height of the gauges and the line under them, footer excluded; the
    // second is for all in turn, where chips and a table come with them.
    readonly property int gaugeHeight: 221
    readonly property int gaugeHeightAll: 196
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

    readonly property color soft: Style.soft

    // Nerd Font (Material Design) glyphs.
    readonly property var glyph: ({
            ethernet: "\u{f0200}",
            tailscale: "\u{f0499}",
            ipv6: "\u{f0317}",
            wol: "\u{f0425}",
            hostname: "\u{f048b}",
            firewall: "\u{f099d}",
            "wifi-boot": "\u{f05aa}",
            locked: "\u{f033e}"
        })
    // Wi-Fi signal in four tiers (Wifi.tier()), weakest first.
    readonly property var wifiTiers: ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"]

    readonly property var wired: Networking.devices.values.filter(d => d.type === DeviceType.Wired).sort((a, b) => a.name.localeCompare(b.name))
    // Interface -> { connection, addresses, gateway, dns }, from nmcli.
    property var info: ({})
    // Interface -> "full" / "half", from sysfs.
    property var duplex: ({})
    property string routeDevice: ""
    // Connection name -> newest stored record.
    property var latest: ({})
    // Connection name -> provider id -> newest stored record.
    property var latestBy: ({})
    // The provider of the newest stored record, any connection.
    property string historyChoice: ""
    // The chooser row last run in this shell: a provider id or "all".
    property string sessionChoice: ""
    // Connection name -> highest download or upload stored for it, in Mb/s.
    property var best: ({})
    readonly property var locked: lockedFile.entries
    readonly property bool lockedPresent: lockedFile.present

    // Enum names by value, as enums.hpp in Quickshell's network module
    // orders them; network/wifi.js works on the names.
    readonly property var securityNames: ["Wpa3SuiteB192", "Sae", "Wpa2Eap", "Wpa2Psk", "WpaEap", "WpaPsk", "StaticWep", "DynamicWep", "Leap", "Owe", "Open", "Unknown"]
    readonly property var stateNames: ["Unknown", "Connecting", "Connected", "Disconnecting", "Disconnected"]
    readonly property var failNames: ["Unknown", "NoSecrets", "WifiClientDisconnected", "WifiClientFailed", "WifiAuthTimeout", "WifiNetworkLost"]
    readonly property var connectivityNames: ["Unknown", "None", "Portal", "Limited", "Full"]

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    // The networks as plain rows, read only while the panel is open. Never
    // keep a WifiNetwork: effects look one up by name when they run.
    readonly property var wifiRows: open && wifiDevice ? wifiDevice.networks.values.map(n => ({
                name: n.name,
                signal: n.signalStrength,
                security: securityNames[n.security] ?? "Unknown",
                known: n.known,
                connected: n.connected,
                state: stateNames[n.state] ?? "Unknown",
                stateChanging: n.stateChanging
            })) : []
    readonly property var wifiIn: ({
            device: wifiDevice !== null,
            hardware: Networking.wifiHardwareEnabled,
            radio: Networking.wifiEnabled,
            answered: wifiAnswered,
            rows: wifiRows,
            connectivity: connectivityNames[Networking.connectivity] ?? "Unknown",
            wiredRoute: wired.some(d => d.name === routeDevice),
            info: wifiDevice ? info[wifiDevice.name] ?? null : null,
            mac: wifiDevice?.address.toLowerCase() ?? ""
        })
    readonly property var wifiSection: Wifi.section(wifiIn)
    readonly property bool wifiRadio: wifiIn.device && wifiIn.hardware && wifiIn.radio
    // The module has no scan-finished signal: a scan has answered once a
    // network shows that only a scan can list (neither saved nor active),
    // or once a scan period has passed (answerTimer).
    property bool wifiAnswered: false
    property bool scanning: false
    property bool rescanning: false
    // network/wifi.js's machine, replaced by each step()'s result.
    property var wifi: Wifi.initial()
    // The last Wifi.list() result, rebuilt only when its key changes.
    property var wifiView: ({
            names: [],
            rows: [],
            key: ""
        })
    // Name -> connected, as last synced, to tell arrivals, departures and
    // new connections apart.
    property var wifiSeen: ({})

    readonly property var rows: wired.map(d => ({
                kind: "wired",
                key: "w:" + d.name,
                device: d
            })).concat(wifiSection.state === "list" ? wifiView.rows.map(v => ({
                    kind: "wifi",
                    key: "f:" + v.name,
                    view: v
                })) : [], lockedPresent ? locked.map((l, n) => ({
                    kind: "nix",
                    key: "n" + n,
                    entry: l
                })) : [])
    // Selection by key, so a row that comes or goes during a scan does not
    // move it.
    property string currentKey: ""
    property int lastIndex: 0
    // With the selected row gone, the row at its old place; never a Set in
    // Nix row, which is only selected by ↓ or a click. -1 with none.
    readonly property int current: {
        const at = rows.findIndex(r => r.key === currentKey);
        if (at >= 0)
            return at;
        let i = Math.min(lastIndex, rows.length - 1);
        while (i >= 0 && rows[i].kind === "nix")
            i--;
        return i;
    }
    readonly property var currentRow: rows[current] ?? null
    readonly property string selectedKey: currentRow?.key ?? ""
    // The selected Wi-Fi network as a plain row, or null.
    readonly property var wifiSelected: currentRow?.kind === "wifi" ? wifiIn.rows.find(r => r.name === currentRow.view.name) ?? null : null
    property string expanded: ""
    property string flash: ""
    // The connection whose figures were just measured, until the panel closes.
    property string fresh: ""
    property date now: new Date()

    // list, out, chooser, run, hold, failed, next, done, back: see
    // openChooser(), choose(), back().
    property string phase: "list"
    // The screen in the card: "list", "chooser" or "gauges"; layerIn fades it.
    property string layer: "list"
    property bool layerIn: true
    property string pendingLayer: ""
    property var pendingThen: null
    // Chooser rows: the providers, then "all".
    readonly property var choices: speedTest.providers.map(p => p.id).concat(["all"])
    property int chosen: 0
    // Provider ids to run, in order, and the one running now.
    property var queue: []
    property int queueIndex: 0
    readonly property bool allMode: queue.length > 1
    // Provider id -> { download, upload, ping } or { failed: true }.
    property var results: ({})
    property string bestId: ""
    property int savedCount: 0
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
        Dropdowns.closeOthers("network");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        // The connected wired device, else the first one; with none, nothing
        // (the Set in Nix rows are only selected by ↓ or a click).
        const up = wired.find(d => d.connected) ?? wired[0];
        currentKey = up ? "w:" + up.name : "";
        lastIndex = 0;
        expanded = "";
        flash = "";
        fresh = "";
        now = new Date();
        wifi = Wifi.initial();
        wifiSeen = {};
        wifiView = {
            names: [],
            rows: [],
            key: ""
        };
        infoQuery.running = true;
        records.reload();
        lockedFile.reload();
        NetworkPanel.screen = window.screen.name;
        syncScanner();
    }

    function close(): void {
        if (speedTest.running)
            speedTest.cancel();
        resetTest();
        wifiStep({
            type: "closed"
        });
        NetworkPanel.screen = "";
        syncScanner();
    }

    function select(index: int): void {
        const row = rows[Math.max(0, Math.min(index, rows.length - 1))];
        if (!row)
            return;
        currentKey = row.key;
        lastIndex = rows.indexOf(row);
    }

    // The scanner runs only while the panel is open with the radio on. The
    // password modal hides the panel's window without closing the panel, so
    // it keeps running then.
    function syncScanner(): void {
        const want = open && wifiRadio;
        if (want === scanning)
            return;
        scanning = want;
        if (want)
            restartAnswer();
        else
            answerTimer.stop();
        if (wifiDevice && wifiDevice.scannerEnabled !== want)
            wifiDevice.scannerEnabled = want;
    }

    function restartAnswer(): void {
        wifiAnswered = false;
        answerTimer.restart();
    }

    function wifiNetwork(name: string): var {
        return wifiDevice?.networks.values.find(n => n.name === name) ?? null;
    }

    // Feeds one event to the machine and performs its effects in order.
    // `psk` is the modal's text for a connectWithPsk effect, "" otherwise.
    function wifiStep(event: var, psk: var): var {
        const r = Wifi.step(wifi, event);
        if (r.state !== wifi)
            wifi = r.state;
        for (const e of r.effects)
            perform(e, psk ?? "");
        return r;
    }

    function perform(e: var, psk: var): void {
        switch (e.do) {
        case "connect":
            wifiNetwork(e.name)?.connect();
            break;
        case "connectWithPsk":
            wifiNetwork(e.name)?.connectWithPsk(psk);
            break;
        case "disconnect":
            wifiNetwork(e.name)?.disconnect();
            break;
        case "cancel":
            // Network.disconnect() refuses a network that is not connected
            // yet; the device's stops a join in flight.
            wifiDevice?.disconnect();
            break;
        case "forget":
            wifiNetwork(e.name)?.forget();
            break;
        case "openModal":
            if (!modal.request)
                modal.screen = window.screen;
            modal.request = {
                title: e.title,
                detail: e.detail,
                error: e.error,
                hint: e.hint,
                security: wifi.target?.security ?? ""
            };
            break;
        case "closeModal":
            modal.request = null;
            break;
        case "watchdog":
            if (e.run)
                watchdog.restart();
            else
                watchdog.stop();
            break;
        case "radio":
            Networking.wifiEnabled = e.on;
            break;
        case "rescan":
            if (wifiDevice && scanning) {
                // Off and on at once: the networks only a scan lists leave
                // and come back within this call, which is not a departure.
                rescanning = true;
                wifiDevice.scannerEnabled = false;
                wifiDevice.scannerEnabled = true;
                rescanning = false;
                restartAnswer();
                syncWifi();
            }
            break;
        case "say":
            say(e.text);
            break;
        }
    }

    // The modal's Enter, after Wifi.passwordCheck() allowed its text. The
    // text leaves the field here and goes only to connectWithPsk.
    function submitPassword(): void {
        const name = wifi.target?.name ?? "";
        const psk = modal.take();
        wifiStep({
            type: "submit",
            row: wifiIn.rows.find(r => r.name === name) ?? null
        }, psk);
    }

    function wifiKey(k: string, repeat: bool): bool {
        return wifiStep({
            type: "key",
            key: k,
            row: wifiSelected,
            section: wifiSection,
            repeat: repeat
        }).handled;
    }

    // Turns changes in the rows into the machine's events (a network left,
    // one became connected or disconnected), then rebuilds the view if
    // anything drawn moved.
    function syncWifi(): void {
        const rows = wifiIn.rows;
        // Later: this runs inside wifiIn's update, and wifiIn reads
        // wifiAnswered, so writing it now is a binding loop.
        if (scanning && !wifiAnswered && rows.some(r => !r.known && !r.connected))
            Qt.callLater(answerScan);
        if (!rescanning) {
            const seen = {};
            for (const r of rows)
                seen[r.name] = r.connected;
            for (const name of Object.keys(wifiSeen)) {
                if (!(name in seen))
                    wifiStep({
                        type: "vanished",
                        name
                    });
            }
            for (const name of Object.keys(seen)) {
                if (seen[name] && !wifiSeen[name]) {
                    wifiStep({
                        type: "connected",
                        name
                    });
                    // The address, gateway and DNS arrive with the link.
                    if (open)
                        infoQuery.running = true;
                } else if (!seen[name] && wifiSeen[name]) {
                    wifiStep({
                        type: "disconnected",
                        name
                    });
                }
            }
            wifiSeen = seen;
        }
        refreshWifi();
    }

    function answerScan(): void {
        if (scanning)
            wifiAnswered = true;
    }

    function refreshWifi(): void {
        const v = Wifi.list(wifiIn.rows, wifi, wifiView.names, {
            connectivity: wifiIn.connectivity,
            wiredRoute: wifiIn.wiredRoute
        });
        if (v.key !== wifiView.key)
            wifiView = v;
    }

    function wifiDetails(name: string): var {
        const row = wifiIn.rows.find(r => r.name === name);
        if (!row)
            return [];
        const nm = wifiIn.info;
        return Wifi.details(row, {
            address: nm?.addresses.map(a => a.split("/")[0]).join(", ") ?? "",
            gateway: nm?.gateway ?? "",
            dns: nm?.dns.join(", ") ?? "",
            mac: wifiIn.mac,
            wiredRoute: wifiIn.wiredRoute
        });
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
        } else if (row.kind === "wifi") {
            wifiKey("Enter", false);
        } else if (row.device.connected) {
            expanded = expanded === row.device.name ? "" : row.device.name;
        } else {
            say(row.device.hasLink ? `${row.device.name} is not connected.` : `No cable in ${row.device.name}.`);
        }
    }

    // The selected wired or Nix row's Enter, as the footer hints it: what
    // activate() does there.
    function rowKeys(): var {
        const row = rows[current];
        if (!row || row.kind === "wifi")
            return [];
        if (row.kind === "nix")
            return [["Enter", "show file"]];
        if (!row.device.connected)
            return [];
        return [["Enter", expanded === row.device.name ? "close details" : "details"]];
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
        swapTimer.stop();
        startTimer.stop();
        holdTimer.stop();
        nextTimer.stop();
        phase = "list";
        download = NaN;
        upload = NaN;
        queue = [];
        layer = "list";
        layerIn = true;
    }

    // Fades the current screen out, then shows `to` and calls `then`.
    function swap(to: string, then: var): void {
        layerIn = false;
        pendingLayer = to;
        pendingThen = then;
        swapTimer.restart();
    }

    function provider(id: string): var {
        return speedTest.find(id);
    }

    // A stored record as `↓ 742 ↑ 801`, with ` · 29 ms` when asked.
    function figures(r: var, withPing: bool): string {
        return `↓ ${Math.round(r.download_mbps)} ↑ ${Math.round(r.upload_mbps)}` + (withPing ? ` · ${Math.round(r.ping_ms)} ms` : "");
    }

    // Records written before providers existed came from Cloudflare.
    function providerOf(r: var): string {
        return typeof r.provider === "string" ? r.provider : "cloudflare";
    }

    // Takes a record, newest last, into latest, latestBy, best and
    // historyChoice.
    function remember(r: var): void {
        const latest = Object.assign({}, root.latest);
        latest[r.connection] = r;
        root.latest = latest;
        const by = Object.assign({}, root.latestBy);
        by[r.connection] = Object.assign({}, by[r.connection] ?? {});
        by[r.connection][providerOf(r)] = r;
        root.latestBy = by;
        const best = Object.assign({}, root.best);
        best[r.connection] = Math.max(best[r.connection] ?? 0, Number(r.download_mbps) || 0, Number(r.upload_mbps) || 0);
        root.best = best;
        root.historyChoice = providerOf(r);
    }

    function openChooser(): void {
        if (!open || phase !== "list")
            return;
        expanded = "";
        // The route may have moved since the panel opened (a cable plugged
        // in); a run is filed under the route read here.
        infoQuery.running = true;
        const last = sessionChoice || historyChoice;
        chosen = Math.max(0, choices.indexOf(last));
        phase = "out";
        swap("chooser", () => root.phase = "chooser");
    }

    // Runs chooser row `index`: one provider, or all of them in turn.
    function choose(index: int): void {
        if (phase !== "chooser" || index < 0 || index >= choices.length)
            return;
        const id = choices[index];
        sessionChoice = id;
        queue = id === "all" ? speedTest.providers.map(p => p.id) : [id];
        queueIndex = 0;
        results = {};
        bestId = "";
        savedCount = 0;
        ping = NaN;
        download = NaN;
        upload = NaN;
        measuring = "";
        failure = "";
        savedAt = "";
        testInterface = routeDevice;
        testConnection = info[routeDevice]?.connection ?? "";
        phase = "out";
        swap("gauges", () => startTimer.start());
    }

    // Runs queue[queueIndex].
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
        speedTest.start(queue[queueIndex]);
    }

    function fail(reason: string): void {
        measuring = "";
        ping = NaN;
        download = NaN;
        upload = NaN;
        failure = reason;
        if (!allMode) {
            phase = "failed";
            return;
        }
        // In turn, a failure is noted and the next provider still runs.
        const r = Object.assign({}, results);
        r[queue[queueIndex]] = {
            failed: true
        };
        results = r;
        afterProvider(2000);
    }

    // In turn: after a short pause the next provider starts from zeroed
    // gauges, or, after the last one, the fastest result stays shown.
    function afterProvider(pause: int): void {
        if (queueIndex + 1 < queue.length) {
            phase = "next";
            nextTimer.interval = pause;
            nextTimer.start();
            return;
        }
        let best = "";
        for (const id of queue) {
            const r = results[id];
            if (r && !r.failed && (best === "" || r.download > results[best].download))
                best = id;
        }
        bestId = best;
        measuring = "";
        failure = "";
        download = best ? results[best].download : NaN;
        upload = best ? results[best].upload : NaN;
        ping = best ? results[best].ping : NaN;
        phase = "done";
    }

    // Back to the list. Cancels a run in progress, which then stores
    // nothing; runs already finished stay stored.
    function back(): void {
        startTimer.stop();
        holdTimer.stop();
        nextTimer.stop();
        if (speedTest.running)
            speedTest.cancel();
        phase = "back";
        swap("list", () => {
            // Cleared while hidden, so the next run's gauges start at zero.
            root.download = NaN;
            root.upload = NaN;
            root.queue = [];
            root.phase = "list";
        });
    }

    Timer {
        id: swapTimer

        interval: 210
        onTriggered: {
            root.layer = root.pendingLayer;
            root.layerIn = true;
            const then = root.pendingThen;
            root.pendingThen = null;
            if (then)
                then();
        }
    }

    Timer {
        id: startTimer

        interval: 380
        // Waits for the route read openChooser() started.
        onTriggered: infoQuery.running ? startTimer.restart() : root.runTest()
    }

    Timer {
        id: holdTimer

        interval: 1500
        onTriggered: root.back()
    }

    Timer {
        id: nextTimer

        onTriggered: {
            root.queueIndex += 1;
            root.download = NaN;
            root.upload = NaN;
            root.ping = NaN;
            root.failure = "";
            root.measuring = "";
            // Lets the gauges ease to zero before the next figures arrive.
            startTimer.start();
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

    // A join that neither connects nor fails: some failures send no signal.
    Timer {
        id: watchdog

        interval: Wifi.WATCHDOG_MS
        onTriggered: root.wifiStep({
            type: "watchdog"
        })
    }

    // The module scans every 10 s while its scanner is on; past one period,
    // what is listed is what a scan found.
    Timer {
        id: answerTimer

        interval: 12000
        onTriggered: root.wifiAnswered = true
    }

    onWifiInChanged: syncWifi()
    onWifiChanged: refreshWifi()
    // Later, not inside wifiIn's update (wifiRadio is bound to it):
    // syncScanner() writes wifiAnswered, and turning the scanner off drops
    // the networks only a scan lists at once, both of which wifiIn reads.
    onWifiRadioChanged: Qt.callLater(radioChanged)

    function radioChanged(): void {
        if (!wifiRadio)
            wifiStep({
                type: "radioOff"
            });
        syncScanner();
    }
    // Later, not inside the binding update that moved the selection: the
    // step can rebuild the rows that `current` is computed from. A selected
    // row that left hands the selection to the row now in its place, so it
    // does not jump back if the network returns.
    onSelectedKeyChanged: Qt.callLater(sendSelect)

    function sendSelect(): void {
        if (currentRow) {
            currentKey = currentRow.key;
            lastIndex = current;
        }
        wifiStep({
            type: "select",
            name: currentRow?.kind === "wifi" ? currentRow.view.name : null
        });
    }
    Component.onDestruction: {
        if (scanning && wifiDevice)
            wifiDevice.scannerEnabled = false;
    }

    // connectionFailed is a signal on each network; the module's own model
    // creates and drops these with its networks.
    Instantiator {
        model: root.open && root.wifiDevice ? root.wifiDevice.networks : null

        delegate: Connections {
            required property var modelData

            target: modelData

            function onConnectionFailed(reason) {
                root.wifiStep({
                    type: "failed",
                    name: modelData.name,
                    reason: root.failNames[reason] ?? "Unknown",
                    security: root.securityNames[modelData.security] ?? "Unknown"
                });
            }
        }
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
                provider: speedTest.provider.id,
                tool: speedTest.provider.tool
            };
            // A Process runs one command at a time; in turn, two appends
            // are tens of seconds apart.
            store.command = ["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" >> "$1/speedtests.jsonl"', "sh", root.stateDir, JSON.stringify(record)];
            store.running = true;
            root.remember(record);
            root.fresh = record.connection;
            root.now = new Date();
            root.savedAt = Qt.formatDateTime(new Date(), "HH:mm");
            root.savedCount += 1;
            if (!root.allMode) {
                root.phase = "hold";
                holdTimer.start();
                return;
            }
            const results = Object.assign({}, root.results);
            results[record.provider] = {
                download: download,
                upload: upload,
                ping: ping
            };
            root.results = results;
            root.afterProvider(900);
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
            const latest = {}, by = {}, best = {};
            let choice = "";
            for (const line of text().split("\n")) {
                if (line.trim() === "")
                    continue;
                try {
                    const r = JSON.parse(line);
                    if (typeof r.connection !== "string")
                        continue;
                    latest[r.connection] = r;
                    by[r.connection] = by[r.connection] ?? {};
                    by[r.connection][root.providerOf(r)] = r;
                    best[r.connection] = Math.max(best[r.connection] ?? 0, Number(r.download_mbps) || 0, Number(r.upload_mbps) || 0);
                    choice = root.providerOf(r);
                } catch (e) {
                    console.warn("network: speedtests.jsonl:", e.message);
                }
            }
            root.latest = latest;
            root.latestBy = by;
            root.best = best;
            root.historyChoice = choice;
        }
        onLoadFailed: {
            root.latest = {};
            root.latestBy = {};
            root.best = {};
            root.historyChoice = "";
        }
    }

    LockedList {
        id: lockedFile

        area: "network"
    }

    Component.onCompleted: Dropdowns.add("network", NetworkPanel)

    Connections {
        target: NetworkPanel

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

    component Small: Text {
        width: parent.width
        elide: Text.ElideRight
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 12
    }

    PasswordModal {
        id: modal

        onSubmitted: root.submitPassword()
        onCancelled: root.wifiStep({
            type: "cancel"
        })
    }

    // Returns true when the key was used. `repeat`: a held key's auto-repeat,
    // which only ↑↓ act on.
    function key(k: int, modifiers: int, repeat: bool): bool {
        const plain = (modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        if (phase === "list") {
            const name = k === Qt.Key_Escape ? "Esc" : enter ? "Enter" : k === Qt.Key_F5 ? "F5" : !plain ? "" : k === Qt.Key_W ? "W" : k === Qt.Key_C ? "C" : k === Qt.Key_F ? "F" : "";
            if (wifiKey(name || "other", repeat))
                return true;
        }
        if (repeat && k !== Qt.Key_Up && k !== Qt.Key_Down)
            return true;
        if (k === Qt.Key_Escape) {
            if (phase === "list") {
                if (expanded !== "")
                    expanded = "";
                else
                    close();
            } else if (phase !== "back") {
                // From the chooser or a run alike, Esc lands on the list.
                back();
            }
        } else if (phase === "failed" && enter) {
            runTest();
        } else if (phase === "chooser") {
            const n = k - Qt.Key_1;
            if (k === Qt.Key_Down)
                chosen = Math.min(chosen + 1, choices.length - 1);
            else if (k === Qt.Key_Up)
                chosen = Math.max(chosen - 1, 0);
            else if (enter)
                choose(chosen);
            else if (plain && n >= 0 && n < choices.length)
                choose(n);
            else
                return false;
        } else if (phase !== "list") {
            // Keys wait while the gauges show.
        } else if (k === Qt.Key_Down) {
            select(current + 1);
        } else if (k === Qt.Key_Up) {
            select(current - 1);
        } else if (enter) {
            activate();
        } else if (k === Qt.Key_S && plain) {
            openChooser();
        } else {
            return false;
        }
        return true;
    }

    PanelWindow {
        id: window

        // Hidden, not closed, while the password modal asks, so the modal
        // has the keyboard and the panel keeps its state and scan.
        visible: root.open && !modal.visible
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
                if (root.key(event.key, event.modifiers, event.isAutoRepeat))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("network", NetworkPanel.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: root.layer === "gauges" ? gaugeView.implicitHeight : root.layer === "chooser" ? chooser.implicitHeight : list.implicitHeight

            Column {
                id: list

                x: 1
                y: 1
                width: parent.width - 2
                visible: root.layer === "list"
                opacity: root.layerIn ? 1 : 0

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
                                        root.select(wiredRow.index);
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
                                        textFormat: Text.PlainText
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

                                    // Flow: with the provider named, the line is wider than the
                                    // row, so provider and age wrap under the figures.
                                    Flow {
                                        visible: wiredRow.up
                                        width: parent.width

                                        Small {
                                            width: undefined
                                            text: wiredRow.record ? `↓ ${Math.round(wiredRow.record.download_mbps)}  ↑ ${Math.round(wiredRow.record.upload_mbps)} Mb/s · ${Math.round(wiredRow.record.ping_ms)} ms ` : "↓ --  ↑ --  Mb/s "
                                            color: wiredRow.record && root.fresh === wiredRow.connection ? Theme.cyan : root.soft
                                        }

                                        Small {
                                            width: undefined
                                            text: "· " + (wiredRow.record ? `${root.providerOf(wiredRow.record)} · ${root.age(wiredRow.record.at)}` : "never run")
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
                                id: wiredDetails

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
                                        width: wiredDetails.width - 12

                                        Repeater {
                                            model: {
                                                const d = wiredRow.modelData, nm = wiredRow.nm;
                                                const duplex = root.duplex[d.name];
                                                return [["address", nm?.addresses.join(", ") || "–"], ["gateway", nm?.gateway || "–"], ["dns", nm?.dns.join(", ") || "–"], ["mac", d.address.toLowerCase() || "–"], ["link", d.linkSpeed > 0 ? `${root.linkText(d.linkSpeed)}${duplex === "full" || duplex === "half" ? ` ${duplex} duplex` : ""}` : "–"]];
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
                                                    width: details.width - 72
                                                    text: parent.modelData[1]
                                                    wrapMode: Text.Wrap
                                                    color: root.soft
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 12
                                                    lineHeight: 1.7
                                                }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    width: 1
                                    height: 4
                                }

                                Rectangle {
                                    width: 2
                                    height: perProvider.implicitHeight + 4
                                    color: Theme.currentLine

                                    Column {
                                        id: perProvider

                                        x: 12
                                        y: 2

                                        Repeater {
                                            model: speedTest.providers

                                            Row {
                                                required property var modelData
                                                readonly property var record: root.latestBy[wiredRow.connection]?.[modelData.id] ?? null

                                                Text {
                                                    width: 84
                                                    text: parent.modelData.id
                                                    color: Theme.comment
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 12
                                                    lineHeight: 1.7
                                                }

                                                Text {
                                                    text: parent.record ? `${root.figures(parent.record, true)} · ${root.age(parent.record.at)}` : "never run"
                                                    color: parent.record ? root.soft : Theme.comment
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

                Item {
                    width: parent.width
                    height: wifiHeader.implicitHeight

                    SectionHeader {
                        id: wifiHeader

                        text: "WI-FI"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.baseline: wifiHeader.baseline
                        text: root.wifiSection.word
                        color: Theme.comment
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                Text {
                    visible: root.wifiSection.line !== ""
                    width: parent.width
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 6
                    bottomPadding: 8
                    wrapMode: Text.Wrap
                    text: root.wifiSection.line
                    color: Theme.comment
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    lineHeight: 1.1
                }

                Column {
                    visible: root.wifiSection.state === "list"
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.wifiSection.state === "list" ? root.wifiView.rows : []

                        Column {
                            id: wifiRow

                            required property var modelData
                            readonly property var v: modelData
                            readonly property bool selected: root.currentRow?.key === "f:" + v.name
                            readonly property color lineColor: v.lineTone === "red" ? Theme.red : v.lineTone === "dim" ? Theme.comment : root.soft

                            width: parent.width - 12
                            spacing: 2

                            Rectangle {
                                width: parent.width
                                height: wifiText.implicitHeight + 14
                                radius: 6
                                color: wifiRow.selected ? Theme.currentLine : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.select(root.rows.findIndex(r => r.key === "f:" + wifiRow.v.name));
                                        root.wifiKey("Enter", false);
                                    }
                                }

                                Text {
                                    id: wifiIcon

                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.wifiTiers[wifiRow.v.tier - 1]
                                    color: wifiRow.v.stateTone === "green" ? Theme.green : wifiRow.v.dim ? Theme.comment : Theme.foreground
                                    font.family: Theme.fontMono
                                    font.pixelSize: 16
                                }

                                Column {
                                    id: wifiText

                                    anchors.left: wifiIcon.right
                                    anchors.leftMargin: 10
                                    anchors.right: wifiState.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: wifiRow.v.name
                                        textFormat: Text.PlainText
                                        color: wifiRow.v.dim ? Theme.comment : Theme.foreground
                                        font.family: Theme.fontUi
                                        font.pixelSize: 15
                                        font.weight: wifiRow.v.dim ? Font.Normal : Font.Medium
                                    }

                                    // Wraps: only the name may be cut short.
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        text: wifiRow.v.line
                                        color: wifiRow.lineColor
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        visible: wifiRow.v.portal !== ""
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        text: wifiRow.v.portal
                                        color: Theme.orange
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                    }
                                }

                                Text {
                                    id: wifiState

                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wifiRow.v.state
                                    color: wifiRow.v.stateTone === "green" ? Theme.green : Theme.cyan
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }

                            Column {
                                visible: wifiRow.v.expanded
                                x: 28
                                width: parent.width - 28
                                bottomPadding: 4

                                Rectangle {
                                    width: 2
                                    height: wifiDetails.implicitHeight + 4
                                    color: Theme.currentLine

                                    Column {
                                        id: wifiDetails

                                        x: 12
                                        y: 2

                                        Repeater {
                                            model: wifiRow.v.expanded ? root.wifiDetails(wifiRow.v.name) : []

                                            Row {
                                                required property var modelData

                                                Text {
                                                    width: 72
                                                    text: parent.modelData.label
                                                    color: Theme.comment
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 12
                                                    lineHeight: 1.7
                                                }

                                                Text {
                                                    width: wifiRow.width - 28 - 12 - 72 - 8
                                                    wrapMode: Text.Wrap
                                                    text: parent.modelData.value
                                                    color: parent.modelData.tone === "dim" ? Theme.comment : root.soft
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
                            readonly property int row: root.rows.findIndex(r => r.key === "n" + index)

                            width: parent.width - 12
                            height: lockedLabel.implicitHeight + 14
                            radius: 6
                            color: root.current === row ? Theme.currentLine : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.select(lockedRow.row);
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
                                wrapMode: Text.Wrap
                                text: lockedRow.modelData.label
                                color: Theme.comment
                                font.family: Theme.fontUi
                                font.pixelSize: 15
                            }

                            NixTag {
                                id: tag

                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                KeyHints {
                    keys: Wifi.hints(root.wifi, root.wifiSection, root.wifiSelected, {
                        moves: root.rows.length > (root.current >= 0 ? 1 : 0),
                        speedTest: true,
                        rowKeys: root.rowKeys(),
                        esc: root.expanded !== "" ? "back" : "close"
                    })
                    message: root.flash
                }
            }

            Column {
                id: chooser

                x: 1
                y: 1
                width: parent.width - 2
                visible: root.layer === "chooser"
                opacity: root.layerIn ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                SectionHeader {
                    text: "SPEED TEST WITH"
                }

                Column {
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.choices

                        Rectangle {
                            id: choiceRow

                            required property string modelData
                            required property int index
                            readonly property var provider: root.provider(modelData)
                            readonly property var record: provider ? root.latestBy[root.info[root.routeDevice]?.connection ?? ""]?.[modelData] ?? null : null

                            width: parent.width - 12
                            height: choiceText.implicitHeight + 14
                            radius: 6
                            color: root.chosen === index ? Theme.currentLine : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.choose(choiceRow.index)
                            }

                            Rectangle {
                                id: number

                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: numberText.implicitWidth + 10
                                height: numberText.implicitHeight + 2
                                radius: 4
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.currentLine

                                Text {
                                    id: numberText

                                    anchors.centerIn: parent
                                    text: String(choiceRow.index + 1)
                                    color: Theme.comment
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }

                            Column {
                                id: choiceText

                                anchors.left: number.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: choiceRow.provider?.name ?? "All in turn"
                                    color: Theme.foreground
                                    font.family: Theme.fontUi
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                }

                                Small {
                                    text: choiceRow.provider?.host ?? "each provider, about a minute"
                                }

                                Small {
                                    visible: choiceRow.provider !== null
                                    text: choiceRow.record ? `${root.figures(choiceRow.record, false)} · ${root.age(choiceRow.record.at)}` : "never run"
                                    color: choiceRow.record ? root.soft : Theme.comment
                                }
                            }
                        }
                    }
                }

                KeyHints {
                    keys: [["↑↓", "select"], ["Enter", "run"], ["1-" + root.choices.length, "run that one"], ["Esc", "back"]]
                }
            }

            Column {
                id: gaugeView

                x: 1
                y: 1
                width: parent.width - 2
                visible: root.layer === "gauges"
                opacity: root.layerIn ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Row {
                    visible: root.allMode
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 12
                    spacing: 6

                    Repeater {
                        model: root.queue

                        Rectangle {
                            id: chip

                            required property string modelData
                            required property int index
                            readonly property bool on: root.queueIndex === index && root.phase !== "done"
                            readonly property bool done: root.results[modelData] !== undefined && !root.results[modelData].failed

                            width: chipText.implicitWidth + 18
                            height: chipText.implicitHeight + 4
                            radius: height / 2
                            color: on ? Qt.rgba(Theme.purple.r, Theme.purple.g, Theme.purple.b, 0.12) : "transparent"
                            border.width: 1
                            border.color: on ? Theme.purple : Theme.currentLine

                            Text {
                                id: chipText

                                anchors.centerIn: parent
                                text: root.provider(chip.modelData)?.name ?? chip.modelData
                                color: chip.on ? Theme.foreground : chip.done ? Theme.green : Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    // Grows only for a failure text too long for the fixed height.
                    height: Math.max(root.allMode ? root.gaugeHeightAll : root.gaugeHeight, gaugeBody.implicitHeight + 8)

                    Column {
                        id: gaugeBody

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

                        // One text so that, when the pairs are wider than the
                        // card, whole pairs wrap to a second centred line.
                        Text {
                            readonly property var pairs: {
                                if (root.phase === "failed")
                                    return [];
                                const via = ["via", root.testInterface || "–"];
                                const latency = ["latency", isNaN(root.ping) ? "measuring…" : `${Math.round(root.ping)} ms`];
                                if (!root.allMode) {
                                    const pairs = [["provider", root.provider(root.queue[0])?.name ?? "–"], latency, via];
                                    if (root.savedAt !== "")
                                        pairs.push(["saved", root.savedAt]);
                                    return pairs;
                                }
                                if (root.phase === "done") {
                                    const saved = ["saved", root.savedCount === 1 ? "1 run" : `${root.savedCount} runs`];
                                    return root.bestId ? [["fastest", root.provider(root.bestId).name], via, saved] : [["result", "none"], saved];
                                }
                                const test = ["test", `${root.queueIndex + 1} of ${root.queue.length}`];
                                if (root.failure !== "")
                                    return [[root.provider(root.queue[root.queueIndex])?.name ?? "", "failed"], test];
                                return [latency, via, test];
                            }

                            visible: pairs.length > 0
                            width: parent.width
                            topPadding: 10
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: pairs.map(p => `${p[0]}&nbsp;<font color="${root.soft}">${String(p[1]).replace(/ /g, "&nbsp;")}</font>`).join("&nbsp; ")
                            textFormat: Text.StyledText
                            color: Theme.comment
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }

                        Text {
                            visible: root.failure !== ""
                            width: parent.width
                            topPadding: root.allMode ? 4 : 10
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: root.allMode ? root.failure : `${root.failure}. Enter retries, Esc returns.`
                            color: Theme.red
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                        }
                    }
                }

                // In turn: one line per provider, current cyan, waiting muted.
                Column {
                    visible: root.allMode
                    width: parent.width
                    leftPadding: 14
                    rightPadding: 14
                    bottomPadding: 10
                    spacing: 2

                    Repeater {
                        model: [null].concat(root.queue)

                        Row {
                            id: resultRow

                            required property var modelData
                            required property int index
                            readonly property var result: modelData ? root.results[modelData] ?? null : null
                            readonly property bool live: modelData !== null && index - 1 === root.queueIndex && root.phase !== "done" && !result
                            readonly property bool best: modelData !== null && root.phase === "done" && modelData === root.bestId
                            readonly property var cells: {
                                if (modelData === null)
                                    return ["provider", "down", "up", "ping"];
                                const name = root.provider(modelData)?.name ?? modelData;
                                const r = result;
                                if (r && !r.failed)
                                    return [name, String(Math.round(r.download)), String(Math.round(r.upload)), `${Math.round(r.ping)} ms`];
                                if (r)
                                    return [name, "", "", "failed"];
                                if (live) {
                                    const shown = v => isNaN(v) ? "…" : String(Math.round(v));
                                    return [name, shown(root.download), shown(root.upload), isNaN(root.ping) ? "…" : `${Math.round(root.ping)} ms`];
                                }
                                return [name, "", "", "waiting"];
                            }
                            readonly property color tone: live ? Theme.cyan : modelData === null || !result || result.failed ? Theme.comment : root.soft

                            width: parent.width - 28
                            spacing: 8

                            Text {
                                width: parent.width - 56 - 56 - 60 - 3 * 8
                                elide: Text.ElideRight
                                text: resultRow.cells[0]
                                color: resultRow.best ? Theme.green : resultRow.tone
                                font.family: Theme.fontMono
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: [[1, 56], [2, 56], [3, 60]]

                                Text {
                                    required property var modelData

                                    width: modelData[1]
                                    horizontalAlignment: Text.AlignRight
                                    text: resultRow.cells[modelData[0]]
                                    color: resultRow.tone
                                    font.family: Theme.fontMono
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                KeyHints {
                    keys: {
                        if (root.allMode)
                            return [["Esc", root.phase === "done" ? "back to list" : "stop, keep finished"]];
                        if (root.phase === "failed")
                            return [["Enter", "retry"], ["Esc", "back"]];
                        return [["Esc", root.phase === "hold" ? "back" : "cancel"]];
                    }
                }
            }
        }
    }
}
