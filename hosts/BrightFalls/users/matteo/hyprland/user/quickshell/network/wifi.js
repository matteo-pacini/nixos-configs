// The Wi-Fi section's decisions for the Network panel: the section's state,
// the rows, their order, the join state machine, the password check, forget
// arming, keys, footer hints, the details lines and the bar's look. Plain
// JavaScript so node can run it too. No effects: the QML performs what step()
// returns.
//
// Everything here works on plain values. The QML converts Quickshell's
// objects before calling: a network becomes a row
//   { name, signal, security, known, connected, state, stateChanging }
// with `signal` 0..1, `security` the WifiSecurityType name ("Wpa2Psk", ...)
// and `state` the ConnectionState name ("Connecting", ...); a failure reason
// is the ConnectionFailReason name. A row's identity is its name: the module
// groups access points by SSID.
//
// No password ever enters this file except as passwordCheck()'s argument,
// which it does not keep. The machine only learns that one was submitted.

const WATCHDOG_MS = 30000;

const TEXT = {
    noDevice: "No Wi-Fi device.",
    hardwareOff: "Blocked by a hardware switch.",
    radioOff: "Radio off. W turns it on.",
    scanning: "Looking for networks…",
    empty: "No networks found.",
    wrongPassword: "Not joined. The password was wrong, or the network refused it.",
    outOfRange: "could not join: network went out of range · Enter retries",
    noAnswer: "could not join: no answer after 30 s · Enter retries",
    armed: "press F again to forget · Esc keeps it",
    portal: "connected · this network wants a sign-in page",
    busy: "joining · Esc cancels",
    vanished: "could not join: network went out of range",
    pskHint: "8 to 63 characters"
};

// Every WifiSecurityType name. `join`: "password" (connectWithPsk accepts
// it), "open" (connect() with no secret), or the footer line saying why the
// panel cannot set it up. `kind`: the words for a saved network of a type
// the panel cannot set up, which connect() still joins from its profile.
const SECURITY = {
    WpaPsk: { words: "WPA password", join: "password" },
    Wpa2Psk: { words: "WPA2 password", join: "password" },
    Sae: { words: "WPA3 password", join: "password" },
    Open: { words: "open", join: "open" },
    // Enhanced Open: no password, but the link is encrypted.
    Owe: { words: "open, encrypted", join: "open" },
    WpaEap: { words: "enterprise: not supported", kind: "enterprise", join: "enterprise (802.1X) networks cannot be set up from here" },
    Wpa2Eap: { words: "enterprise: not supported", kind: "enterprise", join: "enterprise (802.1X) networks cannot be set up from here" },
    Wpa3SuiteB192: { words: "enterprise: not supported", kind: "enterprise", join: "enterprise (802.1X) networks cannot be set up from here" },
    StaticWep: { words: "WEP: not supported", kind: "WEP", join: "WEP networks cannot be set up from here" },
    DynamicWep: { words: "WEP: not supported", kind: "WEP", join: "WEP networks cannot be set up from here" },
    Leap: { words: "LEAP: not supported", kind: "LEAP", join: "LEAP networks cannot be set up from here" },
    Unknown: { words: "security unknown: not supported", kind: "security unknown", join: "this network's security is unknown; it cannot be set up from here" }
};

const FAIL = {
    NoSecrets: "the network asked for credentials",
    WifiClientDisconnected: "the Wi-Fi client disconnected",
    WifiClientFailed: "the Wi-Fi client failed",
    WifiAuthTimeout: "authentication timed out",
    Unknown: "no reason given"
};

function security(name) {
    return SECURITY[name] || SECURITY.Unknown;
}

function isPassword(name) {
    return security(name).join === "password";
}

// A network the panel can act on: one it can set up, or one with a saved
// profile that connect() activates whatever its type.
function joinable(row) {
    const j = security(row.security).join;
    return j === "password" || j === "open" || row.known;
}

// Signal tier 1..4 for a signal of 0..1, with steps at 0.25, 0.5 and 0.75.
function tier(signal) {
    return signal >= 0.75 ? 4 : signal >= 0.5 ? 3 : signal >= 0.25 ? 2 : 1;
}

// The security in words, as the row's second line and the details show it.
// A saved network of an unsupported type is joinable from its profile, so
// it is not called "not supported".
function securityWords(row) {
    const s = security(row.security);
    return row.known && s.kind ? s.kind : s.words;
}

