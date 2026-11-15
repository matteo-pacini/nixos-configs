pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "devices.js" as D

// What Bar.qml and BluetoothPanel.qml share: where the panel is open, the
// adapter and its devices, signal strengths from the agent, and the
// low-battery notices, which go out whether the panel is open or not.
Singleton {
    id: root

    // Name of the monitor the panel is open on, or "" while it is closed.
    property string screen: ""
    // Device path -> RSSI in dBm, from the agent while BlueZ scans.
    property var rssi: ({})
    // Device path -> the agent's latest "links" event for it.
    property var links: ({})
    // Device path -> { uuid: allowed }, from the service questions answered.
    readonly property var answers: {
        try {
            return JSON.parse(persist.answers);
        } catch (e) {
            return {};
        }
    }

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var devices: adapter ? adapter.devices.values : []
    // Lowest battery among connected devices under 15%, in percent, or -1.
    readonly property int lowest: {
        const low = on ? devices.filter(d => d.connected && d.batteryAvailable && d.battery < 0.15) : [];
        return low.length ? Math.round(Math.min(...low.map(d => d.battery)) * 100) : -1;
    }
    readonly property string batteryKey: devices.map(d => d.address + (d.batteryAvailable ? ":" + Math.round(d.battery * 100) : "")).join(",")

    // Asks BluetoothPanel.qml to open the panel on `screen`, or close it.
    signal toggleRequested(string screen)
    // A line for the OSD pill (Osd.qml), such as "Bluetooth on".
    signal announce(string text)

    function recordAnswer(device: string, uuid: string, allowed: bool): void {
        const all = Object.assign({}, answers);
        all[device] = Object.assign({}, all[device] ?? {});
        all[device][uuid] = allowed;
        persist.answers = JSON.stringify(all);
    }

    function forgetAnswers(device: string): void {
        const all = Object.assign({}, answers);
        delete all[device];
        persist.answers = JSON.stringify(all);
    }

    function checkBatteries(): void {
        const result = D.lowBattery(devices, persist.notified.split(",").filter(a => a !== ""));
        persist.notified = result.notified.join(",");
        for (const n of result.send)
            Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", "Bluetooth", "0", n.icon || "bluetooth", n.name, `Battery at ${n.percent}%`, "[]", "{'urgency': <byte 2>}", "int32 -1"]);
    }

    onBatteryKeyChanged: checkBatteries()

    PersistentProperties {
        id: persist

        reloadableId: "bluetooth-battery"

        // Addresses already notified about while under 15%, comma-separated.
        property string notified: ""
        // `answers` as JSON. Kept across reloads, not restarts: BlueZ keeps
        // no record of them, and a trusted device is never asked.
        property string answers: "{}"
    }
}
