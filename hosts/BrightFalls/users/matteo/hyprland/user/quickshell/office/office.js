// The office panel's decisions: the state held from desk-mqtt's events, and
// every text, lock and figure the panel and the bar show from it. Plain
// JavaScript so node can run it too. Times are milliseconds since the epoch;
// clock times in texts are local.

// The light's and the blind's slider step, in percent.
const STEP = 10;

// The state before the helper has said anything. `helper` is whether its
// process is running.
function initial(helper) {
    return {
        helper: helper,
        config: null,
        broker: null,
        bridge: null,
        synced: false,
        devices: {},
        // Command id -> { device, action, value, at, state: "sent" | "pending" }.
        commands: {},
        // Device id -> { text, footer } about its last command that did not
        // take effect, until its next report or command.
        notes: {}
    };
}

function copy(st, changes) {
    return Object.assign({}, st, changes);
}

function without(map, key) {
    const out = Object.assign({}, map);
    delete out[key];
    return out;
}

function withEntry(map, key, value) {
    const out = Object.assign({}, map);
    out[key] = value;
    return out;
}

function clock(ms) {
    const d = new Date(ms);
    const two = n => String(n).padStart(2, "0");
    return `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}`;
}

function parseTime(t) {
    if (typeof t !== "string" || t === "")
        return null;
    const ms = Date.parse(t);
    return isNaN(ms) ? null : ms;
}

