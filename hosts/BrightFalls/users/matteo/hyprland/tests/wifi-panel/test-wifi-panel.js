// The Network panel's Wi-Fi library (quickshell/network/wifi.js) against
// invented networks in fixtures/networks.json and Quickshell's enum names in
// fixtures/enums.js; those names, and Network.qml's copies of them, against
// the installed Quickshell's type file.
// Run: node test-wifi-panel.js <directory holding wifi.js>
//        <Quickshell/Networking/quickshell-network.qmltypes> <Network.qml>
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const W = require(path.join(path.resolve(process.argv[2]), "wifi.js"));
const ENUMS = require("./fixtures/enums.js");
const QMLTYPES = fs.readFileSync(process.argv[3], "utf8");
const NETWORK_QML = fs.readFileSync(process.argv[4], "utf8");
let n = 0;
const t = (name, f) => {
    try {
        f();
    } catch (e) {
        console.error(`not ok: ${name}`);
        throw e;
    }
    n++;
};

const NETS = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "networks.json"), "utf8"));
const net = (name, changes) => Object.assign({}, NETS.find(r => r.name === name), changes || {});
const CTX = { connectivity: "Full", wiredRoute: true };
const LIST = W.section({ device: true, hardware: true, radio: true, answered: true, rows: NETS });
const OFF = W.section({ device: true, hardware: true, radio: false, answered: false, rows: [] });
const ops = r => r.effects.map(e => e.do);
const press = (m, key, row, sec) => W.step(m, { type: "key", key, row: row === undefined ? null : row, section: sec || LIST });
// Runs events from the first state; returns every result.
const run = (events, m) => {
    const out = [];
    let s = m || W.initial();
    for (const e of events) {
        const r = W.step(s, e);
        out.push(r);
        s = r.state;
    }
    return out;
};
const last = rs => rs[rs.length - 1];
const view = (rows, m, prev, ctx) => W.list(rows, m || W.initial(), prev || null, ctx || CTX);

// An enum's names in value order, from the type file's component for
// qs::network::<type>. The values are implicit there, so this relies on
// enums.hpp numbering each enum from 0 without gaps (true in 0.3.2).
const installed = type => {
    const block = QMLTYPES.split("Component {").find(b => b.includes(`name: "qs::network::${type}"`));
    assert.ok(block, `${type} is not in the type file`);
    return JSON.parse(`[${block.match(/values: \[([^\]]*)\]/)[1]}]`);
};

t("enums.js equals the installed Quickshell's enums", () => {
    for (const type of Object.keys(ENUMS))
        assert.deepEqual(ENUMS[type], installed(type), type);
});

t("Network.qml's name arrays equal the installed Quickshell's enums", () => {
    const names = {
        securityNames: "WifiSecurityType",
        stateNames: "ConnectionState",
        failNames: "ConnectionFailReason",
        connectivityNames: "NetworkConnectivity"
    };
    for (const [prop, type] of Object.entries(names)) {
        const m = NETWORK_QML.match(new RegExp(`readonly property var ${prop}: (\\[.*\\])`));
        assert.ok(m, `${prop} not found in Network.qml`);
        assert.deepEqual(JSON.parse(m[1]), installed(type), prop);
    }
});

t("section: each state, header word and line", () => {
    const s = w => W.section(Object.assign({ device: true, hardware: true, radio: true, answered: true, rows: NETS }, w));
    assert.deepEqual(s({ device: false }), { state: "no-device", word: "", line: "No Wi-Fi device." });
    assert.deepEqual(s({ hardware: false }), { state: "hardware-off", word: "off", line: "Blocked by a hardware switch." });
    assert.deepEqual(s({ radio: false }), { state: "radio-off", word: "off", line: "Radio off. W turns it on." });
    assert.deepEqual(s({ answered: false, rows: [] }), { state: "scanning", word: "scanning", line: "Looking for networks…" });
    assert.deepEqual(s({ answered: false }), { state: "list", word: "scanning", line: "" });
    assert.deepEqual(s({}), { state: "list", word: "on", line: "" });
    assert.deepEqual(s({ rows: [] }), { state: "empty", word: "on", line: "No networks found." });
    // The device's absence wins over everything else.
    assert.equal(s({ device: false, hardware: false, radio: false }).state, "no-device");
    assert.equal(s({ hardware: false, radio: true }).state, "hardware-off");
});

t("security: every WifiSecurityType name in the pinned enum is known", () => {
    assert.deepEqual(Object.keys(W.SECURITY).sort(), ENUMS.WifiSecurityType.slice().sort());
});

