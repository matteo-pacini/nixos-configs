// The office panel's library (quickshell/office/office.js) against invented
// helper events, inline and as lines hand-written in the helper's format in
// fixtures/ (one file per state of the panel; "@-N" in a time means N
// seconds before the test's now).
// Run: node test-office-panel.js <directory holding office.js>
process.env.TZ = "UTC";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const O = require(path.join(path.resolve(process.argv[2]), "office.js"));
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

const NOW = Date.parse("2026-11-15T18:45:00.000Z");
const ago = s => new Date(NOW - s * 1000).toISOString();
const DEVICES = [
    { id: "lamp", kind: "light", label: "Lamp" },
    { id: "shade", kind: "blind", label: "Shade" },
    { id: "s1", kind: "socket", label: "Socket 1" },
    { id: "s2", kind: "socket", label: "Socket 2" },
    { id: "s3", kind: "socket", label: "Socket 3" }
];
const def = (kind, props) => ({ matches: true, properties: props });
const dev = (id, kind, label, values, extra) => Object.assign({
    event: "device", id, kind, label, values, last_seen: ago(10), received: ago(10), retained: true,
    availability: "online", availability_since: null,
    definition: kind === "light" ? def(kind, ["state", "brightness"]) : kind === "blind" ? def(kind, ["state", "position", "motor_state", "running"]) : def(kind, ["state", "power"])
}, extra || {});

// A live desk: config, broker up, bridge online, every device reported, synced.
function live(overrides) {
    const o = overrides || {};
    let st = O.initial(true);
    const events = [
        { event: "config", state: "ok", read_only: false, devices: DEVICES },
        { event: "broker", state: "up", since: ago(600), ever_up: true },
        { event: "bridge", state: "online", since: null },
        dev("lamp", "light", "Lamp", { state: "ON", brightness: 140 }, o.lamp),
        dev("shade", "blind", "Shade", { state: "OPEN", position: 60, motor_state: "stopped", running: false }, o.shade),
        dev("s1", "socket", "Socket 1", { state: "ON", power: 61 }, o.s1),
        dev("s2", "socket", "Socket 2", { state: "ON", power: 24.4 }, o.s2),
        dev("s3", "socket", "Socket 3", { state: "ON", power: 52 }, o.s3),
        { event: "synced" }
    ];
    for (const ev of events)
        st = O.apply(st, ev);
    return st;
}

t("ages: now, minutes, hours, days, unknown", () => {
    assert.deepEqual(O.age(ago(59), NOW), { text: "now", old: false });
    assert.deepEqual(O.age(ago(60), NOW), { text: "1m", old: false });
    assert.deepEqual(O.age(ago(3599), NOW), { text: "59m", old: false });
    assert.deepEqual(O.age(ago(3600), NOW), { text: "1h", old: true });
    assert.deepEqual(O.age(ago(86400 * 2 + 5), NOW), { text: "2d", old: true });
    assert.deepEqual(O.age(null, NOW), { text: "—", old: false });
    assert.deepEqual(O.age("not a time", NOW), { text: "—", old: false });
    assert.deepEqual(O.age(new Date(NOW + 5000).toISOString(), NOW), { text: "now", old: false });
});

t("brightness: percent and raw round-trip, ends clamp", () => {
    for (let p = 1; p <= 100; p++)
        assert.equal(O.toPercent(O.toRaw(p)), p);
    assert.equal(O.toRaw(100), 254);
    assert.equal(O.toRaw(0), 1);
    assert.equal(O.toPercent(1), 1);
    assert.equal(O.toPercent(254), 100);
    assert.equal(O.toPercent(140), 55);
});

t("steps of 10 within the range", () => {
    assert.equal(O.step(55, 1, 1, 100), 65);
    assert.equal(O.step(95, 1, 1, 100), 100);
    assert.equal(O.step(5, -1, 1, 100), 1);
    assert.equal(O.step(5, -1, 0, 100), 0);
});