// The section's state from
//   { device, hardware, radio, answered, rows }
// (a Wi-Fi device exists; wifiHardwareEnabled; wifiEnabled; a scan has
// answered since the radio came on or the panel opened; the rows).
// Returns { state, word, line }: state "no-device" | "hardware-off" |
// "radio-off" | "scanning" (nothing yet) | "empty" | "list"; word the
// header's right-hand word ("" | "off" | "on" | "scanning"); line the text
// drawn in place of the rows, "" when rows are drawn.
function section(w) {
    if (!w.device)
        return { state: "no-device", word: "", line: TEXT.noDevice };
    if (!w.hardware)
        return { state: "hardware-off", word: "off", line: TEXT.hardwareOff };
    if (!w.radio)
        return { state: "radio-off", word: "off", line: TEXT.radioOff };
    const word = w.answered ? "on" : "scanning";
    if (w.rows.length)
        return { state: "list", word, line: "" };
    return w.answered ? { state: "empty", word, line: TEXT.empty } : { state: "scanning", word, line: TEXT.scanning };
}

function radioOn(sec) {
    return ["scanning", "empty", "list"].includes(sec.state);
}

function compare(a, b) {
    if (a.connected !== b.connected)
        return a.connected ? -1 : 1;
    if (a.known !== b.known)
        return a.known ? -1 : 1;
    if (a.signal !== b.signal)
        return b.signal - a.signal;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
}

// The names of `rows` in drawn order: connected, then saved, then by
// signal, ties by name. With `frozen`, the names in `previous` that are
// still present keep their order and new ones follow in sorted order, so
// nothing moves under the user.
function arrange(rows, previous, frozen) {
    const sorted = rows.slice().sort(compare).map(r => r.name);
    if (!frozen)
        return sorted;
    const kept = (previous || []).filter(n => sorted.includes(n));
    return kept.concat(sorted.filter(n => !kept.includes(n)));
}

// The rows as the view draws them, in order, and a key over all of it.
//   rows: plain rows; m: the machine's state; previous: the last result's
//   `names` (or null); ctx: { connectivity, wiredRoute } (the
//   NetworkConnectivity name; whether the default route is wired).
// Returns { names, rows: [view], key }; view:
//   { name, tier, line, lineTone: "" | "red" | "dim", portal: "" | text
//     (an orange line under it), state: "" | "connected" | "joining…",
//     stateTone: "" | "green" | "cyan", dim, joinable, expanded }
// The order is frozen while the modal is open or a join is in flight.
// `key` changes only when something drawn changes: rebuild on it.
function list(rows, m, previous, ctx) {
    const names = arrange(rows, previous, m.phase !== "idle");
    const views = names.map(name => {
        const r = rows.find(x => x.name === name);
        let line = securityWords(r) + (r.known ? " · saved" : "");
        let lineTone = "";
        if (m.armed === name) {
            line = TEXT.armed;
            lineTone = "red";
        } else if (m.failed[name]) {
            line = m.failed[name];
            lineTone = "red";
        } else if (!joinable(r)) {
            lineTone = "dim";
        }
        const joining = (m.phase === "joining" && m.target.name === name) || (!r.connected && r.state === "Connecting");
        return {
            name,
            tier: tier(r.signal),
            line,
            lineTone,
            // Connectivity is the host's, not this link's: with wired
            // carrying the traffic, a portal is not this network's.
            portal: r.connected && ctx.connectivity === "Portal" && !ctx.wiredRoute ? TEXT.portal : "",
            state: r.connected ? "connected" : joining ? "joining…" : "",
            stateTone: r.connected ? "green" : joining ? "cyan" : "",
            dim: !joinable(r) && !r.connected,
            joinable: joinable(r),
            expanded: r.connected && m.expanded === name
        };
    });
    return { names, rows: views, key: JSON.stringify(views) };
}

// Whether the modal's Enter may submit `text` for a network of security
// `sec` (a WifiSecurityType name), and the hint line under the field.
// WPA and WPA2: 8 to 63 bytes, as NetworkManager counts them, or exactly
// 64 hex digits; WPA3 (Sae): at least one character, no hint. Any other
// type takes no password. Returns { ok, hint }; keeps nothing.
function passwordCheck(sec, text) {
    if (sec === "Sae")
        return { ok: text.length > 0, hint: "" };
    if (sec !== "WpaPsk" && sec !== "Wpa2Psk")
        return { ok: false, hint: "" };
    const bytes = utf8Length(text);
    const ok = (bytes >= 8 && bytes <= 63) || /^[0-9a-fA-F]{64}$/.test(text);
    return { ok, hint: TEXT.pskHint };
}