// The age of a report: { text: "now" | "4m" | "3h" | "2d" | "—", old }, old
// from an hour.
function age(lastSeen, now) {
    const at = parseTime(lastSeen);
    if (at === null)
        return { text: "—", old: false };
    const s = Math.max(0, (now - at) / 1000);
    const text = s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`;
    return { text, old: s >= 3600 };
}

// "under a minute", "3 min", "2 h", "1 d" since `since`.
function span(since, now) {
    const at = parseTime(since);
    if (at === null)
        return "";
    const s = Math.max(0, (now - at) / 1000);
    return s < 60 ? "under a minute" : s < 3600 ? `${Math.floor(s / 60)} min` : s < 86400 ? `${Math.floor(s / 3600)} h` : `${Math.floor(s / 86400)} d`;
}

// Zigbee2MQTT's brightness, 1..254, as a percent 1..100, and back.
function toPercent(raw) {
    return Math.max(1, Math.min(100, Math.round(raw * 100 / 254)));
}

function toRaw(percent) {
    return Math.max(1, Math.min(254, Math.round(percent * 254 / 100)));
}

// `value` moved one step in `direction` (-1 or 1), kept within min..max.
function step(value, direction, min, max) {
    return Math.max(min, Math.min(max, value + direction * STEP));
}

function deviceOf(st, kind) {
    const spec = st.config && st.config.state === "ok" ? st.config.devices.find(d => d.kind === kind) : null;
    return spec ? Object.assign({ id: spec.id, label: spec.label, values: null, last_seen: null, availability: null, definition: null }, st.devices[spec.id] || {}) : null;
}

function socketsOf(st) {
    if (!st.config || st.config.state !== "ok")
        return [];
    return st.config.devices.filter(d => d.kind === "socket").map(spec => Object.assign({ id: spec.id, label: spec.label, values: null, last_seen: null, availability: null }, st.devices[spec.id] || {}));
}

function lightText(action, value) {
    return action === "brightness" ? `${toPercent(value)} %` : action;
}

function blindPositionText(values) {
    if (!values)
        return "not known";
    if (typeof values.position === "number")
        return values.position === 0 ? "Closed" : `Open ${values.position}%`;
    return values.state === "OPEN" ? "Open" : values.state === "CLOSE" ? "Closed" : values.state === "STOP" ? "Stopped" : "not known";
}

const REASONS = {
    "read-only": "the helper is read-only",
    "broker-down": "the MQTT broker is down",
    "bridge-offline": "Zigbee2MQTT is offline",
    "device-offline": "the device is offline",
    "not-configured": "the helper has no config",
    "bad-value": "the value is out of range"
};

function reasonText(reason, kind) {
    if (reason === "type-unconfirmed")
        return `Zigbee2MQTT does not list it as a ${kind}`;
    return REASONS[reason] || `the helper rejected it (${reason})`;
}

// The note for a command that did not take effect.
function failureNote(st, cmd, state, reason) {
    const device = st.devices[cmd.device] || {};
    const values = device.values || {};
    const kind = device.kind || "";
    const label = device.label || cmd.device;
    if (state === "refused") {
        const why = reasonText(reason, kind);
        return { text: `Not sent: ${why}`, footer: `${label}: not sent, ${why}.` };
    }
    if (kind === "light") {
        const asked = lightText(cmd.action, cmd.value);
        const still = values.state === "OFF" ? "off" : typeof values.brightness === "number" ? `${toPercent(values.brightness)} %` : values.state === "ON" ? "on" : "not known";
        return { text: `Not confirmed: asked ${asked} at ${clock(cmd.at)}`, footer: `${label} did not confirm ${asked}; still ${still}.` };
    }
    const what = cmd.action === "open" ? "Did not start opening" : cmd.action === "close" ? "Did not start closing" : cmd.action === "stop" ? "Did not stop" : `Did not move to ${cmd.value}%`;
    return { text: `${what} (asked ${clock(cmd.at)})`, footer: `${label} did not confirm within 5 s; still ${blindPositionText(device.values)}.` };
}

// Records a command written to the helper.
function sent(st, id, device, action, value, now) {
    return copy(st, {
        commands: withEntry(st.commands, id, { device, action, value, at: now, state: "sent" }),
        notes: without(st.notes, device)
    });
}

// The state after one event from the helper.
function apply(st, ev) {
    switch (ev.event) {
    case "config":
        return copy(st, { config: ev });
    case "broker":
        return copy(st, { broker: ev, synced: ev.state === "up" ? st.synced : false });
    case "bridge":
        return copy(st, { bridge: ev });
    case "synced":
        return copy(st, { synced: true });
    case "device":
        return copy(st, { devices: withEntry(st.devices, ev.id, ev), notes: without(st.notes, ev.id) });
    case "command": {
        const cmd = ev.id === null ? null : st.commands[ev.id];
        if (!cmd)
            return st;
        if (ev.state === "pending")
            return copy(st, { commands: withEntry(st.commands, ev.id, Object.assign({}, cmd, { state: "pending" })) });
        const out = copy(st, { commands: without(st.commands, ev.id) });
        if (ev.state === "confirmed")
            return out;
        out.notes = withEntry(st.notes, cmd.device, failureNote(st, cmd, ev.state, ev.reason));
        return out;
    }
    }
    return st;
}

// The latest command still waiting for a device, or null.
function waiting(st, device) {
    const ids = Object.keys(st.commands).map(Number).filter(id => st.commands[id].device === device).sort((a, b) => a - b);
    return ids.length ? st.commands[ids[ids.length - 1]] : null;
}

// The single plain line shown instead of the whole panel, or "".
function single(st) {
    if (!st.helper)
        return "The office helper (desk-mqtt) is not running. Trying again.";
    if (st.config && st.config.state === "missing")
        return "No office MQTT config on this machine.";
    if (st.config && st.config.state === "invalid")
        return `The office MQTT config is not valid (${st.config.error}).`;
    return "";
}

// Whether nothing has ever come from the broker this run.
function neverUp(st) {
    return !st.config || !st.broker || (st.broker.state !== "up" && !st.broker.ever_up);
}

// Values are from before a broker or Zigbee2MQTT loss.
function stale(st) {
    return !neverUp(st) && (st.broker.state !== "up" || !st.bridge || st.bridge.state !== "online");
}

// The banner over the rows: { tone: "err" | "warn" | "", text }.
function banner(st, now) {
    if (single(st) !== "" || !st.config)
        return { tone: "", text: "" };
    const b = st.broker;
    if (!b || b.state === "connecting")
        return { tone: "warn", text: "Connecting to the MQTT broker…" };
    if (b.state !== "up") {
        if (!b.ever_up)
            return { tone: "err", text: b.error ? `The MQTT broker refused the connection (${b.error}). Trying again every 10 s.` : "Can't reach the MQTT broker. Trying again every 10 s." };
        return { tone: "warn", text: `Broker lost ${span(b.since, now)} ago. Values are from before; controls are off until it is back.` };
    }
    if (st.bridge && st.bridge.state === "offline") {
        const d = span(st.bridge.since, now);
        return { tone: "warn", text: `Zigbee2MQTT is offline${d ? ` (${d})` : ""}. Values are from before; controls are off.` };
    }
    return { tone: "", text: "" };
}

// The header's tag: "read only" whenever the helper runs read-only, "live"
// while commands can really be sent, otherwise "".
function liveText(st) {
    if (st.config && st.config.state === "ok" && st.config.read_only)
        return "read only";
    if (neverUp(st) || stale(st) || !st.synced)
        return "";
    return "live";
}

function offline(st, device) {
    return device.availability === "offline" && !stale(st) && !neverUp(st);
}

// Why `device`'s controls are locked, or "" when they work: "broker",
// "bridge", "offline" or "type" (not yet confirmed a device of its kind).
function lockOf(st, device) {
    if (!device || neverUp(st) || st.broker.state !== "up")
        return "broker";
    if (!st.bridge || st.bridge.state !== "online")
        return "bridge";
    if (device.availability === "offline")
        return "offline";
    if (!device.definition || !device.definition.matches)
        return "type";
    return "";
}

// The light's row. `draft` is the percent being dragged or keyed, or null.
// tone: "" | "note" (orange) | "bad" (red) | "dim".
function lightView(st, now, draft) {
    const d = deviceOf(st, "light");
    if (!d)
        return null;
    const v = d.values || {};
    const known = d.values !== null && !neverUp(st);
    const on = v.state === "ON";
    const percent = typeof v.brightness === "number" ? toPercent(v.brightness) : null;
    const cmd = waiting(st, d.id);
    const asked = cmd && cmd.action === "brightness" ? toPercent(cmd.value) : null;
    const handle = draft !== null ? draft : asked !== null ? asked : percent;
    const lock = lockOf(st, d);
    const isOffline = offline(st, d);
    const view = {
        id: d.id,
        label: d.label,
        known,
        on,
        offline: isOffline,
        lit: on && known && lock === "",
        locked: lock !== "",
        dim: lock !== "" || !on,
        percent,
        handle,
        slider: known && percent !== null,
        value: "",
        sub: "",
        tone: "",
        age: neverUp(st) ? { text: "", old: false } : age(d.last_seen, now)
    };
    if (neverUp(st)) {
        view.value = "not known";
        return view;
    }
    if (!known) {
        view.value = "—";
        view.sub = st.synced ? "No report yet" : "Waiting for a report";
        view.tone = "dim";
        return view;
    }
    view.value = percent === null ? "" : handle !== percent && handle !== null ? `${percent} → ${handle} %` : `${percent} %`;
    const note = st.notes[d.id];
    if (isOffline) {
        view.sub = `Offline · was ${on ? "on" : "off"}`;
        view.tone = "bad";
    } else if (draft !== null) {
        view.sub = "Release to send";
    } else if (cmd) {
        view.sub = "Sending…";
    } else if (note) {
        view.sub = note.text;
        view.tone = "note";
    } else {
        view.sub = on ? "On" : "Off";
    }
    return view;
}

// The blind's row. `draft` is the position being dragged or keyed, or null;
// `target` the position last asked for while the blind may still be moving.
function blindView(st, now, draft, target) {
    const d = deviceOf(st, "blind");
    if (!d)
        return null;
    const v = d.values || {};
    const known = d.values !== null && !neverUp(st);
    const lock = lockOf(st, d);
    const exposes = !d.definition || d.definition.properties.includes("position");
    const position = typeof v.position === "number" ? v.position : null;
    const hasPosition = known && exposes && position !== null;
    const moving = v.motor_state === "opening" || v.motor_state === "closing";
    const cmd = waiting(st, d.id);
    const view = {
        id: d.id,
        label: d.label,
        known,
        locked: lock !== "",
        hasPosition,
        position,
        handle: draft !== null ? draft : (cmd || moving) && target !== null ? target : position,
        moving,
        upOff: lock !== "" || (hasPosition && position === 100),
        downOff: lock !== "" || (hasPosition && position === 0),
        stopOff: lock !== "",
        sub: "",
        tone: "",
        age: neverUp(st) ? { text: "", old: false } : age(d.last_seen, now)
    };
    if (neverUp(st)) {
        view.sub = "";
        return view;
    }
    if (!known) {
        view.sub = st.synced ? "No report yet" : "Waiting for a report";
        view.tone = "dim";
        return view;
    }
    const where = v.motor_state === "opening" ? "Opening…" : v.motor_state === "closing" ? "Closing…" : v.motor_state === "blocked" ? "Blocked" : exposes ? blindPositionText(v) : blindPositionText({ state: v.state });
    const note = st.notes[d.id];
    if (offline(st, d)) {
        view.sub = `Offline · was ${where}`;
        view.tone = "bad";
    } else if (draft !== null) {
        view.sub = "Release to send";
    } else if (cmd) {
        view.sub = "Sending…";
    } else if (note) {
        view.sub = note.text;
        view.tone = "note";
    } else {
        view.sub = where;
    }
    return view;
}

// The sockets: { rows, watts, counted, all, text }. Rows sorted by watts,
// then off, then offline and silent ones; `share` is of the largest. A
// socket counts in the total while it is online and has reported.
function socketsView(st, now) {
    const all = socketsOf(st);
    const rows = all.map(d => {
        const v = d.values || {};
        const isOffline = offline(st, d);
        const reported = d.values !== null;
        const power = typeof v.power === "number" ? v.power : null;
        const state = isOffline ? "offline" : !reported ? "silent" : v.state === "OFF" ? "off" : "on";
        return {
            id: d.id,
            label: d.label,
            state,
            power,
            counted: !isOffline && reported,
            share: 0,
            age: age(d.last_seen, now),
            lastSeen: parseTime(d.last_seen)
        };
    });
    const rank = r => r.state === "on" ? 0 : r.state === "off" ? 1 : 2;
    rows.sort((a, b) => rank(a) - rank(b) || (b.power || 0) - (a.power || 0) || a.label.localeCompare(b.label));
    const max = Math.max(0, ...rows.filter(r => r.state === "on").map(r => r.power || 0));
    for (const r of rows)
        r.share = r.state === "on" && max > 0 ? (r.power || 0) / max : 0;
    const counted = rows.filter(r => r.counted);
    const watts = Math.round(counted.reduce((sum, r) => sum + (r.state === "on" ? r.power || 0 : 0), 0));
    let text;
    if (neverUp(st))
        text = "";
    else if (stale(st))
        text = `${span(st.broker.state !== "up" ? st.broker.since : st.bridge && st.bridge.since, now) || "some time"} ago`;
    else if (counted.length < rows.length)
        text = `${counted.length} of ${rows.length} sockets`;
    else {
        const oldest = Math.min(...counted.map(r => r.lastSeen === null ? now : r.lastSeen));
        text = `${rows.length} sockets, ${age(new Date(oldest).toISOString(), now).text}`;
    }
    return { rows, watts, counted: counted.length, all: rows.length, text };
}

// The bar item: { glyph: "on" | "off" | "none", watts: "184 W" | "— W", dim }.
function barView(st, now) {
    if (single(st) !== "" || neverUp(st))
        return { glyph: "none", watts: "— W", dim: true };
    const light = lightView(st, now, null);
    const sockets = socketsView(st, now);
    const isStale = stale(st);
    return {
        glyph: light && light.on && light.known && !isStale && !offline(st, deviceOf(st, "light")) ? "on" : "off",
        watts: sockets.counted > 0 ? `${sockets.watts} W` : "— W",
        dim: isStale
    };
}

// Why a light or blind control did nothing, for the footer: "" when it works.
function lockText(st, kind) {
    const d = deviceOf(st, kind);
    const lock = lockOf(st, d);
    if (lock === "broker")
        return "The MQTT broker is not connected.";
    if (lock === "bridge")
        return "Zigbee2MQTT is offline.";
    if (lock === "offline")
        return `${d.label} is offline.`;
    if (lock === "type")
        return `Zigbee2MQTT does not list ${d.label} as a ${kind} yet.`;
    return "";
}

if (typeof module !== "undefined")
    module.exports = { STEP, initial, apply, sent, age, span, toPercent, toRaw, step, single, banner, liveText, neverUp, stale, lockOf, lockText, lightView, blindView, socketsView, barView, reasonText };