t("the live panel: light on, blind open, total of five sockets", () => {
    const st = live();
    assert.equal(O.liveText(st), "live");
    assert.deepEqual(O.banner(st, NOW), { tone: "", text: "" });
    const l = O.lightView(st, NOW, null);
    assert.equal(l.value, "55 %");
    assert.equal(l.sub, "On");
    assert.equal(l.lit, true);
    assert.equal(l.locked, false);
    const b = O.blindView(st, NOW, null, null);
    assert.equal(b.sub, "Open 60%");
    assert.equal(b.hasPosition, true);
    assert.equal(b.upOff || b.downOff || b.stopOff, false);
    const s = O.socketsView(st, NOW);
    assert.deepEqual(s.rows.map(r => r.label), ["Socket 1", "Socket 3", "Socket 2"]);
    assert.equal(s.rows[0].share, 1);
    assert.equal(s.watts, 137);
    assert.equal(s.text, "3 sockets, now");
    assert.deepEqual(O.barView(st, NOW), { glyph: "on", watts: "137 W", dim: false });
});

t("read only replaces live in the header, whatever the broker", () => {
    let st = live();
    st = O.apply(st, { event: "config", state: "ok", read_only: true, devices: DEVICES });
    assert.equal(O.liveText(st), "read only");
    st = O.apply(st, { event: "broker", state: "down", since: ago(30), ever_up: true });
    assert.equal(O.liveText(st), "read only");
    // The controls still work; the helper refuses.
    assert.equal(O.lightView(live(), NOW, null).locked, false);
    let ro = O.apply(O.initial(true), { event: "config", state: "ok", read_only: true, devices: DEVICES });
    assert.equal(O.liveText(ro), "read only");
});

t("light off keeps its last brightness, unlit", () => {
    const st = live({ lamp: { values: { state: "OFF", brightness: 140 } } });
    const l = O.lightView(st, NOW, null);
    assert.equal(l.sub, "Off");
    assert.equal(l.value, "55 %");
    assert.equal(l.lit, false);
    assert.equal(l.dim, true);
    assert.equal(O.barView(st, NOW).glyph, "off");
});

t("dragging: fill confirmed, handle asked, release to send", () => {
    const l = O.lightView(live(), NOW, 70);
    assert.equal(l.percent, 55);
    assert.equal(l.handle, 70);
    assert.equal(l.value, "55 → 70 %");
    assert.equal(l.sub, "Release to send");
});

t("command pending, then confirmed", () => {
    let st = O.sent(live(), 1, "lamp", "brightness", O.toRaw(70), NOW);
    st = O.apply(st, { event: "command", id: 1, state: "pending", device: "lamp", action: "brightness", value: O.toRaw(70), at: ago(0) });
    let l = O.lightView(st, NOW, null);
    assert.equal(l.sub, "Sending…");
    assert.equal(l.handle, 70);
    st = O.apply(st, dev("lamp", "light", "Lamp", { state: "ON", brightness: O.toRaw(70) }, { retained: false }));
    st = O.apply(st, { event: "command", id: 1, state: "confirmed" });
    l = O.lightView(st, NOW, null);
    assert.equal(l.sub, "On");
    assert.equal(l.value, "70 %");
    assert.deepEqual(st.commands, {});
});

t("not confirmed: handle back, note in the row and the footer", () => {
    let st = O.sent(live(), 2, "lamp", "brightness", O.toRaw(70), Date.parse("2026-11-15T18:43:05Z"));
    st = O.apply(st, { event: "command", id: 2, state: "pending" });
    st = O.apply(st, { event: "command", id: 2, state: "not-confirmed" });
    const l = O.lightView(st, NOW, null);
    assert.equal(l.handle, 55);
    assert.equal(l.sub, "Not confirmed: asked 70 % at 18:43:05");
    assert.equal(l.tone, "note");
    assert.equal(st.notes.lamp.footer, "Lamp did not confirm 70 %; still 55 %.");
    // Until the next report.
    st = O.apply(st, dev("lamp", "light", "Lamp", { state: "ON", brightness: 140 }));
    assert.equal(O.lightView(st, NOW, null).sub, "On");
});

t("blind not confirmed says what it did not do", () => {
    let st = live({ shade: { values: { state: "CLOSE", position: 0, motor_state: "stopped", running: false } } });
    st = O.sent(st, 3, "shade", "open", null, Date.parse("2026-11-15T18:43:02Z"));
    st = O.apply(st, { event: "command", id: 3, state: "pending" });
    st = O.apply(st, { event: "command", id: 3, state: "not-confirmed" });
    assert.equal(O.blindView(st, NOW, null, 100).sub, "Did not start opening (asked 18:43:02)");
    assert.equal(st.notes.shade.footer, "Shade did not confirm within 5 s; still Closed.");
});

