pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "office.js" as O

// What Bar.qml and Office.qml share: where the panel is open, and the office
// devices as `desk-mqtt` reports them (desk-mqtt.py in nixos-configs
// describes the protocol). The helper runs for as long as the shell does and
// is started again if it exits; `office` is office.js's state, rebuilt from
// its events.
Singleton {
    id: root

    // Starts the helper with --read-only: it then refuses every command and
    // publishes nothing.
    readonly property bool readOnly: false

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    property var office: O.initial(true)
    property int nextId: 1

    // Asks Office.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
    // A command for `device` did not take effect; `text` says so for the
    // footer.
    signal failed(string device, string text)

    // Writes one command to the helper. `value` is null for actions without
    // one. Returns false when the helper is not running.
    function send(device: string, action: string, value: var): bool {
        if (!proc.running)
            return false;
        const id = nextId++;
        const cmd = {
            id,
            device,
            action
        };
        if (value !== null)
            cmd.value = value;
        office = O.sent(office, id, device, action, value, Date.now());
        console.info("office helper: send", id, device, action, value ?? "");
        proc.write(JSON.stringify(cmd) + "\n");
        return true;
    }

    // One line from the helper.
    function handle(line: string): void {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            console.warn("office helper:", line);
            return;
        }
        const before = office.notes;
        office = O.apply(office, ev);
        for (const id of Object.keys(office.notes))
            if (office.notes[id] !== before[id])
                failed(id, office.notes[id].footer);
        if (ev.event === "command" && ev.state !== "pending")
            console.info("office helper: command", ev.id, ev.state, ev.reason ?? "");
        else if (ev.event === "broker" || ev.event === "bridge" || ev.event === "bad-input")
            console.info("office helper:", ev.event, ev.state ?? "", ev.error ?? "");
        else if (ev.event === "config" && ev.state !== "ok")
            console.warn("office helper: config", ev.state, ev.error);
    }

    Process {
        id: proc

        command: root.readOnly ? ["desk-mqtt", "--read-only"] : ["desk-mqtt"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("office helper:", line)
        }
        onExited: code => console.warn("office helper exited with", code)
        // Also the only signal when it fails to start (no binary).
        onRunningChanged: {
            root.office = O.initial(running);
            if (running)
                return;
            restart.start();
        }
    }

    // 2 s, doubling up to a minute while it keeps failing; back to 2 s once
    // the helper has said its config is good.
    Timer {
        id: restart

        interval: 2000
        onTriggered: {
            proc.running = true;
            interval = Math.min(interval * 2, 60000);
        }
    }

    onOfficeChanged: if (office.config?.state === "ok")
        restart.interval = 2000
}