t("security words, saved, joinable, greyed", () => {
    const want = {
        WpaPsk: ["WPA password", true],
        Wpa2Psk: ["WPA2 password", true],
        Sae: ["WPA3 password", true],
        Open: ["open", true],
        Owe: ["open, encrypted", true],
        WpaEap: ["enterprise: not supported", false],
        Wpa2Eap: ["enterprise: not supported", false],
        Wpa3SuiteB192: ["enterprise: not supported", false],
        StaticWep: ["WEP: not supported", false],
        DynamicWep: ["WEP: not supported", false],
        Leap: ["LEAP: not supported", false],
        Unknown: ["security unknown: not supported", false]
    };
    for (const sec of ENUMS.WifiSecurityType) {
        const v = view([net("Harbour Loft", { security: sec, known: false })]).rows[0];
        assert.deepEqual([v.line, v.joinable, v.dim, v.lineTone], [want[sec][0], want[sec][1], !want[sec][1], want[sec][1] ? "" : "dim"], sec);
    }
    assert.equal(view([net("Harbour Loft")]).rows[0].line, "WPA2 password · saved");
    // A saved network of a type the panel cannot set up joins from its profile.
    const saved = view([net("Northgate Staff", { known: true })]).rows[0];
    assert.deepEqual([saved.line, saved.joinable, saved.dim], ["enterprise · saved", true, false]);
    assert.equal(W.securityWords(net("Northgate Staff", { known: true, security: "StaticWep" })), "WEP");
});

t("signal tiers at 25, 50 and 75 %", () => {
    const cases = [[0, 1], [0.24, 1], [0.25, 2], [0.49, 2], [0.5, 3], [0.74, 3], [0.75, 4], [1, 4]];
    for (const [s, want] of cases)
        assert.equal(W.tier(s), want, String(s));
    assert.equal(view([net("Fernhill 5G")]).rows[0].tier, 2);
});

t("rows: right-hand state, details flag, the portal line", () => {
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    let v = view([c]).rows[0];
    assert.deepEqual([v.state, v.stateTone, v.portal, v.expanded], ["connected", "green", "", false]);
    v = view([c], Object.assign(W.initial(), { expanded: "Harbour Loft" })).rows[0];
    assert.equal(v.expanded, true);
    // Details only on a connected row.
    assert.equal(view([net("Harbour Loft")], Object.assign(W.initial(), { expanded: "Harbour Loft" })).rows[0].expanded, false);
    // Connecting on its own (autoconnect) shows joining too.
    v = view([net("Fernhill 5G", { state: "Connecting", stateChanging: true })]).rows[0];
    assert.deepEqual([v.state, v.stateTone], ["joining…", "cyan"]);
    // The portal belongs to whichever link carries the traffic.
    assert.equal(view([c], null, null, { connectivity: "Portal", wiredRoute: false }).rows[0].portal, "connected · this network wants a sign-in page");
    assert.equal(view([c], null, null, { connectivity: "Portal", wiredRoute: true }).rows[0].portal, "");
    for (const k of ENUMS.NetworkConnectivity.filter(k => k !== "Portal"))
        assert.equal(view([c], null, null, { connectivity: k, wiredRoute: false }).rows[0].portal, "", k);
    assert.equal(view([net("Harbour Loft")], null, null, { connectivity: "Portal", wiredRoute: false }).rows[0].portal, "");
});

t("awkward names are keys as they are", () => {
    const names = view(NETS).names;
    assert.ok(names.includes("Larkspur: Flat 2"));
    assert.ok(names.includes("Tea Room ☕"));
    assert.ok(names.includes("orchard") && names.includes("Orchard"));
    assert.equal(Buffer.byteLength("Upstairs Extender 32 Chars Long!"), 32);
    assert.equal(new Set(names).size, NETS.length);
});

const SORTED = ["Harbour Loft", "Fernhill 5G", "Cafe Meridian Guest", "Northgate Staff", "Tea Room ☕", "Upstairs Extender 32 Chars Long!", "Orchard", "orchard", "printer-setup-7F", "Larkspur: Flat 2"];

t("order: connected, saved, then signal, ties by name", () => {
    assert.deepEqual(view(NETS).names, SORTED);
    const rows = NETS.map(r => r.name === "printer-setup-7F" ? Object.assign({}, r, { connected: true, known: true }) : r);
    assert.deepEqual(view(rows).names.slice(0, 3), ["printer-setup-7F", "Harbour Loft", "Fernhill 5G"]);
    // Stable: the input order does not matter.
    assert.deepEqual(view(NETS.slice().reverse()).names, SORTED);
});

t("order: frozen while the modal is open or a join is in flight", () => {
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    assert.equal(opened.phase, "modal");
    const before = view(NETS, opened).names;
    // A scan: signals change, one network goes, one arrives.
    const after = NETS.filter(r => r.name !== "Tea Room ☕").map(r => Object.assign({}, r, { signal: 1 - r.signal })).concat([{ name: "Quayside", signal: 0.9, security: "Open", known: false, connected: false, state: "Disconnected", stateChanging: false }]);
    const frozen = view(after, opened, before);
    assert.deepEqual(frozen.names, before.filter(x => x !== "Tea Room ☕").concat(["Quayside"]));
    const joining = W.step(opened, { type: "submit", row: net("printer-setup-7F") }).state;
    assert.equal(joining.phase, "joining");
    assert.deepEqual(view(after, joining, before).names, frozen.names);
    // Idle again: sorted.
    const idle = view(after, W.initial(), before).names;
    assert.deepEqual(idle.slice(0, 4), ["Fernhill 5G", "Harbour Loft", "Larkspur: Flat 2", "Quayside"]);
    assert.notDeepEqual(idle, frozen.names);
});