function utf8Length(s) {
    let n = 0;
    for (const ch of s) {
        const c = ch.codePointAt(0);
        n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4;
    }
    return n;
}

// The machine's first state. Fields: phase "idle" | "modal" | "joining";
// target null | { name, security, wasKnown, tried } (wasKnown: the network
// had a profile when Enter started this join; tried: a join call was made);
// failed { name: line }; armed: name | null (forget armed); expanded:
// name | null (details open).
function initial() {
    return { phase: "idle", target: null, failed: {}, armed: null, expanded: null };
}

function withState(m, changes) {
    return Object.assign({}, m, changes);
}

function withFailed(m, name, line) {
    const failed = Object.assign({}, m.failed);
    if (line)
        failed[name] = line;
    else
        delete failed[name];
    return failed;
}

function modalEffect(t, error) {
    return { do: "openModal", name: t.name, title: "Wi-Fi password", detail: `${t.name} · ${security(t.security).words}`, error, hint: passwordCheck(t.security, "").hint };
}

// Leaving a join without success: a profile this join made is forgotten,
// a profile that was there before is never touched.
function cleanup(t) {
    return t.tried && !t.wasKnown ? [{ do: "forget", name: t.name }] : [];
}

function settle(m, changes, effects) {
    return { state: withState(m, Object.assign({ phase: "idle", target: null }, changes)), effects, handled: true };
}

function begin(m, row) {
    const failed = withFailed(m, row.name, "");
    if (row.connected)
        return settle(m, { failed, armed: null }, []);
    const target = { name: row.name, security: row.security, wasKnown: row.known, tried: true };
    if (!row.known && isPassword(row.security)) {
        target.tried = false;
        return { state: withState(m, { phase: "modal", target, failed, armed: null }), effects: [modalEffect(target, "")], handled: true };
    }
    return {
        state: withState(m, { phase: "joining", target, failed, armed: null }),
        effects: [{ do: "connect", name: row.name }, { do: "watchdog", run: true }],
        handled: true
    };
}

function failLine(reason, password) {
    if (reason === "WifiNetworkLost")
        return TEXT.outOfRange;
    if (password && (reason === "NoSecrets" || reason === "WifiAuthTimeout"))
        return "could not join: password refused or missing · Enter retries";
    return `could not join: ${FAIL[reason] || FAIL.Unknown} · Enter retries`;
}

function key(m, e) {
    const none = { state: m, effects: [], handled: true };
    const say = text => ({ state: m, effects: [{ do: "say", text }], handled: true });
    if (e.repeat && ["W", "F5", "Esc", "Enter", "C", "F"].includes(e.key))
        return none;
    if (m.phase === "joining") {
        if (e.key !== "Esc")
            return say(TEXT.busy);
        return settle(m, {}, [{ do: "cancel" }, { do: "watchdog", run: false }].concat(cleanup(m.target)));
    }
    if (m.phase === "modal")
        return none;
    const sec = e.section;
    if (e.key === "W") {
        if (sec.state === "no-device")
            return say(TEXT.noDevice);
        if (sec.state === "hardware-off")
            return say(TEXT.hardwareOff);
        return { state: m, effects: [{ do: "radio", on: !radioOn(sec) }], handled: true };
    }
    if (e.key === "F5") {
        if (!radioOn(sec))
            return say(sec.line);
        return { state: m, effects: [{ do: "rescan" }], handled: true };
    }
    if (e.key === "Esc") {
        if (m.armed)
            return { state: withState(m, { armed: null }), effects: [], handled: true };
        if (m.expanded)
            return { state: withState(m, { expanded: null }), effects: [], handled: true };
        return { state: m, effects: [], handled: false };
    }
    const row = e.row;
    if (!row || !["Enter", "C", "F"].includes(e.key))
        return { state: m, effects: [], handled: false };
    if (e.key === "F") {
        if (!row.known)
            return none;
        if (m.armed !== row.name)
            return { state: withState(m, { armed: row.name }), effects: [], handled: true };
        return {
            state: withState(m, { armed: null, expanded: m.expanded === row.name ? null : m.expanded, failed: withFailed(m, row.name, "") }),
            effects: [{ do: "forget", name: row.name }],
            handled: true
        };
    }
    const disarmed = withState(m, { armed: null });
    if (row.connected) {
        if (e.key === "C")
            return { state: withState(disarmed, { expanded: null }), effects: [{ do: "disconnect", name: row.name }], handled: true };
        return { state: withState(disarmed, { expanded: m.expanded === row.name ? null : row.name }), effects: [], handled: true };
    }
    if (e.key === "C" && !row.known)
        return none;
    if (!joinable(row))
        return { state: disarmed, effects: [{ do: "say", text: security(row.security).join }], handled: true };
    return begin(disarmed, row);
}

