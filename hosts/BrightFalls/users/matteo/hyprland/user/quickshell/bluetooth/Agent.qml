import QtQuick
import Quickshell
import Quickshell.Io

// BlueZ's default pairing agent for this session: runs `desk-bt-agent`
// (bt-agent.py in nixos-configs, which describes the protocol) for as long as
// the shell runs, and starts it again if it exits. Requests wait in
// `requests` until answer() is called; nothing is ever answered here on the
// user's behalf.
Scope {
    id: root

    // Open requests, oldest first: the agent's request events, with id null
    // for DisplayPasskey and DisplayPinCode.
    property var requests: []
    property bool ready: false

    // The agent registered; BlueZ has just made the adapter pairable.
    signal registered

    // `extra` carries the passkey or pin that RequestPasskey and
    // RequestPinCode answer with.
    function answer(request: var, accept: bool, extra: var): void {
        requests = requests.filter(r => r !== request);
        if (request.id === null)
            return;
        proc.write(JSON.stringify(Object.assign({
            id: request.id,
            accept
        }, extra ?? {})) + "\n");
    }

    function hasRequestFor(device: string): bool {
        return requests.some(r => r.device === device);
    }

    // One line from the agent.
    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            console.warn("bluetooth agent:", line);
            return;
        }
        if (ev.event === "request") {
            // A newer passkey display for the same device replaces the
            // older one; `entered` counts the keys typed so far.
            requests = requests.filter(r => !(r.id === null && ev.id === null && r.device === ev.device)).concat([ev]);
        } else if (ev.event === "cancel") {
            requests = requests.filter(r => r.id !== null && !ev.ids.includes(r.id));
        } else if (ev.event === "links") {
            const links = Object.assign({}, BluetoothShared.links);
            links[ev.device] = ev;
            BluetoothShared.links = links;
        } else if (ev.event === "rssi") {
            const rssi = Object.assign({}, BluetoothShared.rssi);
            rssi[ev.device] = ev.rssi;
            BluetoothShared.rssi = rssi;
        } else if (ev.event === "ready") {
            ready = true;
            restart.interval = 2000;
            registered();
        } else if (ev.event !== "exit") {
            console.info("bluetooth agent:", line);
        }
    }

    // Display requests end when the device they are about stops pairing.
    function dropDisplays(device: string): void {
        requests = requests.filter(r => !(r.id === null && r.device === device));
    }

    Process {
        id: proc

        command: ["desk-bt-agent"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("bluetooth agent:", line)
        }
        onExited: code => console.warn("bluetooth agent exited with", code)
        // Also the only signal when it fails to start (no binary).
        onRunningChanged: {
            if (running)
                return;
            root.ready = false;
            root.requests = [];
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }
}