t("state key: changes only with what is drawn", () => {
    const a = view(NETS).key;
    assert.equal(view(NETS.map(r => Object.assign({}, r, { signal: r.signal + 0.01 }))).key, a);
    assert.notEqual(view(NETS.map(r => r.name === "Harbour Loft" ? Object.assign({}, r, { signal: 0.1 }) : r)).key, a);
    assert.notEqual(view(NETS.map(r => r.name === "printer-setup-7F" ? Object.assign({}, r, { known: true }) : r)).key, a);
    assert.notEqual(view(NETS, Object.assign(W.initial(), { armed: "Harbour Loft" })).key, a);
});

t("Enter: modal for an unknown password network, at once for open and saved", () => {
    let r = press(W.initial(), "Enter", net("printer-setup-7F"));
    assert.deepEqual(r.effects, [{ do: "openModal", name: "printer-setup-7F", title: "Wi-Fi password", detail: "printer-setup-7F · WPA2 password", error: "", hint: "8 to 63 characters" }]);
    assert.deepEqual(r.state.target, { name: "printer-setup-7F", security: "Wpa2Psk", wasKnown: false, tried: false });
    r = press(W.initial(), "Enter", net("Fernhill 5G", { known: false }));
    assert.equal(r.effects[0].hint, "");
    for (const name of ["Cafe Meridian Guest", "Tea Room ☕", "Harbour Loft", "Fernhill 5G"]) {
        r = press(W.initial(), "Enter", net(name));
        assert.deepEqual(r.effects, [{ do: "connect", name }, { do: "watchdog", run: true }], name);
        assert.equal(r.state.phase, "joining");
    }
    // C on a saved network joins the same way; on an unknown one nothing.
    assert.deepEqual(ops(press(W.initial(), "C", net("Harbour Loft"))), ["connect", "watchdog"]);
    r = press(W.initial(), "C", net("printer-setup-7F"));
    assert.deepEqual([r.effects, r.state.phase, r.handled], [[], "idle", true]);
});

t("Enter on an unsupported network says why; a saved one joins", () => {
    const say = sec => press(W.initial(), "Enter", net("Northgate Staff", { security: sec })).effects;
    assert.deepEqual(say("Wpa2Eap"), [{ do: "say", text: "enterprise (802.1X) networks cannot be set up from here" }]);
    assert.deepEqual(say("StaticWep"), [{ do: "say", text: "WEP networks cannot be set up from here" }]);
    assert.deepEqual(say("Leap"), [{ do: "say", text: "LEAP networks cannot be set up from here" }]);
    assert.deepEqual(say("Unknown"), [{ do: "say", text: "this network's security is unknown; it cannot be set up from here" }]);
    assert.deepEqual(ops(press(W.initial(), "Enter", net("Northgate Staff", { known: true }))), ["connect", "watchdog"]);
});

t("Enter on a connected network toggles details; C disconnects", () => {
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    let r = press(W.initial(), "Enter", c);
    assert.deepEqual([r.state.expanded, r.effects], ["Harbour Loft", []]);
    r = press(r.state, "Enter", c);
    assert.equal(r.state.expanded, null);
    r = press(Object.assign(W.initial(), { expanded: "Harbour Loft" }), "C", c);
    assert.deepEqual([r.effects, r.state.expanded], [[{ do: "disconnect", name: "Harbour Loft" }], null]);
});

t("a join already satisfied settles at once", () => {
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    // Joined in the background while the modal was up.
    const r = W.step(opened, { type: "submit", row: net("printer-setup-7F", { connected: true, known: true }) });
    assert.deepEqual([r.state.phase, r.state.target, r.effects], ["idle", null, [{ do: "closeModal" }]]);
});