t("refused: the reason in plain words", () => {
    let st = O.sent(live(), 4, "lamp", "off", null, NOW);
    st = O.apply(st, { event: "command", id: 4, state: "refused", reason: "read-only" });
    assert.equal(O.lightView(st, NOW, null).sub, "Not sent: the helper is read-only");
    assert.equal(st.notes.lamp.footer, "Lamp: not sent, the helper is read-only.");
    assert.equal(O.reasonText("type-unconfirmed", "blind"), "Zigbee2MQTT does not list it as a blind");
    assert.equal(O.reasonText("weird", "light"), "the helper rejected it (weird)");
    // A refusal with no id, or an unknown id, changes nothing.
    assert.equal(O.apply(st, { event: "command", id: null, state: "refused", reason: "bad-input" }), st);
});

t("blind states: closed, moving, fallback without position", () => {
    let b = O.blindView(live({ shade: { values: { state: "CLOSE", position: 0, motor_state: "stopped", running: false } } }), NOW, null, null);
    assert.equal(b.sub, "Closed");
    assert.equal(b.downOff, true);
    assert.equal(b.upOff, false);
    b = O.blindView(live({ shade: { values: { state: "OPEN", position: 100 } } }), NOW, null, null);
    assert.equal(b.upOff, true);
    b = O.blindView(live({ shade: { values: { state: "OPEN", position: 35, motor_state: "opening", running: true } } }), NOW, null, 80);
    assert.equal(b.sub, "Opening…");
    assert.equal(b.handle, 80);
    assert.equal(b.position, 35);
    assert.equal(b.moving, true);
    b = O.blindView(live({ shade: { values: { state: "OPEN" }, definition: { matches: true, properties: ["state"] } } }), NOW, null, null);
    assert.equal(b.hasPosition, false);
    assert.equal(b.sub, "Open");
    assert.equal(b.downOff, false);
});

t("socket off says off and still counts", () => {
    const s = O.socketsView(live({ s2: { values: { state: "OFF", power: 0 } } }), NOW);
    const r = s.rows.find(r => r.id === "s2");
    assert.equal(r.state, "off");
    assert.equal(s.rows[s.rows.length - 1].id, "s2");
    assert.equal(s.counted, 3);
    assert.equal(s.text, "3 sockets, now");
});

t("offline devices: greyed, locked, socket left out of the total", () => {
    const st = live({
        lamp: { availability: "offline" },
        shade: { availability: "offline", last_seen: ago(86400 + 60) },
        s2: { availability: "offline" }
    });
    const l = O.lightView(st, NOW, null);
    assert.equal(l.sub, "Offline · was on");
    assert.equal(l.tone, "bad");
    assert.equal(l.locked, true);
    const b = O.blindView(st, NOW, null, null);
    assert.equal(b.sub, "Offline · was Open 60%");
    assert.deepEqual(b.age, { text: "1d", old: true });
    assert.equal(b.upOff && b.stopOff && b.downOff, true);
    const s = O.socketsView(st, NOW);
    assert.equal(s.watts, 113);
    assert.equal(s.text, "2 of 3 sockets");
    assert.equal(s.rows[s.rows.length - 1].state, "offline");
    assert.equal(O.barView(st, NOW).glyph, "off");
    assert.equal(O.lockText(st, "light"), "Lamp is offline.");
});

t("silent device: no report yet, light on/off still allowed", () => {
    const st = live({ lamp: { values: null, last_seen: null }, s3: { values: null, last_seen: null } });
    const l = O.lightView(st, NOW, null);
    assert.equal(l.sub, "No report yet");
    assert.equal(l.value, "—");
    assert.equal(l.slider, false);
    assert.equal(l.locked, false);
    const s = O.socketsView(st, NOW);
    assert.equal(s.counted, 2);
    assert.equal(s.rows.find(r => r.id === "s3").state, "silent");
});

t("broker never up: one error banner, nothing known, everything locked", () => {
    let st = O.initial(true);
    st = O.apply(st, { event: "config", state: "ok", read_only: false, devices: DEVICES });
    st = O.apply(st, { event: "broker", state: "down", since: ago(30), ever_up: false, last_attempt: ago(1) });
    assert.deepEqual(O.banner(st, NOW), { tone: "err", text: "Can't reach the MQTT broker. Trying again every 10 s." });
    assert.equal(O.lightView(st, NOW, null).value, "not known");
    assert.equal(O.lightView(st, NOW, null).locked, true);
    assert.deepEqual(O.barView(st, NOW), { glyph: "none", watts: "— W", dim: true });
    st = O.apply(st, { event: "broker", state: "down", since: ago(30), ever_up: false, error: "Not authorized" });
    assert.match(O.banner(st, NOW).text, /refused the connection \(Not authorized\)/);
});

