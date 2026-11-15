// The Bluetooth panel's libraries (quickshell/bluetooth/services.js and
// devices.js) against invented devices.
// Run: node test-bluetooth.js <directory holding services.js and devices.js>
const assert = require("node:assert/strict");
const path = require("node:path");
const dir = path.resolve(process.argv[2]);
const S = require(path.join(dir, "services.js"));
const D = require(path.join(dir, "devices.js"));
const base = h => `0000${h}-0000-1000-8000-00805f9b34fb`;
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

t("every requested service family is named, never by UUID", () => {
    const want = {
        "110a": /A2DP source/, "110b": /A2DP sink/, "110d": /A2DP/,
        "111e": /HFP/, "111f": /HFP/, "1108": /HSP/, "1112": /HSP/, "1131": /HSP/,
        "110c": /AVRCP/, "110e": /AVRCP/, "110f": /AVRCP/,
        "1124": /HID/, "1812": /HOGP/,
        "1116": /NAP/, "1115": /PANU/, "1117": /GN/,
        "1105": /OBEX push/, "1106": /OBEX FTP/,
        "112e": /PBAP/, "112f": /PBAP/, "1130": /PBAP/,
        "1132": /MAP/, "1133": /MAP/, "1134": /MAP/,
        "112d": /SIM/, "1101": /Serial/,
        "1855": /LE Audio/, "1858": /LE Audio/, "184e": /LE Audio/, "1850": /LE Audio/
    };
    for (const [h, re] of Object.entries(want)) {
        const s = S.describe(base(h), "Phone");
        assert.ok(s.known, h);
        assert.match(s.name, re, h);
        assert.doesNotMatch(s.name, /[0-9a-f]{4}-|0x/i, h);
        assert.match(s.question, /^Let Phone .*\?$/, h);
    }
});

t("questions say what it means", () => {
    assert.equal(S.describe(base("110b"), "Pixel").question, "Let Pixel play its audio through this computer?");
    assert.equal(S.describe(base("1116"), "Pixel").question, "Let Pixel use this computer's network connection?");
});

t("upper-case UUIDs work", () => {
    assert.ok(S.describe(base("110B").toUpperCase(), "x").known);
});

t("unknown: an unlisted service, short UUID kept apart", () => {
    const s = S.describe(base("1800"), "Pixel");
    assert.equal(s.known, false);
    assert.equal(s.name, "an unlisted service");
    assert.equal(s.short, "1800");
    assert.doesNotMatch(s.question, /1800/);
    const v = S.describe("03b80e5a-ede8-4b33-a751-6ce34ec4c700", "Pixel");
    assert.equal(v.short, "03b80e5a");
    assert.equal(v.known, false);
});

t("no device name", () => {
    assert.match(S.describe(base("110b"), "").question, /^Let This device /);
});

t("kinds from BlueZ icons; unknown and empty fall back", () => {
    assert.equal(D.kind("input-gaming").label, "controller");
    assert.equal(D.kind("audio-headphones").audio, true);
    assert.equal(D.kind("phone").audio, false);
    assert.equal(D.kind("").label, "kind not reported");
    assert.equal(D.kind("watch").glyph, "\u{f00af}");
});

t("battery tiers at 15 and 35", () => {
    assert.deepEqual([0, 14, 15, 34, 35, 100].map(D.batteryTier), ["low", "low", "mid", "mid", "ok", "ok"]);
});

t("paired order: connected first, then name", () => {
    const l = D.sortPaired([{ name: "b", connected: false }, { name: "c", connected: true }, { name: "a", connected: false }]);
    assert.deepEqual(l.map(d => d.name), ["c", "a", "b"]);
});

t("nearby: unpaired, named, strongest first, then name", () => {
    const devs = [
        { dbusPath: "1", name: "Far", address: "01:00:00:00:00:01", paired: false },
        { dbusPath: "2", name: "Near", address: "01:00:00:00:00:02", paired: false },
        { dbusPath: "3", name: "01-00-00-00-00-03", address: "01:00:00:00:00:03", paired: false },
        { dbusPath: "4", name: "Mine", address: "01:00:00:00:00:04", paired: true },
        { dbusPath: "5", name: "Alpha", address: "01:00:00:00:00:05", paired: false }
    ];
    assert.deepEqual(D.nearby(devs, { 1: -80, 2: -40 }).map(d => d.name), ["Near", "Far", "Alpha"]);
    assert.deepEqual(D.nearby(devs, {}).map(d => d.name), ["Alpha", "Far", "Near"]);
});

t("low battery: once per crossing", () => {
    const dev = (b, avail = true) => [{ address: "A", name: "Pad", icon: "input-gaming", batteryAvailable: avail, battery: b }];
    let r = D.lowBattery(dev(0.20), []);
    assert.equal(r.send.length, 0);
    r = D.lowBattery(dev(0.14), r.notified);
    assert.equal(r.send.length, 1);
    assert.equal(r.send[0].percent, 14);
    r = D.lowBattery(dev(0.10), r.notified);
    assert.equal(r.send.length, 0, "not again while low");
    r = D.lowBattery(dev(0, false), r.notified);
    assert.deepEqual(r.notified, ["A"], "disconnected keeps the flag");
    r = D.lowBattery(dev(0.12), r.notified);
    assert.equal(r.send.length, 0, "reconnect while low is no crossing");
    r = D.lowBattery(dev(0.15), r.notified);
    assert.deepEqual(r.notified, []);
    r = D.lowBattery(dev(0.13), r.notified);
    assert.equal(r.send.length, 1, "second crossing");
    r = D.lowBattery([], r.notified);
    assert.deepEqual(r.notified, [], "forgotten device leaves the set");
});