t("submit: close the modal, connectWithPsk, watchdog", () => {
    const rs = run([
        { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
        { type: "submit", row: net("printer-setup-7F") },
        { type: "connected", name: "printer-setup-7F" }
    ]);
    assert.deepEqual(rs[1].effects, [{ do: "closeModal" }, { do: "connectWithPsk", name: "printer-setup-7F" }, { do: "watchdog", run: true }]);
    assert.equal(rs[1].state.target.tried, true);
    assert.deepEqual([last(rs).state.phase, last(rs).effects], ["idle", [{ do: "watchdog", run: false }]]);
    // Submit with the network gone.
    const g = run([
        { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
        { type: "submit", row: null }
    ]);
    assert.deepEqual(last(g).effects, [{ do: "closeModal" }, { do: "say", text: "could not join: network went out of range" }]);
    // A submit with no modal does nothing.
    assert.deepEqual(W.step(W.initial(), { type: "submit", row: net("printer-setup-7F") }).effects, []);
});

t("wrong password: NoSecrets or WifiAuthTimeout reopens the modal, empty, with the line", () => {
    for (const reason of ["NoSecrets", "WifiAuthTimeout"]) {
        const rs = run([
            { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
            { type: "submit", row: net("printer-setup-7F") },
            { type: "failed", name: "printer-setup-7F", reason, security: "Wpa2Psk" }
        ]);
        assert.equal(last(rs).state.phase, "modal");
        assert.deepEqual(last(rs).effects, [{ do: "watchdog", run: false }, { do: "openModal", name: "printer-setup-7F", title: "Wi-Fi password", detail: "printer-setup-7F · WPA2 password", error: "Not joined. The password was wrong, or the network refused it.", hint: "8 to 63 characters" }]);
    }
    // A saved network failing that way also gets the modal.
    const rs = run([
        { type: "key", key: "Enter", row: net("Fernhill 5G"), section: LIST },
        { type: "failed", name: "Fernhill 5G", reason: "WifiAuthTimeout", security: "Sae" }
    ]);
    assert.equal(last(rs).state.phase, "modal");
    assert.equal(last(rs).effects[1].error, "Not joined. The password was wrong, or the network refused it.");
    assert.equal(last(rs).effects[1].hint, "");
});

t("other failures: a red row line, no modal", () => {
    const lines = {
        WifiNetworkLost: "could not join: network went out of range · Enter retries",
        WifiClientDisconnected: "could not join: the Wi-Fi client disconnected · Enter retries",
        WifiClientFailed: "could not join: the Wi-Fi client failed · Enter retries",
        Unknown: "could not join: no reason given · Enter retries",
        NoSecrets: "could not join: the network asked for credentials · Enter retries",
        WifiAuthTimeout: "could not join: authentication timed out · Enter retries"
    };
    assert.deepEqual(Object.keys(lines).sort(), ENUMS.ConnectionFailReason.slice().sort());
    for (const reason of ENUMS.ConnectionFailReason) {
        // An open network: even NoSecrets is not a password matter.
        const rs = run([
            { type: "key", key: "Enter", row: net("Cafe Meridian Guest"), section: LIST },
            { type: "failed", name: "Cafe Meridian Guest", reason, security: "Open" }
        ]);
        const s = last(rs).state;
        assert.deepEqual([s.phase, s.failed["Cafe Meridian Guest"], last(rs).effects], ["idle", lines[reason], [{ do: "watchdog", run: false }]], reason);
        const v = view([net("Cafe Meridian Guest")], s).rows[0];
        assert.deepEqual([v.line, v.lineTone], [lines[reason], "red"]);
    }
    // A password network out of range: the row, not the modal.
    const rs = run([
        { type: "key", key: "Enter", row: net("Fernhill 5G"), section: LIST },
        { type: "failed", name: "Fernhill 5G", reason: "WifiNetworkLost", security: "Sae" }
    ]);
    assert.equal(last(rs).state.failed["Fernhill 5G"], lines.WifiNetworkLost);
    // A new join clears the line.
    const again = press(last(rs).state, "Enter", net("Fernhill 5G"));
    assert.equal(again.state.failed["Fernhill 5G"], undefined);
});

t("failures of joins the panel did not start change only the row", () => {
    let r = W.step(W.initial(), { type: "failed", name: "Harbour Loft", reason: "NoSecrets", security: "Wpa2Psk" });
    assert.deepEqual([r.state.phase, r.effects], ["idle", []]);
    assert.equal(r.state.failed["Harbour Loft"], "could not join: password refused or missing · Enter retries");
    // While joining another network.
    const joining = press(W.initial(), "Enter", net("Cafe Meridian Guest")).state;
    r = W.step(joining, { type: "failed", name: "Harbour Loft", reason: "WifiAuthTimeout", security: "Wpa2Psk" });
    assert.deepEqual([r.state.phase, r.state.target, r.effects], ["joining", joining.target, []]);
    // While the modal is up for the same network (no join in flight).
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    r = W.step(opened, { type: "failed", name: "printer-setup-7F", reason: "NoSecrets", security: "Wpa2Psk" });
    assert.deepEqual([r.state.phase, r.effects], ["modal", []]);
    // Connected clears a line.
    r = W.step(r.state, { type: "connected", name: "printer-setup-7F" });
    assert.deepEqual([r.state.phase, r.state.failed, r.effects], ["idle", {}, [{ do: "closeModal" }]]);
});

t("watchdog: no answer after 30 s", () => {
    assert.equal(W.WATCHDOG_MS, 30000);
    const joining = press(W.initial(), "Enter", net("Cafe Meridian Guest")).state;
    const r = W.step(joining, { type: "watchdog" });
    assert.deepEqual([r.state.phase, r.state.failed["Cafe Meridian Guest"], r.effects], ["idle", "could not join: no answer after 30 s · Enter retries", []]);
    // Late: ignored.
    assert.deepEqual(W.step(r.state, { type: "watchdog" }).state, r.state);
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    assert.deepEqual(W.step(opened, { type: "watchdog" }).state, opened);
});

t("vanished: a join or modal for it settles; others keep going", () => {
    const joining = press(W.initial(), "Enter", net("Cafe Meridian Guest")).state;
    let r = W.step(joining, { type: "vanished", name: "Cafe Meridian Guest" });
    assert.deepEqual([r.state.phase, r.effects], ["idle", [{ do: "watchdog", run: false }, { do: "say", text: "could not join: network went out of range" }]]);
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    r = W.step(opened, { type: "vanished", name: "printer-setup-7F" });
    assert.deepEqual([r.state.phase, ops(r)], ["idle", ["closeModal", "say"]]);
    r = W.step(joining, { type: "vanished", name: "Tea Room ☕" });
    assert.deepEqual([r.state.phase, r.effects], ["joining", []]);
    // Its armed forget, details and failure line go with it.
    const m = Object.assign(W.initial(), { armed: "Harbour Loft", expanded: "Harbour Loft", failed: { "Harbour Loft": "x" } });
    r = W.step(m, { type: "vanished", name: "Harbour Loft" });
    assert.deepEqual([r.state.armed, r.state.expanded, r.state.failed], [null, null, {}]);
});

t("Esc in the modal: the design's table", () => {
    // First prompt: nothing left behind.
    let rs = run([
        { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
        { type: "cancel" }
    ]);
    assert.deepEqual([last(rs).state.phase, last(rs).effects], ["idle", [{ do: "closeModal" }]]);
    // After a wrong password on a network this join made a profile for.
    rs = run([
        { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
        { type: "submit", row: net("printer-setup-7F") },
        { type: "failed", name: "printer-setup-7F", reason: "NoSecrets", security: "Wpa2Psk" },
        { type: "cancel" }
    ]);
    assert.deepEqual(last(rs).effects, [{ do: "closeModal" }, { do: "forget", name: "printer-setup-7F" }]);
    // Twice wrong, then Esc: still only that profile.
    rs = run([
        { type: "key", key: "Enter", row: net("printer-setup-7F"), section: LIST },
        { type: "submit", row: net("printer-setup-7F") },
        { type: "failed", name: "printer-setup-7F", reason: "NoSecrets", security: "Wpa2Psk" },
        { type: "submit", row: net("printer-setup-7F", { known: true }) },
        { type: "failed", name: "printer-setup-7F", reason: "WifiAuthTimeout", security: "Wpa2Psk" },
        { type: "cancel" }
    ]);
    assert.equal(rs[3].state.target.wasKnown, false);
    assert.deepEqual(last(rs).effects, [{ do: "closeModal" }, { do: "forget", name: "printer-setup-7F" }]);
    // After a wrong password on a network saved before this join: never touched.
    rs = run([
        { type: "key", key: "Enter", row: net("Harbour Loft"), section: LIST },
        { type: "failed", name: "Harbour Loft", reason: "NoSecrets", security: "Wpa2Psk" },
        { type: "submit", row: net("Harbour Loft") },
        { type: "failed", name: "Harbour Loft", reason: "NoSecrets", security: "Wpa2Psk" },
        { type: "cancel" }
    ]);
    assert.deepEqual(last(rs).effects, [{ do: "closeModal" }]);
    assert.ok(!rs.some(r => ops(r).includes("forget")));
    // Cancel with no modal does nothing.
    assert.deepEqual(W.step(W.initial(), { type: "cancel" }).effects, []);
});

t("Esc while joining cancels, with the same cleanup", () => {
    // A network this join is making a profile for.
    let r = press(press(W.initial(), "Enter", net("Cafe Meridian Guest")).state, "Esc");
    assert.deepEqual([r.state.phase, r.effects], ["idle", [{ do: "cancel" }, { do: "watchdog", run: false }, { do: "forget", name: "Cafe Meridian Guest" }]]);
    // A saved one.
    r = press(press(W.initial(), "Enter", net("Harbour Loft")).state, "Esc");
    assert.deepEqual(r.effects, [{ do: "cancel" }, { do: "watchdog", run: false }]);
    // Any other key while joining is held off, and says so.
    const joining = press(W.initial(), "Enter", net("Harbour Loft")).state;
    for (const k of ["W", "F5", "Enter", "C", "F", "S", "Up"]) {
        r = press(joining, k, net("Fernhill 5G"));
        assert.deepEqual([r.state, r.effects, r.handled], [joining, [{ do: "say", text: "joining · Esc cancels" }], true], k);
    }
});

t("radio off or panel closed mid-join: settled, nothing left running", () => {
    for (const type of ["radioOff", "closed"]) {
        const joining = press(W.initial(), "Enter", net("Cafe Meridian Guest")).state;
        let r = W.step(joining, { type });
        assert.deepEqual([r.state.phase, r.state.target, r.effects], ["idle", null, [{ do: "watchdog", run: false }]], type);
        // First prompt open.
        const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
        r = W.step(opened, { type });
        assert.deepEqual([r.state.phase, r.effects], ["idle", [{ do: "closeModal" }]], type);
        // The modal after a wrong password on a new profile: as Esc.
        const failed = run([
            { type: "submit", row: net("printer-setup-7F") },
            { type: "failed", name: "printer-setup-7F", reason: "NoSecrets", security: "Wpa2Psk" },
            { type }
        ], opened);
        assert.deepEqual(last(failed).effects, [{ do: "closeModal" }, { do: "forget", name: "printer-setup-7F" }], type);
        // Idle: nothing to do; lines, arming and details are dropped.
        const m = Object.assign(W.initial(), { armed: "Harbour Loft", expanded: "Harbour Loft", failed: { "Fernhill 5G": "x" } });
        r = W.step(m, { type });
        assert.deepEqual([r.state, r.effects], [W.initial(), []], type);
    }
});

t("password check: WPA and WPA2 lengths and hex, WPA3 any", () => {
    for (const sec of ["WpaPsk", "Wpa2Psk"]) {
        const ok = s => W.passwordCheck(sec, s);
        assert.deepEqual(ok("a".repeat(7)), { ok: false, hint: "8 to 63 characters" });
        assert.equal(ok("a".repeat(8)).ok, true);
        assert.equal(ok("a".repeat(63)).ok, true);
        assert.equal(ok("g".repeat(64)).ok, false);
        assert.equal(ok("0123456789abcdefABCDEF".repeat(3).slice(0, 64)).ok, true);
        assert.equal(ok("a".repeat(65)).ok, false);
        assert.equal(ok("").ok, false);
        // NetworkManager counts bytes: 4 two-byte letters are 8.
        assert.equal(ok("éééé").ok, true);
        assert.equal(ok("ééé").ok, false);
        assert.equal(ok("é".repeat(32)).ok, false);
    }
    assert.deepEqual(W.passwordCheck("Sae", ""), { ok: false, hint: "" });
    assert.deepEqual(W.passwordCheck("Sae", "x"), { ok: true, hint: "" });
    assert.equal(W.passwordCheck("Sae", "a".repeat(200)).ok, true);
    for (const sec of ["Open", "Owe", "Wpa2Eap", "StaticWep", "Unknown"])
        assert.equal(W.passwordCheck(sec, "a".repeat(12)).ok, false, sec);
});

t("the password never reaches a state or an effect", () => {
    const SECRET = "sentinel-Pa55phrase-do-not-store";
    const seen = [];
    const record = r => {
        seen.push(JSON.stringify(r));
        return r.state;
    };
    let m = record(press(W.initial(), "Enter", net("printer-setup-7F")));
    // The QML checks the field's text, then submits without it.
    const check = W.passwordCheck("Wpa2Psk", SECRET);
    seen.push(JSON.stringify(check));
    assert.equal(check.ok, true);
    m = record(W.step(m, { type: "submit", row: net("printer-setup-7F") }));
    m = record(W.step(m, { type: "failed", name: "printer-setup-7F", reason: "NoSecrets", security: "Wpa2Psk" }));
    m = record(W.step(m, { type: "submit", row: net("printer-setup-7F", { known: true }) }));
    m = record(W.step(m, { type: "connected", name: "printer-setup-7F" }));
    seen.push(view(NETS, m).key);
    seen.push(JSON.stringify(W.hints(m, LIST, net("printer-setup-7F"), { moves: true, speedTest: true })));
    assert.ok(seen.every(s => !s.includes(SECRET)));
    assert.ok(seen.some(s => s.includes("connectWithPsk")));
});

t("forget: F arms, F again forgets, Esc or moving off disarms", () => {
    const h = net("Harbour Loft");
    let r = press(W.initial(), "F", h);
    assert.deepEqual([r.state.armed, r.effects], ["Harbour Loft", []]);
    let v = view(NETS, r.state).rows[0];
    assert.deepEqual([v.line, v.lineTone], ["press F again to forget · Esc keeps it", "red"]);
    const armed = r.state;
    r = press(armed, "F", h);
    assert.deepEqual([r.state.armed, r.effects], [null, [{ do: "forget", name: "Harbour Loft" }]]);
    r = press(armed, "Esc");
    assert.deepEqual([r.state.armed, r.effects, r.handled], [null, [], true]);
    r = W.step(armed, { type: "select", name: "Fernhill 5G" });
    assert.equal(r.state.armed, null);
    r = W.step(armed, { type: "select", name: "Harbour Loft" });
    assert.equal(r.state.armed, "Harbour Loft");
    r = W.step(armed, { type: "select", name: null });
    assert.equal(r.state.armed, null);
    // F on another saved row moves the arming; Enter disarms and joins.
    assert.equal(press(armed, "F", net("Fernhill 5G")).state.armed, "Fernhill 5G");
    r = press(armed, "Enter", h);
    assert.deepEqual([r.state.armed, ops(r)], [null, ["connect", "watchdog"]]);
    // Not offered on an unsaved row.
    r = press(W.initial(), "F", net("printer-setup-7F"));
    assert.deepEqual([r.state.armed, r.effects], [null, []]);
    // Forgetting a connected row closes its details.
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    r = press(press(Object.assign(W.initial(), { expanded: "Harbour Loft" }), "F", c).state, "F", c);
    assert.deepEqual([r.state.expanded, ops(r)], [null, ["forget"]]);
});

t("forget: a held F arms once and never forgets", () => {
    const h = net("Harbour Loft");
    const held = (m, key, row) => W.step(m, { type: "key", key, row, section: LIST, repeat: true });
    let r = press(W.initial(), "F", h);
    const armed = r.state;
    for (let i = 0; i < 3; i++) {
        r = held(r.state, "F", h);
        assert.deepEqual([r.state, r.effects, r.handled], [armed, [], true]);
    }
    // Only a second press forgets.
    assert.deepEqual(press(r.state, "F", h).effects, [{ do: "forget", name: "Harbour Loft" }]);
});

t("a held key's repeats: Wi-Fi's keys do nothing, the panel's stay the panel's", () => {
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    const held = (m, key, row, sec) => W.step(m, { type: "key", key, row: row === undefined ? null : row, section: sec || LIST, repeat: true });
    const cases = [
        [W.initial(), "W", null, OFF],
        [W.initial(), "F5", null, LIST],
        [W.initial(), "Enter", net("Harbour Loft")],
        [W.initial(), "C", net("Harbour Loft")],
        [W.initial(), "C", c],
        [W.initial(), "Enter", c],
        [Object.assign(W.initial(), { expanded: "Harbour Loft" }), "Esc", c],
        [Object.assign(W.initial(), { armed: "Harbour Loft" }), "Esc", c],
        [press(W.initial(), "Enter", net("Harbour Loft")).state, "Esc", null],
        // Esc and Enter that would fall to the panel (close, wired details).
        [W.initial(), "Esc", null],
        [W.initial(), "Enter", null]
    ];
    for (const [m, key, row, sec] of cases) {
        const r = held(m, key, row, sec);
        assert.deepEqual([r.state, r.effects, r.handled], [m, [], true], key);
    }
    for (const k of ["S", "Up", "Down", "other"])
        assert.equal(held(W.initial(), k, net("Harbour Loft")).handled, false, k);
});

t("W: radio on and off, with no row selected; refused without a device or with the switch off", () => {
    assert.deepEqual(press(W.initial(), "W", null, OFF).effects, [{ do: "radio", on: true }]);
    assert.deepEqual(press(W.initial(), "W", null, LIST).effects, [{ do: "radio", on: false }]);
    const scanning = W.section({ device: true, hardware: true, radio: true, answered: false, rows: [] });
    assert.deepEqual(press(W.initial(), "W", null, scanning).effects, [{ do: "radio", on: false }]);
    const none = W.section({ device: false, hardware: true, radio: true, answered: true, rows: [] });
    assert.deepEqual(press(W.initial(), "W", null, none).effects, [{ do: "say", text: "No Wi-Fi device." }]);
    const hw = W.section({ device: true, hardware: false, radio: true, answered: true, rows: [] });
    assert.deepEqual(press(W.initial(), "W", null, hw).effects, [{ do: "say", text: "Blocked by a hardware switch." }]);
});

t("F5 rescans while the radio is on; other keys are the panel's", () => {
    assert.deepEqual(press(W.initial(), "F5", null, LIST).effects, [{ do: "rescan" }]);
    assert.deepEqual(press(W.initial(), "F5", null, OFF).effects, [{ do: "say", text: "Radio off. W turns it on." }]);
    for (const k of ["S", "Up", "Down"]) {
        const r = press(W.initial(), k, net("Harbour Loft"));
        assert.deepEqual([r.effects, r.handled], [[], false], k);
    }
    // Enter, C and F with a wired or Nix row selected.
    for (const k of ["Enter", "C", "F"])
        assert.equal(press(W.initial(), k, null).handled, false, k);
    // Esc with nothing of Wi-Fi's open: the panel's.
    assert.equal(press(W.initial(), "Esc").handled, false);
    // Esc closes Wi-Fi details first.
    const r = press(Object.assign(W.initial(), { expanded: "Harbour Loft" }), "Esc");
    assert.deepEqual([r.state.expanded, r.handled], [null, true]);
    // While the modal is up the panel's keys do nothing.
    const opened = press(W.initial(), "Enter", net("printer-setup-7F")).state;
    assert.deepEqual(press(opened, "W", null).effects, []);
    // Unknown events are not handled.
    assert.equal(W.step(W.initial(), { type: "nonsense" }).handled, false);
});

t("hints: per selection and state, only keys that work", () => {
    const ctx = { moves: true, speedTest: true };
    const h = (m, sec, row, c) => W.hints(m, sec, row, c || ctx);
    // A saved network, not joined.
    assert.deepEqual(h(W.initial(), LIST, net("Harbour Loft")), [["↑↓", "select"], ["Enter", "join"], ["C", "connect"], ["F", "forget"], ["W", "radio off"], ["F5", "scan"], ["S", "speed test"], ["Esc", "close"]]);
    assert.deepEqual(h(W.initial(), LIST, net("printer-setup-7F")), [["↑↓", "select"], ["Enter", "join"], ["W", "radio off"], ["F5", "scan"], ["S", "speed test"], ["Esc", "close"]]);
    assert.deepEqual(h(W.initial(), LIST, net("Northgate Staff")), [["↑↓", "select"], ["W", "radio off"], ["F5", "scan"], ["S", "speed test"], ["Esc", "close"]]);
    // Radio off, a wired row selected.
    assert.deepEqual(h(W.initial(), OFF, null, { moves: true, speedTest: true, rowKeys: [], esc: "close" }), [["↑↓", "select"], ["W", "radio on"], ["S", "speed test"], ["Esc", "close"]]);
    // A wired row with its own keys, details open.
    assert.deepEqual(h(W.initial(), OFF, null, { moves: false, speedTest: false, rowKeys: [["Enter", "close details"]], esc: "back" }), [["Enter", "close details"], ["W", "radio on"], ["Esc", "back"]]);
    // Connected, details open.
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    const open = Object.assign(W.initial(), { expanded: "Harbour Loft" });
    assert.deepEqual(h(open, LIST, c), [["↑↓", "select"], ["Enter", "close details"], ["C", "disconnect"], ["F", "forget"], ["W", "radio off"], ["F5", "scan"], ["S", "speed test"], ["Esc", "back"]]);
    assert.deepEqual(h(W.initial(), LIST, c)[1], ["Enter", "details"]);
    const joining = press(W.initial(), "Enter", net("Cafe Meridian Guest")).state;
    assert.deepEqual(h(joining, LIST, net("Cafe Meridian Guest")), [["Esc", "cancel"]]);
    assert.deepEqual(h(Object.assign(W.initial(), { armed: "Harbour Loft" }), LIST, c), [["F", "forget"], ["Esc", "keep"]]);
    // No device or switch off: no W, no F5.
    const none = W.section({ device: false, hardware: true, radio: true, answered: true, rows: [] });
    const hw = W.section({ device: true, hardware: false, radio: true, answered: true, rows: [] });
    for (const sec of [none, hw])
        assert.deepEqual(h(W.initial(), sec, null, { moves: true, speedTest: true }), [["↑↓", "select"], ["S", "speed test"], ["Esc", "close"]]);
});

t("hints: Esc says what Esc does, whichever row is selected", () => {
    const esc = (m, row, panelEsc) => W.hints(m, LIST, row, { moves: true, speedTest: true, rowKeys: [], esc: panelEsc }).slice(-1)[0];
    const c = net("Harbour Loft", { connected: true, state: "Connected" });
    const open = Object.assign(W.initial(), { expanded: "Harbour Loft" });
    // Wired details open, a Wi-Fi row selected: Esc closes the wired details.
    assert.deepEqual(esc(W.initial(), net("Fernhill 5G"), "back"), ["Esc", "back"]);
    // Wi-Fi details open, a wired row selected: Esc closes the Wi-Fi details.
    assert.deepEqual(esc(open, null, "close"), ["Esc", "back"]);
    // Wi-Fi details open, another Wi-Fi row selected: the same.
    assert.deepEqual(esc(open, net("Fernhill 5G"), "close"), ["Esc", "back"]);
    assert.deepEqual(esc(open, c, "close"), ["Esc", "back"]);
    // Nothing open anywhere.
    assert.deepEqual(esc(W.initial(), c, "close"), ["Esc", "close"]);
    assert.deepEqual(esc(W.initial(), null, "close"), ["Esc", "close"]);
    // The expanded row disconnected or gone: its details went, Esc closes.
    for (const type of ["disconnected", "vanished"]) {
        const r = W.step(open, { type, name: "Harbour Loft" });
        assert.equal(r.state.expanded, null, type);
        assert.deepEqual(esc(r.state, net("Harbour Loft"), "close"), ["Esc", "close"], type);
        assert.equal(press(r.state, "Esc", null).handled, false, type);
    }
    // Another network disconnecting leaves the details open.
    assert.equal(W.step(open, { type: "disconnected", name: "Fernhill 5G" }).state.expanded, "Harbour Loft");
});

t("details of the connected row", () => {
    const c = net("Harbour Loft", { connected: true, state: "Connected", signal: 0.78 });
    const info = { address: "192.0.2.10/24", gateway: "192.0.2.1", dns: "192.0.2.53", mac: "02:00:00:00:00:01", wiredRoute: true };
    assert.deepEqual(W.details(c, info), [
        { label: "address", value: "192.0.2.10/24", tone: "" },
        { label: "gateway", value: "192.0.2.1", tone: "" },
        { label: "dns", value: "192.0.2.53", tone: "" },
        { label: "mac", value: "02:00:00:00:00:01", tone: "" },
        { label: "security", value: "WPA2 password", tone: "" },
        { label: "signal", value: "78 %", tone: "" },
        { label: "route", value: "wired carries the traffic", tone: "" },
        { label: "link", value: "no link rate: the module does not give one", tone: "dim" }
    ]);
    const bare = W.details(c, { address: "", gateway: "", dns: "", mac: "", wiredRoute: false });
    assert.deepEqual(bare.map(d => d.label), ["security", "signal", "link"]);
});

t("bar: every combination", () => {
    for (const wired of [false, true])
        for (const wifi of [false, true])
            for (const radio of [false, true])
                for (const offline of [false, true]) {
                    const b = W.bar({ wired, wifi: wifi && radio, signal: 0.3, radio, offline });
                    const glyph = wired ? "ethernet" : wifi && radio ? "wifi" : "noNetwork";
                    assert.deepEqual(b, { glyph, tier: glyph === "wifi" ? 2 : 0, mark: radio && glyph !== "wifi", red: offline }, JSON.stringify({ wired, wifi, radio, offline }));
                }
    // Wired up, radio off.
    assert.deepEqual(W.bar({ wired: true, wifi: false, signal: 0, radio: false, offline: false }), { glyph: "ethernet", tier: 0, mark: false, red: false });
    // Wi-Fi only, every tier.
    assert.deepEqual([0.1, 0.3, 0.6, 0.9].map(s => W.bar({ wired: false, wifi: true, signal: s, radio: true, offline: false }).tier), [1, 2, 3, 4]);
});

console.log(`ok: ${n} tests`);