t("broker lost: values kept, stale, locked", () => {
    let st = live();
    st = O.apply(st, { event: "broker", state: "down", since: ago(180), ever_up: true });
    assert.deepEqual(O.banner(st, NOW), { tone: "warn", text: "Broker lost 3 min ago. Values are from before; controls are off until it is back." });
    assert.equal(st.synced, false);
    assert.equal(O.liveText(st), "");
    assert.equal(O.lightView(st, NOW, null).locked, true);
    assert.equal(O.lightView(st, NOW, null).lit, false);
    assert.equal(O.socketsView(st, NOW).text, "3 min ago");
    assert.deepEqual(O.barView(st, NOW), { glyph: "off", watts: "137 W", dim: true });
});

t("Zigbee2MQTT offline: banner with or without a start, availability ignored", () => {
    let st = live({ lamp: { availability: "offline" } });
    st = O.apply(st, { event: "bridge", state: "offline", since: ago(360) });
    assert.equal(O.banner(st, NOW).text, "Zigbee2MQTT is offline (6 min). Values are from before; controls are off.");
    assert.equal(O.lightView(st, NOW, null).sub, "On");
    assert.equal(O.lockOf(st, { availability: "online", definition: { matches: true } }), "bridge");
    st = O.apply(st, { event: "bridge", state: "offline", since: null });
    assert.equal(O.banner(st, NOW).text, "Zigbee2MQTT is offline. Values are from before; controls are off.");
});

t("an unconfirmed device kind locks its controls", () => {
    const st = live({ lamp: { definition: { matches: false, properties: [] } } });
    assert.equal(O.lightView(st, NOW, null).locked, true);
    assert.equal(O.lockText(st, "light"), "Zigbee2MQTT does not list Lamp as a light yet.");
});

t("config missing or invalid, helper not running: one plain line", () => {
    let st = O.apply(O.initial(true), { event: "config", state: "missing", error: "no config file" });
    assert.equal(O.single(st), "No office MQTT config on this machine.");
    st = O.apply(O.initial(true), { event: "config", state: "invalid", error: "topics.s1" });
    assert.equal(O.single(st), "The office MQTT config is not valid (topics.s1).");
    assert.deepEqual(O.banner(st, NOW), { tone: "", text: "" });
    assert.equal(O.single(O.initial(false)), "The office helper (desk-mqtt) is not running. Trying again.");
    assert.equal(O.single(live()), "");
});

// The state after a fixture's lines, fed in order as the helper would.
function fixture(name) {
    const text = fs.readFileSync(path.join(__dirname, "fixtures", name + ".jsonl"), "utf8");
    let st = O.initial(true);
    for (const line of text.split("\n").filter(l => l.trim() !== ""))
        st = O.apply(st, JSON.parse(line.replace(/"@-(\d+)"/g, (m, s) => JSON.stringify(ago(Number(s))))));
    return st;
}

t("fixture: light off, blind closed, a socket off", () => {
    const st = fixture("01-off-closed-socketoff");
    assert.equal(O.lightView(st, NOW, null).sub, "Off");
    const b = O.blindView(st, NOW, null, null);
    assert.equal(b.sub, "Closed");
    assert.equal(b.downOff, true);
    const s = O.socketsView(st, NOW);
    assert.equal(s.rows[s.rows.length - 1].state, "off");
    assert.equal(s.watts, 175);
    assert.equal(O.barView(st, NOW).glyph, "off");
});

t("fixture: moving towards a target", () => {
    const b = O.blindView(fixture("02-moving"), NOW, null, 80);
    assert.equal(b.sub, "Opening…");
    assert.equal(b.position, 35);
    assert.equal(b.handle, 80);
});

t("fixture: offline light, blind and socket", () => {
    const st = fixture("03-offline");
    assert.equal(O.lightView(st, NOW, null).sub, "Offline · was on");
    assert.equal(O.lightView(st, NOW, null).offline, true);
    assert.equal(O.blindView(st, NOW, null, null).age.text, "1d");
    assert.equal(O.socketsView(st, NOW).text, "4 of 5 sockets");
    assert.equal(O.socketsView(st, NOW).watts, 175);
});