// The reducer: step(state, event) -> { state, effects, handled }.
// Events:
//   { type: "key", key, row, section, repeat }  key "W" | "F5" | "Enter" |
//       "C" | "F" | "Esc" | any other; row the selected Wi-Fi row (plain) or
//       null when a wired or Nix row or nothing is selected; section as
//       section() returns; repeat true for a held key's auto-repeat, which
//       none of these keys acts on (handled, so the panel's Esc and Enter do
//       not act on it either). handled false: the key is not Wi-Fi's, the
//       panel's own handling applies (Esc: wired details, then close).
//   { type: "select", name }            the selection moved (name or null)
//   { type: "submit", row }             the modal's Enter, after
//       passwordCheck() allowed it; row the network as it is now, or null
//       if it is gone
//   { type: "cancel" }                  the modal's Esc
//   { type: "failed", name, reason, security }  connectionFailed: the
//       reason's name and the network's WifiSecurityType name
//   { type: "connected", name }         a network became connected
//   { type: "vanished", name }          a network left the list
//   { type: "watchdog" }                the watchdog fired
//   { type: "radioOff" }                wifiEnabled became false
//   { type: "closed" }                  the panel closed
// Effects, in order, for the QML to perform (looking the network up by
// name at that moment):
//   { do: "connect", name }             network.connect()
//   { do: "connectWithPsk", name }      network.connectWithPsk(field text),
//                                       then clear the field
//   { do: "disconnect", name }          network.disconnect()
//   { do: "cancel" }                    the Wi-Fi device's disconnect()
//   { do: "forget", name }              network.forget()
//   { do: "openModal", name, title, detail, error, hint }  open or reopen,
//                                       field empty and masked
//   { do: "closeModal" }                close it, clear the field
//   { do: "watchdog", run }             start (WATCHDOG_MS) or stop it
//   { do: "radio", on }                 Networking.wifiEnabled = on
//   { do: "rescan" }                    scannerEnabled off, then on
//   { do: "say", text }                 a footer line
function step(m, e) {
    const t = m.target;
    const ours = name => t && t.name === name;
    switch (e.type) {
    case "key":
        return key(m, e);
    case "select":
        return { state: m.armed && m.armed !== e.name ? withState(m, { armed: null }) : m, effects: [], handled: true };
    case "submit":
        if (m.phase !== "modal")
            return { state: m, effects: [], handled: true };
        if (!e.row)
            return settle(m, {}, [{ do: "closeModal" }, { do: "say", text: TEXT.vanished }].concat(cleanup(t)));
        if (e.row.connected)
            return settle(m, {}, [{ do: "closeModal" }]);
        return {
            state: withState(m, { phase: "joining", target: Object.assign({}, t, { tried: true }) }),
            effects: [{ do: "closeModal" }, { do: "connectWithPsk", name: t.name }, { do: "watchdog", run: true }],
            handled: true
        };
    case "cancel":
        if (m.phase !== "modal")
            return { state: m, effects: [], handled: true };
        return settle(m, {}, [{ do: "closeModal" }].concat(cleanup(t)));
    case "failed":
        if (m.phase === "joining" && ours(e.name)) {
            if (isPassword(t.security) && (e.reason === "NoSecrets" || e.reason === "WifiAuthTimeout"))
                return { state: withState(m, { phase: "modal" }), effects: [{ do: "watchdog", run: false }, modalEffect(t, TEXT.wrongPassword)], handled: true };
            return settle(m, { failed: withFailed(m, e.name, failLine(e.reason, false)) }, [{ do: "watchdog", run: false }]);
        }
        // A join this panel did not start, or one it no longer waits on.
        return { state: withState(m, { failed: withFailed(m, e.name, failLine(e.reason, isPassword(e.security))) }), effects: [], handled: true };
    case "connected": {
        const failed = withFailed(m, e.name, "");
        if (m.phase === "joining" && ours(e.name))
            return settle(m, { failed }, [{ do: "watchdog", run: false }]);
        if (m.phase === "modal" && ours(e.name))
            return settle(m, { failed }, [{ do: "closeModal" }]);
        return { state: withState(m, { failed }), effects: [], handled: true };
    }
    case "vanished": {
        const changes = {
            failed: withFailed(m, e.name, ""),
            armed: m.armed === e.name ? null : m.armed,
            expanded: m.expanded === e.name ? null : m.expanded
        };
        // A network with a profile stays in the list, so there is nothing
        // to forget here.
        if (m.phase === "joining" && ours(e.name))
            return settle(m, changes, [{ do: "watchdog", run: false }, { do: "say", text: TEXT.vanished }]);
        if (m.phase === "modal" && ours(e.name))
            return settle(m, changes, [{ do: "closeModal" }, { do: "say", text: TEXT.vanished }]);
        return { state: withState(m, changes), effects: [], handled: true };
    }
    case "watchdog":
        if (m.phase !== "joining")
            return { state: m, effects: [], handled: true };
        return settle(m, { failed: withFailed(m, t.name, TEXT.noAnswer) }, []);
    case "radioOff":
    case "closed": {
        const effects = m.phase === "joining" ? [{ do: "watchdog", run: false }] : m.phase === "modal" ? [{ do: "closeModal" }].concat(cleanup(t)) : [];
        if (e.type === "closed")
            return { state: initial(), effects, handled: true };
        return settle(m, { failed: {}, armed: null, expanded: null }, effects);
    }
    }
    return { state: m, effects: [], handled: false };
}

