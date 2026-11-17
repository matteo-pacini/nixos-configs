import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.bluetooth
import qs.common
import "bluetooth/devices.js" as D
import "bluetooth/services.js" as S

// The Bluetooth panel, hanging under the bar's Bluetooth item on one monitor,
// and the pairing agent with its modal, which run for the whole session.
//   qs ipc call bluetooth toggle    the panel, on the focused monitor
//   qs ipc call bluetooth power     adapter on or off, confirmed by the OSD
// Paired devices (connected first), nearby ones after a scan (S, 30 s), then
// the settings Nix fixes (~/.local/share/desk/bluetooth/locked.json, absent
// with no file). The adapter is pairable only while this computer pairs a
// device or while "visible" (V) runs, so nothing can pair with it otherwise.
Scope {
    id: root

    readonly property bool open: BluetoothShared.screen !== ""
    readonly property int panelWidth: 380
    readonly property int scanSeconds: 30
    readonly property int visibleSeconds: 120

    readonly property color soft: Style.soft

    readonly property var adapter: BluetoothShared.adapter
    readonly property bool blocked: adapter !== null && adapter.state === BluetoothAdapterState.Blocked
    readonly property bool usable: adapter !== null && !blocked
    readonly property bool on: usable && adapter.enabled

    readonly property var paired: D.sortPaired(BluetoothShared.devices.filter(d => d.paired))
    readonly property var nearby: showNearby ? D.nearby(BluetoothShared.devices, BluetoothShared.rssi) : []
    readonly property bool anyRssi: nearby.some(d => BluetoothShared.rssi[d.dbusPath] !== undefined)

    readonly property var locked: lockedFile.entries
    readonly property bool lockedPresent: lockedFile.present

    readonly property var rows: !on ? [] : paired.map(d => ({
                kind: "paired",
                key: d.dbusPath,
                device: d
            })).concat(nearby.map(d => ({
                    kind: "nearby",
                    key: d.dbusPath,
                    device: d
                }))).concat(lockedPresent ? locked.map((l, n) => ({
                    kind: "nix",
                    key: "n" + n,
                    entry: l
                })) : [])
    property string currentKey: ""
    property int lastIndex: 0
    // With no row picked, the nearest device row; never a Set in Nix row,
    // which is only selected by ↓ or a click. -1 when no device is listed.
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
    readonly property bool canMove: rows.length > (current >= 0 ? 1 : 0)

    property string expanded: ""
    property string armed: ""
    property string flash: ""
    property double now: Date.now()

    // Scanning started here, and whether this opening has scanned (so the
    // Nearby list stays after the scan ends).
    property double scanUntil: 0
    property bool showNearby: false
    property double visibleUntil: 0
    readonly property bool visibleOn: visibleUntil > 0

    // Pairing started here: the device path, when, and the last sign of life
    // (start, agent request, answer).
    property string pairTarget: ""
    property double pairStarted: 0
    property double pairActivity: 0
    // Device path -> true, for rows showing a failure.
    property var pairFailed: ({})
    property var connectTried: ({})
    property var connectFailed: ({})
    // Device path -> { at, trusted } for pairings the user said yes to:
    // when, and whether that yes is what trusted the device (settleAccepted).
    property var accepted: ({})
    property var pairedBefore: []
    // The power toggle over IPC, waiting for the adapter to follow.
    property bool powerPending: false

    readonly property var request: agent.requests[0] ?? null
    // `request`, set only after the modal has been moved to its monitor.
    property var shownRequest: null
    readonly property var requestDevice: shownRequest ? device(shownRequest.device) : null

    function device(path: string): var {
        return BluetoothShared.devices.find(d => d.dbusPath === path) ?? null;
    }

    function toggle(screen: string): void {
        if (open) {
            close();
            return;
        }
        Dropdowns.closeOthers("bluetooth");
        window.screen = Array.from(Quickshell.screens).find(s => s.name === screen) ?? Quickshell.screens[0];
        expanded = "";
        armed = "";
        flash = "";
        showNearby = false;
        pairFailed = {};
        connectFailed = {};
        lastIndex = 0;
        currentKey = "";
        now = Date.now();
        lockedFile.reload();
        BluetoothShared.screen = window.screen.name;
    }

    function close(): void {
        stopScan();
        endVisible();
        if (pairTarget !== "")
            cancelPairing();
        BluetoothShared.screen = "";
    }

    function say(text: string): void {
        flash = text;
        flashTimer.restart();
    }

    function select(index: int): void {
        const row = rows[Math.max(0, Math.min(index, rows.length - 1))];
        if (!row)
            return;
        currentKey = row.key;
        lastIndex = rows.indexOf(row);
    }

    // Pairable only while this computer pairs or "visible" runs. BlueZ turns
    // it on whenever the agent registers, so this runs again then.
    function syncPairable(): void {
        const want = visibleOn || pairTarget !== "";
        if (usable && agent.ready && adapter.pairable !== want)
            adapter.pairable = want;
    }

    function startScan(): void {
        BluetoothShared.rssi = {};
        showNearby = true;
        scanUntil = Date.now() + scanSeconds * 1000;
        now = Date.now();
        adapter.discovering = true;
    }

    function stopScan(): void {
        if (scanUntil === 0)
            return;
        scanUntil = 0;
        if (usable && adapter.discovering)
            adapter.discovering = false;
    }

    function startVisible(): void {
        visibleUntil = Date.now() + visibleSeconds * 1000;
        now = Date.now();
        syncPairable();
        adapter.discoverable = true;
    }

    function endVisible(): void {
        if (!visibleOn)
            return;
        visibleUntil = 0;
        if (usable && adapter.discoverable)
            adapter.discoverable = false;
        syncPairable();
    }

    function startPairing(d: var): void {
        stopScan();
        const failed = Object.assign({}, pairFailed);
        delete failed[d.dbusPath];
        pairFailed = failed;
        pairTarget = d.dbusPath;
        pairStarted = Date.now();
        pairActivity = Date.now();
        syncPairable();
        // The pairable write and Pair() go out on the same connection in
        // this order; the pause lets BlueZ apply the first before the
        // kernel answers the device's pairing request.
        pairDelay.restart();
    }

    function cancelPairing(): void {
        const d = device(pairTarget);
        if (d && d.pairing)
            d.cancelPair();
        endPairing(false);
    }

    function endPairing(ok: bool): void {
        const path = pairTarget;
        if (path === "")
            return;
        pairTarget = "";
        pairDelay.stop();
        agent.dropDisplays(path);
        syncPairable();
        const d = device(path);
        if (ok && d) {
            d.trusted = true;
            if (!d.connected)
                d.connect();
            say(`Paired with ${d.name}.`);
            currentKey = path;
        } else if (!ok) {
            const failed = Object.assign({}, pairFailed);
            failed[path] = true;
            pairFailed = failed;
            settleAccepted(path);
        }
    }

    // A device is trusted on the user's yes to the pairing, before BlueZ
    // reports it paired, so the services it asks for right after pairing
    // are allowed at once instead of waiting on the modal while the device's
    // own timeout runs. If the pairing then fails, BlueZ keeps that trust on
    // an unpaired device (src/device.c, device_bonding_complete), so it is
    // withdrawn here: at once for `failedPath`, otherwise once the device
    // drops its connection unpaired or a minute has passed.
    function settleAccepted(failedPath: string): void {
        const accepted = Object.assign({}, root.accepted);
        for (const path of Object.keys(accepted)) {
            const d = device(path);
            const age = Date.now() - accepted[path].at;
            if (d?.paired) {
                delete accepted[path];
                continue;
            }
            // A pairing started here ends through endPairing() instead.
            const failed = path === failedPath || !d || (path !== pairTarget && (age > 60000 || (!d.connected && age > 4000)));
            if (!failed)
                continue;
            if (accepted[path].trusted && d && d.trusted) {
                d.trusted = false;
                console.info("bluetooth: trust withdrawn, the pairing did not complete");
            }
            delete accepted[path];
        }
        root.accepted = accepted;
    }

    // Quickshell's pair() gives up on BlueZ's reply after QtDBus's call
    // timeout while BlueZ may still wait on the user, so the outcome is read
    // from `paired` and the agent's requests instead.
    function checkPairing(): void {
        const d = device(pairTarget);
        if (!d) {
            endPairing(false);
        } else if (d.paired) {
            endPairing(true);
        } else if (Date.now() - pairStarted > 120000) {
            cancelPairing();
        } else if (!d.pairing && !agent.hasRequestFor(pairTarget) && Date.now() - pairActivity > 4000) {
            endPairing(false);
        }
    }

    function toggleConnection(d: var): void {
        if (d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting)
            return;
        if (d.connected) {
            d.disconnect();
            return;
        }
        const tried = Object.assign({}, connectTried);
        tried[d.dbusPath] = true;
        connectTried = tried;
        const failed = Object.assign({}, connectFailed);
        delete failed[d.dbusPath];
        connectFailed = failed;
        d.connect();
    }

    function power(): void {
        if (!usable) {
            BluetoothShared.announce(blocked ? "Bluetooth is blocked" : "No Bluetooth adapter", false);
            return;
        }
        powerPending = true;
        powerTimer.restart();
        adapter.enabled = !adapter.enabled;
    }

    function activate(): void {
        const row = currentRow;
        if (!row)
            return;
        if (row.kind === "nix")
            say(`Set in ${row.entry.file}. Change it there and deploy.`);
        else if (row.kind === "nearby")
            startPairing(row.device);
        else
            expanded = expanded === row.key ? "" : row.key;
    }

    // Returns true when the key was used.
    function key(k: int, plain: bool): bool {
        const enter = k === Qt.Key_Return || k === Qt.Key_Enter;
        const row = currentRow;
        if (k === Qt.Key_Escape) {
            if (armed !== "")
                armed = "";
            else if (expanded !== "")
                expanded = "";
            else if (pairTarget !== "")
                cancelPairing();
            else
                close();
            return true;
        }
        if (!usable)
            return false;
        if (k === Qt.Key_B && plain) {
            adapter.enabled = !adapter.enabled;
            return true;
        }
        if (!on || pairTarget !== "")
            return false;
        if (k === Qt.Key_Down) {
            select(current + 1);
        } else if (k === Qt.Key_Up) {
            select(current - 1);
        } else if (enter) {
            activate();
        } else if (k === Qt.Key_S && plain) {
            if (scanUntil > 0)
                stopScan();
            else
                startScan();
        } else if (k === Qt.Key_V && plain) {
            if (visibleOn)
                endVisible();
            else
                startVisible();
        } else if (k === Qt.Key_C && plain && row?.kind === "paired") {
            toggleConnection(row.device);
        } else if (k === Qt.Key_T && plain && row?.kind === "paired" && expanded === row.key) {
            row.device.trusted = !row.device.trusted;
        } else if (k === Qt.Key_F && plain && row?.kind === "paired") {
            if (armed === row.key) {
                armed = "";
                expanded = "";
                say(`Forgot ${row.device.name}.`);
                BluetoothShared.forgetAnswers(row.key);
                row.device.forget();
            } else {
                armed = row.key;
            }
        } else {
            return false;
        }
        return true;
    }

    function codecName(id: string): string {
        return ({
                sbc: "SBC",
                sbc_xq: "SBC XQ",
                aac: "AAC",
                ldac: "LDAC",
                aptx: "aptX",
                aptx_hd: "aptX HD",
                aptx_ll: "aptX Low Latency",
                faststream: "FastStream",
                lc3: "LC3 (LE Audio)",
                msbc: "mSBC, calls",
                cvsd: "CVSD, calls"
            })[id] ?? id.toUpperCase();
    }

    // The codec PipeWire negotiated for an audio device, or "".
    function codecOf(d: var): string {
        const node = Pipewire.nodes.values.find(n => n.name.startsWith("bluez_") && n.properties["api.bluez5.address"] === d.address && n.properties["api.bluez5.codec"]);
        return node ? codecName(node.properties["api.bluez5.codec"]) : "";
    }

    // What `d` does through this computer now (S.uses).
    function usesOf(d: var): var {
        const groups = Pipewire.linkGroups.values;
        const nodes = Pipewire.nodes.values.filter(n => n.name.startsWith("bluez_") && n.properties["api.bluez5.address"] === d.address).map(n => ({
                    profile: n.properties["api.bluez5.profile"] ?? "",
                    mediaClass: n.properties["media.class"] ?? "",
                    linked: groups.some(g => (g.source === n || g.target === n) && g.state === PwLinkState.Active)
                }));
        return S.uses(d.connected ? BluetoothShared.links[d.dbusPath] ?? null : null, d.connected ? nodes : [], BluetoothShared.answers[d.dbusPath] ?? {}, d.name);
    }

    function rowSub(d: var, nearbyRow: bool): var {
        const k = D.kind(d.icon).label;
        if (!on)
            return [k, "dim"];
        if (nearbyRow) {
            if (pairTarget === d.dbusPath)
                return [`${k} · pairing…`, "busy"];
            if (pairFailed[d.dbusPath])
                return [`${k} · pairing failed · Enter retries`, "bad"];
            return [k, ""];
        }
        if (armed === d.dbusPath)
            return ["press F again to forget", "arm"];
        if (d.state === BluetoothDeviceState.Connecting)
            return [`${k} · connecting…`, "busy"];
        if (d.state === BluetoothDeviceState.Disconnecting)
            return [`${k} · disconnecting…`, "busy"];
        if (connectFailed[d.dbusPath])
            return [`${k} · could not connect · C retries`, "bad"];
        if (d.connected && d.batteryAvailable && d.battery < 0.15)
            return [`${k} · connected · battery low`, "bad"];
        if (d.connected)
            return [`${k} · connected`, "up"];
        return [k, ""];
    }

    function details(d: var): var {
        const lines = [["address", d.address], ["trusted", d.trusted ? "yes, reconnects by itself" : "no, connects only when asked"]];
        const codec = d.connected ? codecOf(d) : "";
        if (codec !== "")
            lines.push(["codec", codec]);
        lines.push(["battery", d.batteryAvailable ? `${Math.round(d.battery * 100)}%` : "not reported"]);
        const uses = usesOf(d).lines;
        uses.forEach((u, i) => lines.push([i === 0 ? "uses" : "", `${u[0]}: ${u[1]}`]));
        if (uses.length === 0)
            lines.push(["uses", d.connected ? "nothing reported" : "nothing, not connected"]);
        return lines;
    }

    // Nerd Font (Material Design) glyphs for the roles on a device's row.
    readonly property var roleGlyph: ({
            calls: "\u{f03f2}",
            audio: "\u{f075a}",
            controls: "\u{f040e}",
            network: "\u{f0318}"
        })

    // Allowed sits between comment and foreground, so it reads as present
    // but not in use on a selected row too.
    function roleColor(state: string): color {
        return state === "active" ? Theme.green : state === "connected" ? Theme.foreground : Qt.tint(Theme.comment, Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.25));
    }

    function clock(ms: real): string {
        const s = Math.max(0, Math.ceil(ms / 1000));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    readonly property string busy: {
        if (!usable)
            return "";
        if (adapter.state === BluetoothAdapterState.Enabling)
            return "turning on…";
        if (adapter.state === BluetoothAdapterState.Disabling)
            return "turning off…";
        if (visibleOn)
            return `visible · ${clock(visibleUntil - now)}`;
        if (scanUntil > 0)
            return `scanning… ${Math.max(0, Math.ceil((scanUntil - now) / 1000))} s`;
        return "";
    }

    readonly property var hints: {
        if (!usable)
            return [["Esc", "close"]];
        if (!on)
            return [["B", "turn on"], ["Esc", "close"]];
        if (pairTarget !== "")
            return [["Esc", "cancel pairing"], ["B", "on/off"]];
        // The selected row's keys, then the ones that work on any row.
        const row = currentRow;
        const showing = row !== null && expanded === row.key;
        let keys = [];
        if (row?.kind === "nix")
            keys = [["Enter", "show file"]];
        else if (row?.kind === "nearby")
            keys = [["Enter", "pair"]];
        else if (row)
            keys = [["Enter", showing ? "close details" : "details"], ["C", row.device.connected ? "disconnect" : "connect"]].concat(showing ? [["T", row.device.trusted ? "untrust" : "trust"]] : [], [["F", "forget"]]);
        if (canMove)
            keys.push(["↑↓", "select"]);
        return keys.concat([["S", scanUntil > 0 ? "stop" : "scan"], ["V", visibleOn ? "hide" : "visible"], ["B", "on/off"], ["Esc", armed !== "" ? "cancel" : showing ? "back" : "close"]]);
    }

    // Also when the selection moves on its own (a row came or went).
    onSelectedKeyChanged: {
        armed = "";
        if (expanded !== "" && expanded !== selectedKey)
            expanded = "";
    }
    onOnChanged: {
        if (powerPending) {
            powerPending = false;
            powerTimer.stop();
            BluetoothShared.announce(on ? "Bluetooth on" : "Bluetooth off", on);
        }
        if (!on) {
            scanUntil = 0;
            visibleUntil = 0;
            if (pairTarget !== "")
                endPairing(false);
        }
    }
    onVisibleOnChanged: syncPairable()
    onRequestChanged: {
        if (request !== null && shownRequest === null) {
            const name = open ? BluetoothShared.screen : Hyprland.focusedMonitor?.name;
            modal.screen = Array.from(Quickshell.screens).find(s => s.name === name) ?? Quickshell.screens[0];
        }
        shownRequest = request;
    }

    // Connection attempts end in Connected or back in Disconnected.
    readonly property string stateKey: BluetoothShared.devices.map(d => d.dbusPath + ":" + d.state).join(",")
    onStateKeyChanged: {
        const tried = Object.assign({}, connectTried);
        const failed = Object.assign({}, connectFailed);
        for (const path of Object.keys(tried)) {
            const d = device(path);
            if (!d || d.state === BluetoothDeviceState.Connected) {
                delete tried[path];
            } else if (d.state === BluetoothDeviceState.Disconnected) {
                delete tried[path];
                failed[path] = true;
            }
        }
        connectTried = tried;
        connectFailed = failed;
    }

    // A device the user said yes to is trusted once paired, if the yes did
    // not already trust it, and a pairing while visible ends the visible
    // window.
    readonly property var pairedNow: BluetoothShared.devices.filter(d => d.paired).map(d => d.dbusPath)
    onPairedNowChanged: {
        const fresh = pairedNow.filter(p => !pairedBefore.includes(p));
        pairedBefore = pairedNow;
        const accepted = Object.assign({}, root.accepted);
        for (const path of fresh) {
            const d = device(path);
            if (accepted[path] && d) {
                d.trusted = true;
                delete accepted[path];
                if (visibleOn) {
                    endVisible();
                    say(`Paired with ${d.name}.`);
                }
            }
        }
        root.accepted = accepted;
    }

    Component.onCompleted: {
        pairedBefore = pairedNow;
        Dropdowns.add("bluetooth", BluetoothShared);
    }

    Agent {
        id: agent

        onRegistered: root.syncPairable()
        onRequestsChanged: if (root.pairTarget !== "" && hasRequestFor(root.pairTarget))
            root.pairActivity = Date.now()
    }

    PairModal {
        id: modal

        request: root.shownRequest
        deviceName: root.requestDevice?.name || "A device"
        kindLabel: {
            const k = D.kind(root.requestDevice?.icon ?? "").label;
            return k === "kind not reported" ? "device" : k;
        }
        glyph: D.kind(root.requestDevice?.icon ?? "").glyph
        initiated: root.shownRequest !== null && root.shownRequest.device === root.pairTarget

        onDecided: (accept, extra, trust) => {
            const r = root.shownRequest;
            if (!r)
                return;
            const d = root.device(r.device);
            if (r.id === null) {
                if (!accept && d && d.pairing)
                    d.cancelPair();
                agent.dropDisplays(r.device);
                return;
            }
            // A yes to the pairing itself trusts the device now (settleAccepted).
            if (accept && r.method !== "AuthorizeService") {
                const accepted = Object.assign({}, root.accepted);
                accepted[r.device] = {
                    at: Date.now(),
                    trusted: d !== null && !d.trusted
                };
                root.accepted = accepted;
                if (d && !d.trusted) {
                    d.trusted = true;
                    console.info("bluetooth: trusted on the user's yes to", r.method);
                }
            }
            if (r.method === "AuthorizeService")
                BluetoothShared.recordAnswer(r.device, r.uuid, accept);
            if (accept && trust && d)
                d.trusted = true;
            root.pairActivity = Date.now();
            agent.answer(r, accept, extra);
        }
    }

    Timer {
        id: pairDelay

        interval: 300
        onTriggered: {
            const d = root.device(root.pairTarget);
            if (d)
                d.pair();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pairTarget !== ""
        onTriggered: root.checkPairing()
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.accepted).length > 0
        onTriggered: root.settleAccepted("")
    }

    // Counts the scan and the visible window down, and ends them.
    Timer {
        interval: 1000
        repeat: true
        running: root.scanUntil > 0 || root.visibleOn
        onTriggered: {
            root.now = Date.now();
            if (root.scanUntil > 0 && root.now >= root.scanUntil)
                root.stopScan();
            if (root.visibleOn && root.now >= root.visibleUntil)
                root.endVisible();
        }
    }

    Timer {
        id: flashTimer

        interval: 2500
        onTriggered: root.flash = ""
    }

    Timer {
        id: powerTimer

        interval: 5000
        onTriggered: {
            if (root.powerPending) {
                root.powerPending = false;
                BluetoothShared.announce(root.on ? "Bluetooth did not turn off" : "Bluetooth did not turn on", root.on);
            }
        }
    }

    // Node properties (address, profile, codec) arrive once a node is bound.
    // Bluetooth audio nodes exist only while a device's audio or call is set
    // up, so this binds a few at most.
    PwObjectTracker {
        readonly property var bluez: Pipewire.nodes.values.filter(n => n.name.startsWith("bluez_input.") || n.name.startsWith("bluez_output."))

        // Link state is known only for bound links.
        objects: bluez.concat(Pipewire.linkGroups.values.filter(g => bluez.includes(g.source) || bluez.includes(g.target)))
    }

    LockedList {
        id: lockedFile

        area: "bluetooth"
    }

    Connections {
        target: BluetoothShared

        function onToggleRequested(screen) {
            root.toggle(screen);
        }
    }

    IpcHandler {
        target: "bluetooth"

        function toggle(): void {
            root.toggle(Hyprland.focusedMonitor?.name ?? "");
        }
        function power(): void {
            root.power();
        }
    }

    component Mono: Text {
        color: Theme.comment
        font.family: Theme.fontMono
        font.pixelSize: 12
    }

    // A battery outline filled to `percent`, and the figure.
    component Battery: Row {
        property int percent
        readonly property string tier: D.batteryTier(percent)
        readonly property color tone: tier === "low" ? Theme.red : tier === "mid" ? Theme.orange : Theme.green

        spacing: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 10
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: Theme.comment

            Rectangle {
                x: 2
                y: 2
                width: Math.max(2, (parent.width - 4) * parent.parent.percent / 100)
                height: parent.height - 4
                radius: 1
                color: parent.parent.tone
            }

            Rectangle {
                x: parent.width
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 4
                color: Theme.comment
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${parent.percent}%`
            color: parent.tier === "low" ? Theme.red : root.soft
            font.family: Theme.fontMono
            font.pixelSize: 12
        }
    }

    // One device row with its details under it.
    component DeviceRow: Column {
        id: deviceRow

        required property var modelData
        property bool nearbyRow: false
        readonly property var d: modelData
        readonly property string key: d.dbusPath
        readonly property bool selected: root.currentRow?.key === key
        readonly property var sub: root.rowSub(d, nearbyRow)
        readonly property color tone: sub[1] === "up" ? Theme.green : sub[1] === "busy" ? Theme.cyan : sub[1] === "bad" || sub[1] === "arm" ? Theme.red : selected ? root.soft : Theme.comment

        width: parent.width - 12
        spacing: 2

        Rectangle {
            width: parent.width
            height: rowText.implicitHeight + 14
            radius: 6
            color: deviceRow.selected ? Theme.currentLine : "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.select(root.rows.findIndex(r => r.key === deviceRow.key));
                    root.activate();
                }
            }

            Text {
                id: rowIcon

                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                horizontalAlignment: Text.AlignHCenter
                text: D.kind(deviceRow.d.icon).glyph
                color: deviceRow.sub[1] === "dim" ? Theme.comment : deviceRow.sub[1] === "up" || deviceRow.sub[1] === "busy" || deviceRow.sub[1] === "bad" ? deviceRow.tone : Theme.foreground
                font.family: Theme.fontMono
                font.pixelSize: 17
            }

            Column {
                id: rowText

                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.right: roles.visible ? roles.left : battery.visible ? battery.left : parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: deviceRow.d.name
                    color: deviceRow.sub[1] === "dim" ? Theme.comment : Theme.foreground
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: deviceRow.sub[1] === "dim" ? Font.Normal : Font.Medium
                }

                // Wraps: the name is what shortens, never the state.
                Mono {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: deviceRow.sub[0]
                    color: deviceRow.tone
                }
            }

            // What the device does here: green in use now, light connected,
            // dim allowed but not in use. Words are in details.
            Row {
                id: roles

                readonly property var list: root.on && !deviceRow.nearbyRow && deviceRow.d.connected ? root.usesOf(deviceRow.d).roles : []

                visible: list.length > 0
                anchors.right: battery.visible ? battery.left : parent.right
                anchors.rightMargin: battery.visible ? 10 : 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: roles.list

                    Text {
                        required property var modelData

                        text: root.roleGlyph[modelData.id] ?? ""
                        color: root.roleColor(modelData.state)
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                    }
                }
            }

            Battery {
                id: battery

                visible: root.on && deviceRow.d.connected && deviceRow.d.batteryAvailable
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                percent: Math.round(deviceRow.d.battery * 100)
            }
        }

        Item {
            visible: root.expanded === deviceRow.key
            width: parent.width
            height: visible ? detailLines.implicitHeight + 8 : 0

            Rectangle {
                x: 30
                width: 2
                height: detailLines.implicitHeight + 4
                color: Theme.currentLine
            }

            Column {
                id: detailLines

                x: 42
                y: 2
                width: parent.width - 48

                Repeater {
                    model: root.expanded === deviceRow.key ? root.details(deviceRow.d) : []

                    Row {
                        required property var modelData

                        Mono {
                            width: 72
                            text: parent.modelData[0]
                            lineHeight: 1.6
                        }

                        Mono {
                            width: detailLines.width - 72
                            wrapMode: Text.Wrap
                            text: parent.modelData[1]
                            color: root.soft
                            lineHeight: 1.6
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: window

        // Hidden, not closed, while the pairing modal asks something, so the
        // modal has the keyboard and a visible window keeps running.
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
        WlrLayershell.namespace: "desk-bluetooth"
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
                const plain = (event.modifiers & ~Qt.KeypadModifier) === Qt.NoModifier;
                if (root.key(event.key, plain))
                    event.accepted = true;
            }
        }

        DropCard {
            centre: root.open ? Dropdowns.centre("bluetooth", BluetoothShared.screen) : -1
            cardWidth: root.panelWidth
            contentHeight: content.implicitHeight

            Column {
                id: content

                x: 1
                y: 1
                width: parent.width - 2

                // Title, what is going on, and the power switch.
                Item {
                    width: parent.width
                    height: title.implicitHeight

                    SectionHeader {
                        id: title

                        text: "BLUETOOTH"
                    }

                    Row {
                        visible: root.usable
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        spacing: 8

                        Mono {
                            visible: root.busy !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.busy
                            color: Theme.cyan
                            font.pixelSize: 11
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 16
                            radius: 8
                            color: root.on ? Theme.purple : Theme.currentLine

                            Rectangle {
                                x: root.on ? 16 : 2
                                y: 2
                                width: 12
                                height: 12
                                radius: 6
                                color: root.on ? "#191a21" : root.soft

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 150
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.adapter.enabled = !root.adapter.enabled
                            }
                        }
                    }
                }

                Mono {
                    visible: !root.usable
                    width: parent.width
                    wrapMode: Text.Wrap
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 4
                    bottomPadding: 10
                    text: root.blocked ? "Bluetooth is blocked (rfkill)." : "No Bluetooth adapter found."
                }

                Mono {
                    visible: root.visibleOn
                    width: parent.width
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 2
                    bottomPadding: 4
                    wrapMode: Text.Wrap
                    text: `This computer shows as ${root.adapter?.name ?? "this computer"} to devices nearby. Pick it on the other device; nothing pairs without your yes here.`
                    color: Theme.cyan
                }

                SectionHeader {
                    visible: root.usable
                    text: "MY DEVICES"
                }

                Mono {
                    visible: root.usable && root.paired.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    leftPadding: 14
                    rightPadding: 14
                    bottomPadding: 8
                    topPadding: 2
                    text: root.on ? "No devices yet. Press S to look for one." : "Nothing paired."
                }

                Column {
                    visible: root.usable && root.paired.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.usable ? root.paired : []

                        DeviceRow {}
                    }
                }

                SectionHeader {
                    visible: root.on && root.showNearby
                    text: "NEARBY"
                }

                Mono {
                    visible: root.on && root.showNearby && (root.nearby.length === 0 || !root.anyRssi)
                    width: parent.width
                    leftPadding: 14
                    rightPadding: 14
                    bottomPadding: 6
                    topPadding: 2
                    wrapMode: Text.Wrap
                    text: root.nearby.length === 0 ? (root.scanUntil > 0 ? "Looking… put the device in pairing mode." : "Nothing found. Press S to look again.") : "No signal strength reported; sorted by name."
                }

                Column {
                    visible: root.on && root.nearby.length > 0
                    width: parent.width
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 4
                    spacing: 2

                    Repeater {
                        model: root.on ? root.nearby : []

                        DeviceRow {
                            nearbyRow: true
                        }
                    }
                }

                SectionHeader {
                    visible: root.usable && root.lockedPresent && root.locked.length > 0
                    text: "SET IN NIX"
                }

                Column {
                    visible: root.usable && root.lockedPresent && root.locked.length > 0
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
                            readonly property string key: "n" + index

                            width: parent.width - 12
                            height: lockedLabel.implicitHeight + 14
                            radius: 6
                            color: root.currentRow?.key === key ? Theme.currentLine : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.select(root.rows.findIndex(r => r.key === lockedRow.key));
                                    root.activate();
                                }
                            }

                            Text {
                                id: lockedIcon

                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                horizontalAlignment: Text.AlignHCenter
                                text: "\u{f00af}"
                                color: Theme.comment
                                font.family: Theme.fontMono
                                font.pixelSize: 17
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
                    keys: root.hints
                    message: root.flash
                }
            }
        }
    }
}
