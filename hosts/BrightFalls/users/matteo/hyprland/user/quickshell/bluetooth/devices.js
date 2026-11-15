// Device kinds, battery levels and list order for the Bluetooth panel. Plain
// JavaScript so node can run it too.
//
// The kind comes from BlueZ's Device1.Icon, which BlueZ 5.87 derives from the
// device's class or appearance (src/dbus-common.c); a device that reports
// neither has no icon. BlueZ has no name for watches or earbuds, so those
// show as whatever class they report (earbuds as headphones or headset).

// Icon -> [what the row calls it, Nerd Font (Material Design) glyph, audio].
const KINDS = {
    "input-gaming": ["controller", "\u{f0297}", false],
    "input-keyboard": ["keyboard", "\u{f030c}", false],
    "input-mouse": ["mouse", "\u{f037d}", false],
    "input-tablet": ["tablet", "\u{f04f6}", false],
    "audio-headphones": ["headphones", "\u{f02cb}", true],
    "audio-headset": ["headset", "\u{f02ce}", true],
    "audio-card": ["audio device", "\u{f04c3}", true],
    "phone": ["phone", "\u{f011c}", false],
    "computer": ["computer", "\u{f0322}", false],
    "video-display": ["display", "\u{f0379}", false],
    "multimedia-player": ["media player", "\u{f075a}", false],
    "camera-video": ["video camera", "\u{f0567}", false],
    "camera-photo": ["camera", "\u{f0100}", false],
    "printer": ["printer", "\u{f042a}", false],
    "scanner": ["scanner", "\u{f06ab}", false],
    "modem": ["modem", "\u{f0469}", false],
    "network-wireless": ["network access point", "\u{f0469}", false]
};

const BLUETOOTH = "\u{f00af}";

// { label, glyph, audio } for a Device1.Icon value ("" or unknown included).
function kind(icon) {
    const k = KINDS[icon];
    return k ? { label: k[0], glyph: k[1], audio: k[2] } : { label: "kind not reported", glyph: BLUETOOTH, audio: false };
}

// Under 15% red, under 35% orange, else fine; `percent` 0..100.
function batteryTier(percent) {
    return percent < 15 ? "low" : percent < 35 ? "mid" : "ok";
}

// Paired devices: connected first, then by name.
function sortPaired(devices) {
    return devices.slice().sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name));
}

// Nearby devices for the scan list: unpaired, named (a name that is only the
// address counts as none), strongest signal first where `rssi` (path -> dBm)
// has one, then by name.
function nearby(devices, rssi) {
    const named = devices.filter(d => !d.paired && d.name !== "" && d.name.replace(/-/g, ":").toUpperCase() !== d.address.toUpperCase());
    const strength = d => rssi[d.dbusPath] ?? -1000;
    return named.sort((a, b) => (strength(b) - strength(a)) || a.name.localeCompare(b.name));
}

// Which notifications to send, and the new set of addresses already notified,
// for one look at the devices: one notice per device each time its level
// drops under 15%. A device that reports 15% or more leaves the set; one that
// stops reporting (disconnected) stays in it, so reconnecting while still low
// is not a new crossing. Devices no longer listed (forgotten) leave it.
function lowBattery(devices, notified) {
    const present = new Set(devices.map(d => d.address));
    const keep = new Set(notified.filter(a => present.has(a)));
    const send = [];
    for (const d of devices) {
        if (!d.batteryAvailable)
            continue;
        const percent = Math.round(d.battery * 100);
        if (percent < 15 && !keep.has(d.address)) {
            keep.add(d.address);
            send.push({ address: d.address, name: d.name, icon: d.icon, percent });
        } else if (percent >= 15) {
            keep.delete(d.address);
        }
    }
    return { send, notified: Array.from(keep) };
}

if (typeof module !== "undefined")
    module.exports = { KINDS, kind, batteryTier, sortPaired, nearby, lowBattery };