t("fixture: old values and silent devices", () => {
    const st = fixture("04-old-silent");
    assert.equal(O.lightView(st, NOW, null).sub, "No report yet");
    assert.deepEqual(O.blindView(st, NOW, null, null).age, { text: "3h", old: true });
    const s = O.socketsView(st, NOW);
    assert.deepEqual(s.rows.map(r => r.state), ["on", "on", "on", "offline", "silent"]);
    assert.equal(s.rows[3].age.text, "2d");
});

t("fixture: blind without position", () => {
    const b = O.blindView(fixture("05-fallback"), NOW, null, null);
    assert.equal(b.hasPosition, false);
    assert.equal(b.sub, "Open");
});

t("fixture: broker never up", () => {
    const st = fixture("06-never-up");
    assert.equal(O.banner(st, NOW).tone, "err");
    assert.equal(O.lightView(st, NOW, null).value, "not known");
    assert.equal(O.barView(st, NOW).watts, "— W");
});

t("fixture: broker lost and Zigbee2MQTT offline", () => {
    let st = fixture("07-broker-lost");
    assert.equal(O.banner(st, NOW).text, "Broker lost 3 min ago. Values are from before; controls are off until it is back.");
    assert.equal(O.socketsView(st, NOW).text, "3 min ago");
    st = fixture("08-bridge-offline");
    assert.equal(O.banner(st, NOW).text, "Zigbee2MQTT is offline (6 min). Values are from before; controls are off.");
    assert.equal(O.blindView(st, NOW, null, null).locked, true);
});

t("fixture: live, then the command paths", () => {
    let st = fixture("09-live");
    assert.equal(O.liveText(st), "live");
    st = O.sent(st, 1, "light", "brightness", 178, NOW);
    st = O.apply(st, { event: "command", id: 1, state: "pending" });
    assert.equal(O.lightView(st, NOW, null).sub, "Sending…");
    st = O.apply(st, { event: "command", id: 1, state: "not-confirmed" });
    assert.equal(st.notes.light.footer, "Light did not confirm 70 %; still 55 %.");
    st = fixture("10-blind-closed");
    st = O.sent(st, 2, "blind", "open", null, NOW);
    st = O.apply(st, { event: "command", id: 2, state: "not-confirmed" });
    assert.equal(st.notes.blind.footer, "Blind did not confirm within 5 s; still Closed.");
});

t("fixture: config missing or invalid", () => {
    assert.equal(O.single(fixture("11-config-missing")), "No office MQTT config on this machine.");
    assert.equal(O.single(fixture("12-config-invalid")), "The office MQTT config is not valid (topics.desk1).");
});

t("connecting: a warning until the broker answers", () => {
    let st = O.initial(true);
    st = O.apply(st, { event: "config", state: "ok", read_only: false, devices: DEVICES });
    assert.deepEqual(O.banner(st, NOW), { tone: "warn", text: "Connecting to the MQTT broker…" });
    st = O.apply(st, { event: "broker", state: "connecting", since: ago(1), ever_up: false });
    assert.deepEqual(O.banner(st, NOW), { tone: "warn", text: "Connecting to the MQTT broker…" });
    assert.equal(O.liveText(st), "");
    assert.equal(O.lockText(st, "light"), "The MQTT broker is not connected.");
});

t("lock texts for the blind: broker, bridge, offline, type", () => {
    let st = O.apply(live(), { event: "broker", state: "down", since: ago(5), ever_up: true });
    assert.equal(O.lockText(st, "blind"), "The MQTT broker is not connected.");
    st = O.apply(live(), { event: "bridge", state: "offline", since: ago(5) });
    assert.equal(O.lockText(st, "blind"), "Zigbee2MQTT is offline.");
    assert.equal(O.lockText(st, "light"), "Zigbee2MQTT is offline.");
    assert.equal(O.lockText(live({ shade: { availability: "offline" } }), "blind"), "Shade is offline.");
    assert.equal(O.lockText(live({ shade: { definition: { matches: false, properties: [] } } }), "blind"),
        "Zigbee2MQTT does not list Shade as a blind yet.");
    assert.equal(O.lockText(live(), "blind"), "");
});