// The footer's [key, label] pairs, in KeyHints' form, only keys that work
// now. m: the machine; sec: section(); row: the selected Wi-Fi row or null;
// ctx: { moves (↑↓ has somewhere to go), speedTest (S works), rowKeys (the
// selected wired or Nix row's own pairs, when row is null), esc (the
// panel's Esc label when row is null: "close" | "back") }.
function hints(m, sec, row, ctx) {
    if (m.phase === "joining")
        return [["Esc", "cancel"]];
    if (m.armed)
        return [["F", "forget"], ["Esc", "keep"]];
    const out = [];
    if (ctx.moves)
        out.push(["↑↓", "select"]);
    let esc = ctx.esc || "close";
    if (row) {
        esc = m.expanded === row.name && row.connected ? "back" : "close";
        if (row.connected) {
            out.push(["Enter", m.expanded === row.name ? "close details" : "details"]);
            out.push(["C", "disconnect"]);
        } else if (joinable(row)) {
            out.push(["Enter", "join"]);
            if (row.known)
                out.push(["C", "connect"]);
        }
        if (row.known)
            out.push(["F", "forget"]);
    } else {
        for (const k of ctx.rowKeys || [])
            out.push(k);
    }
    if (sec.state !== "no-device" && sec.state !== "hardware-off")
        out.push(["W", radioOn(sec) ? "radio off" : "radio on"]);
    if (radioOn(sec))
        out.push(["F5", "scan"]);
    if (ctx.speedTest)
        out.push(["S", "speed test"]);
    out.push(["Esc", esc]);
    return out;
}

// The connected row's details, [{ label, value, tone }] (tone "" | "dim").
// row: the plain row; info: { address, gateway, dns, mac, wiredRoute } from
// the panel's nmcli read and route table ("" for unknown: that line is left
// out). The module gives no link rate; the last line says so.
function details(row, info) {
    const out = [];
    for (const k of ["address", "gateway", "dns", "mac"]) {
        if (info[k])
            out.push({ label: k, value: info[k], tone: "" });
    }
    out.push({ label: "security", value: securityWords(row), tone: "" });
    out.push({ label: "signal", value: `${Math.round(row.signal * 100)} %`, tone: "" });
    if (info.wiredRoute)
        out.push({ label: "route", value: "wired carries the traffic", tone: "" });
    out.push({ label: "link", value: "no link rate: the module does not give one", tone: "dim" });
    return out;
}

// The bar's network item from { wired, wifi, signal, radio, offline }
// (a wired device connected; a Wi-Fi network connected and its signal 0..1;
// wifiEnabled; today's offline test). Returns { glyph: "ethernet" | "wifi" |
// "noNetwork", tier: 0 | 1..4 (for the wifi glyph), mark (the small Wi-Fi
// mark beside the glyph: the radio is on and the glyph is not wifi), red }.
function bar(b) {
    const glyph = b.wired ? "ethernet" : b.wifi ? "wifi" : "noNetwork";
    return { glyph, tier: glyph === "wifi" ? tier(b.signal) : 0, mark: b.radio && glyph !== "wifi", red: !!b.offline };
}

if (typeof module !== "undefined")
    module.exports = { WATCHDOG_MS, TEXT, SECURITY, tier, securityWords, section, arrange, list, passwordCheck, initial, step, hints, details, bar };