t("uses: an agent without the calls field keeps the answer's wording", () => {
    const links = { transports: [{ uuid: base("110b"), state: "idle" }], control: true, network: false };
    const u = S.uses(links, [], { [base("111e")]: true }, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "allowed" }, { id: "audio", state: "connected" }, { id: "controls", state: "connected" }]);
    assert.deepEqual(u.lines, [
        ["calls through this computer", "allowed, no call now"],
        ["audio from Phone", "connected, idle"],
        ["media controls (AVRCP)", "connected"]]);
});

t("uses: calls connected with no question asked (a trusted phone)", () => {
    const links = { transports: [{ uuid: base("110b"), state: "idle" }], control: true, network: false, calls: "connected" };
    const u = S.uses(links, [], {}, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "connected" }, { id: "audio", state: "connected" }, { id: "controls", state: "connected" }]);
    assert.deepEqual(u.lines[0], ["calls through this computer", "connected, no call now"]);
});

t("uses: calls connected wins over a recorded answer", () => {
    const u = S.uses({ transports: [], calls: "connected" }, [], { [base("111e")]: true }, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "connected" }]);
    assert.deepEqual(u.lines, [["calls through this computer", "connected, no call now"]]);
});

t("uses: calls active from the agent, before or without PipeWire's call nodes", () => {
    const u = S.uses({ transports: [], calls: "active" }, [], {}, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "active" }]);
    assert.deepEqual(u.lines, [["calls through this computer", "in a call now"]]);
});

t("uses: a call node still means a call when the agent says none", () => {
    const u = S.uses({ transports: [], calls: "none" }, [{ profile: "headset-audio-gateway", mediaClass: "Audio/Source", linked: true }], {}, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "active" }]);
});

t("uses: calls not connected, allowed earlier: grey, says not connected", () => {
    const u = S.uses({ transports: [], calls: "none" }, [], { [base("111e")]: true }, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "allowed" }]);
    assert.deepEqual(u.lines, [["calls through this computer", "allowed, not connected"]]);
});

t("uses: calls not connected, denied: a line, no glyph", () => {
    const u = S.uses({ transports: [], calls: "none" }, [], { [base("111e")]: false }, "Phone");
    assert.deepEqual(u.roles, []);
    assert.deepEqual(u.lines, [["calls through this computer", "denied"]]);
});

t("uses: calls not connected, never asked: no handset", () => {
    const links = { transports: [{ uuid: base("110b"), state: "idle" }], control: false, network: false, calls: "none" };
    const u = S.uses(links, [], {}, "Phone");
    assert.equal(u.roles.some(r => r.id === "calls"), false);
    assert.equal(u.lines.some(l => l[0] === "calls through this computer"), false);
});

t("uses: the phone's broken stream (BlueZ active, no PipeWire node) is not 'playing here'", () => {
    const links = { transports: [{ uuid: base("110b"), state: "active" }], control: true, network: false, calls: "none" };
    const u = S.uses(links, [], {}, "Phone");
    assert.deepEqual(u.roles[0], { id: "audio", state: "connected" });
    assert.deepEqual(u.lines[0], ["audio from Phone", "sending, not reaching the speakers"]);
});

t("uses: a call in progress and audio linked to an output", () => {
    const links = { transports: [{ uuid: base("110b"), state: "active" }], control: false, network: true, calls: "active" };
    const nodes = [{ profile: "headset-head-unit", mediaClass: "Audio/Source", linked: true }, { profile: "a2dp-source", mediaClass: "Audio/Source", linked: true }];
    const u = S.uses(links, nodes, {}, "Phone");
    assert.deepEqual(u.roles, [{ id: "calls", state: "active" }, { id: "audio", state: "active" }, { id: "network", state: "active" }]);
    assert.equal(u.lines[0][1], "in a call now");
    assert.deepEqual(u.lines[1], ["audio from Phone", "playing here now"]);
});

t("uses: denied services listed by name, nothing as a role", () => {
    const u = S.uses(null, [], { [base("111e")]: false, [base("1105")]: false, "03b80e5a-ede8-4b33-a751-6ce34ec4c700": true }, "Phone");
    assert.deepEqual(u.roles, []);
    assert.deepEqual(u.lines, [
        ["calls through this computer", "denied"],
        ["File transfer (OBEX push)", "denied"],
        ["an unlisted service (03b80e5a)", "allowed"]]);
});

t("uses: nothing known", () => {
    assert.deepEqual(S.uses(null, [], {}, "x"), { roles: [], lines: [] });
});

console.log(`ok, ${n} tests`);