t("before the first full report: not live, the rows wait", () => {
    let st = O.initial(true);
    for (const ev of [
        { event: "config", state: "ok", read_only: false, devices: DEVICES },
        { event: "broker", state: "up", since: ago(1), ever_up: true },
        { event: "bridge", state: "online", since: null }])
        st = O.apply(st, ev);
    assert.equal(O.liveText(st), "");
    st = O.apply(st, { event: "synced" });
    assert.equal(O.liveText(st), "live");
    // A broker drop clears synced: not live again until the next one.
    st = O.apply(st, { event: "broker", state: "down", since: ago(1), ever_up: true });
    st = O.apply(st, { event: "broker", state: "up", since: ago(0), ever_up: true });
    assert.equal(O.liveText(st), "");
});

t("not confirmed, light: what it still is", () => {
    const note = (values, action, value) => {
        let st = live({ lamp: { values } });
        st = O.sent(st, 7, "lamp", action, value, Date.parse("2026-11-15T18:44:00Z"));
        st = O.apply(st, { event: "command", id: 7, state: "not-confirmed" });
        return st.notes.lamp.footer;
    };
    assert.equal(note({ state: "OFF", brightness: 140 }, "on", null), "Lamp did not confirm on; still off.");
    assert.equal(note({ state: "ON" }, "off", null), "Lamp did not confirm off; still on.");
    assert.equal(note({}, "off", null), "Lamp did not confirm off; still not known.");
});

t("not confirmed, blind: close, stop, a position", () => {
    const sub = (action, value) => {
        let st = live();
        st = O.sent(st, 8, "shade", action, value, Date.parse("2026-11-15T18:44:00Z"));
        st = O.apply(st, { event: "command", id: 8, state: "not-confirmed" });
        return [O.blindView(st, NOW, null, null).sub, st.notes.shade.footer];
    };
    assert.deepEqual(sub("close", null), ["Did not start closing (asked 18:44:00)",
        "Shade did not confirm within 5 s; still Open 60%."]);
    assert.equal(sub("stop", null)[0], "Did not stop (asked 18:44:00)");
    assert.equal(sub("position", 40)[0], "Did not move to 40% (asked 18:44:00)");
    let st = O.sent(live(), 9, "shade", "close", null, NOW);
    st = O.apply(st, { event: "command", id: 9, state: "refused", reason: "bridge-offline" });
    assert.equal(st.notes.shade.footer, "Shade: not sent, Zigbee2MQTT is offline.");
});

t("blind text when stopped without a position", () => {
    const b = O.blindView(live({ shade: { values: { state: "STOP" }, definition: { matches: true, properties: ["state"] } } }), NOW, null, null);
    assert.equal(b.sub, "Stopped");
});

t("two commands to one device: the newer one is shown", () => {
    let st = O.sent(live(), 10, "lamp", "brightness", O.toRaw(30), NOW);
    st = O.sent(st, 11, "lamp", "brightness", O.toRaw(90), NOW);
    assert.equal(O.lightView(st, NOW, null).handle, 90);
});

t("events the panel does not know change nothing", () => {
    const st = live();
    assert.equal(O.apply(st, { event: "rumour", id: "lamp" }), st);
    assert.equal(O.apply(st, { event: "command", id: 99, state: "confirmed" }), st);
});

t("bar: broker up, no socket counted yet", () => {
    const st = live({ s1: { values: null }, s2: { values: null }, s3: { values: null } });
    assert.equal(O.barView(st, NOW).watts, "— W");
});

t("KNOWN BUG: a device list with no sockets throws", () => {
    // socketsView takes Math.min() of no report times (Infinity) and turns
    // it into a date. The shipped list (desk-mqtt.nix) has five sockets, so
    // nothing reaches this today. When fixed, expect "0 sockets…" here.
    let st = O.initial(true);
    for (const ev of [
        { event: "config", state: "ok", read_only: false, devices: DEVICES.filter(d => d.kind !== "socket") },
        { event: "broker", state: "up", since: ago(600), ever_up: true },
        { event: "bridge", state: "online", since: null },
        dev("lamp", "light", "Lamp", { state: "ON", brightness: 140 }),
        { event: "synced" }])
        st = O.apply(st, ev);
    assert.throws(() => O.socketsView(st, NOW), RangeError);
    assert.throws(() => O.barView(st, NOW), RangeError);
});

console.log(`ok: ${n} tests`);
