// The Tailscale panel's library (quickshell/tailscale/tailscale.js) against
// hand-made `tailscale status --json` answers in fixtures/ (cut to the fields
// the panel reads; invented names, documentation address ranges) and the
// mesh-host file's shape (fixtures/mesh.json).
// Run: node test-tailscale-panel.js <directory holding tailscale.js>
process.env.TZ = "UTC";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const T = require(path.join(path.resolve(process.argv[2]), "tailscale.js"));
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

const NOW = Date.parse("2026-11-16T12:00:00.000Z");
const MIN = 60000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const fixture = name => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name + ".json"), "utf8"));
const MESH = fixture("mesh");
const CALLS = fixture("calls");
const STATES = fixture("states");
const OVERLAYS = fixture("overlays");
const clone = x => JSON.parse(JSON.stringify(x));

const call = (status, light) => ({ stdout: JSON.stringify(status), exit: 0, stderr: "", timedOut: false, light: !!light });
const answer = (status, prev, at) => T.read(call(status), prev || T.initial(), at === undefined ? NOW : at);
const view = (a, ui, mesh) => T.view(a, mesh === undefined ? MESH : mesh, NOW, ui || T.initialUi());
const rows = v => v.groups.reduce((all, g) => all.concat(g.rows), []);
const row = (v, id) => rows(v).find(r => r.id === id);
const keyNames = r => r.keys.map(k => k.key).join(" ");
const stripTexts = v => v.strips.map(s => [s.tone, s.text]);
const wellText = v => v.well.parts.map(p => p.text + (p.tone ? `[${p.tone}]` : "")).join(" ");
const overlay = name => {
    const st = clone(fixture("running"));
    const o = OVERLAYS[name];
    for (const k of Object.keys(o))
        st[k] = k === "Self" ? Object.assign(st.Self, o.Self) : o[k];
    return st;
};
const running = () => answer(fixture("running"));
const failing = (name, good) => T.read(Object.assign({ light: false }, CALLS[name]), good || T.initial(), NOW);
const lastGood = () => answer(fixture("running"), null, NOW - 2 * MIN);

// ---- section 1 -------------------------------------------------------------

t("running: header, well, groups in order, nothing over the list, bar on", () => {
    const v = view(running());
    assert.deepEqual(v.header, { word: "connected", colour: "green", meta: "read only" });
    assert.equal(wellText(v), "BrightFalls 100.64.0.1 · MagicDNS on · key never expires · 1.104.5");
    assert.equal(v.well.parts[0].bold, true);
    assert.deepEqual(v.strips, []);
    assert.equal(v.versionLine, "");
    assert.equal(v.note, "");
    assert.equal(v.live, true);
    assert.deepEqual(v.groups.map(g => [g.title, g.rows.map(r => r.name)]), [
        ["MY HOSTS", ["Nexus", "NightSprings", "CauldronLake"]],
        ["OTHER DEVICES", ["nas.tail1111.ts.net", "phone"]]
    ]);
    assert.deepEqual(v.ids, ["nNexus", "nNightSprings", "nCauldronLake", "nNas", "nPhone"]);
    assert.deepEqual(v.bar, { look: "on", colour: "fg" });
    assert.deepEqual(v.hints, [["↑↓ J K", "device"], ["O", "admin console"], ["F5", "refresh"], ["Esc", "close"]]);
});

t("running rows: glyph, chip, second line, dimmed", () => {
    const v = view(running());
    const want = {
        nNexus: ["▤", "Direct", "green", "linux · 100.64.0.2", false],
        nNightSprings: ["▭", "Idle", "soft", "macOS · 100.64.0.3", false],
        nCauldronLake: ["▭", "Offline", "dim", "linux · last seen 5 d ago", true],
        nNas: ["◫", "Idle", "soft", "linux · 100.64.0.6 · shared in", false],
        nPhone: ["▯", "Offline", "dim", "android · last seen 22 d ago · key expires in 4 months", true]
    };
    for (const [id, [glyph, label, colour, line, dim]] of Object.entries(want)) {
        const r = row(v, id);
        assert.equal(r.glyph, glyph, id);
        assert.deepEqual(r.chip, { label, colour }, id);
        assert.equal(r.line, line, id);
        assert.equal(r.dim, dim, id);
    }
});

t("running: the first row is selected, folded, with its keys; other rows have none", () => {
    const v = view(running());
    assert.equal(v.selected, "nNexus");
    const nexus = row(v, "nNexus");
    assert.equal(nexus.selected, true);
    assert.deepEqual(nexus.keys, [{ key: "Enter", label: "details" }, { key: "Y", label: "copy" }, { key: "T", label: "ssh" }]);
    assert.deepEqual(nexus.details, []);
    assert.equal(keyNames(row(v, "nNightSprings")), "");
    assert.equal(keyNames(row(view(running(), { selected: "nCauldronLake", unfolded: [], chooser: null }), "nCauldronLake")), "Enter Y");
    assert.equal(keyNames(row(view(running(), { selected: "nPhone", unfolded: [], chooser: null }), "nPhone")), "Enter Y");
});

t("details: Nexus as in section 1, idle and never-sent paths, shared owner", () => {
    const v = view(running(), { selected: "nNexus", unfolded: ["nNexus", "nNightSprings", "nNas", "nCauldronLake"], chooser: null });
    const nexus = row(v, "nNexus");
    assert.deepEqual(nexus.keys[0], { key: "Enter", label: "fold" });
    assert.deepEqual(nexus.details, [
        { label: "dns", value: "nexus-ts.tail0000.ts.net" },
        { label: "addresses", value: "100.64.0.2 · fd7a:115c:a1e0::2" },
        { label: "path", value: "direct, 192.0.2.10:41641" },
        { label: "home relay", value: "lhr" },
        { label: "traffic", value: "received 5.5 GB · sent 312 MB" },
        { label: "key", value: "never expires" },
        { label: "owner", value: "you" },
        { label: "ssh", value: "nexus" }
    ]);
    assert.equal(row(v, "nNightSprings").details.find(d => d.label === "path").value, "idle, last sent 9 min ago");
    const nas = row(v, "nNas").details;
    assert.equal(nas.find(d => d.label === "path").value, "nothing sent yet");
    assert.equal(nas.find(d => d.label === "owner").value, "shared in");
    assert.equal(nas.find(d => d.label === "traffic").value, "received none yet · sent none yet");
    assert.equal(nas.find(d => d.label === "ssh"), undefined);
    // Offline: no path line.
    assert.equal(row(v, "nCauldronLake").details.find(d => d.label === "path"), undefined);
});

// ---- 2a: the panel as a whole ---------------------------------------------

t("2a 1: not read yet", () => {
    const v = view(T.initial());
    assert.deepEqual(v.header, { word: "reading…", colour: "dim", meta: "read only" });
    assert.equal(v.note, "Reading Tailscale…");
    assert.deepEqual(v.strips, []);
    assert.equal(v.well, null);
    assert.deepEqual(v.groups, []);
    assert.deepEqual(v.bar, { look: "off", colour: "dim" });
});

t("2a 2: daemon not running: red strip, no list even with a good one before", () => {
    const a = failing("no-daemon", lastGood());
    assert.equal(a.state, 2);
    const v = view(a);
    assert.deepEqual(v.header, { word: "not running", colour: "red", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["red", "tailscaled is not running. It is enabled in Nix; systemctl status tailscaled says why it stopped."]]);
    assert.deepEqual(v.strips[0].parts.filter(p => p.code).map(p => p.text), ["systemctl status tailscaled"]);
    assert.deepEqual(v.groups, []);
    assert.equal(v.well, null);
    assert.deepEqual(v.hints, [["O", "admin console"], ["F5", "retry"], ["Esc", "close"]]);
    assert.equal(v.bar.look, "attention");
});

t("2a 3: status call failed: exit code and stderr's first line, last good list greyed", () => {
    const a = failing("in-use", lastGood());
    assert.equal(a.state, 3);
    const v = view(a);
    assert.deepEqual(v.header, { word: "error", colour: "red", meta: "as of 11:58" });
    assert.deepEqual(stripTexts(v), [["red", "tailscale status failed (exit 1): 401 Unauthorized: Tailscale already in use by another user"]]);
    assert.equal(v.live, false);
    assert.equal(rows(v).length, 5);
    for (const r of rows(v)) {
        assert.equal(r.dim, true, r.id);
        assert.equal(r.chip.colour, "dim", r.id);
    }
    assert.equal(row(v, "nNexus").chip.label, "Direct");
    assert.equal(v.bar.look, "attention");
    assert.equal(view(failing("in-use")).groups.length, 0);
    assert.equal(failing("socket-failed").state, 3);
    assert.deepEqual(stripTexts(view(failing("silent-failure"))), [["red", "tailscale status failed (exit 2)."]]);
});

t("2a 4: hung: orange strip, last good list", () => {
    const v = view(failing("hung", lastGood()));
    assert.deepEqual(v.header, { word: "no answer", colour: "orange", meta: "as of 11:58" });
    assert.deepEqual(stripTexts(v), [["orange", "tailscale status did not answer within 10 s and was stopped. Trying again in 5 s."]]);
    assert.equal(rows(v).length, 5);
    assert.equal(v.bar.look, "attention");
});

t("2a 5: bad output, and junk input of every kind", () => {
    for (const name of ["not-json", "array", "no-backend-state", "backend-state-number", "json-null"]) {
        const a = failing(name, lastGood());
        assert.equal(a.state, 5, name);
        assert.equal(a.status, null, name);
        const v = view(a);
        assert.deepEqual(v.header, { word: "bad output", colour: "orange", meta: "as of 11:58" }, name);
        assert.deepEqual(stripTexts(v), [["orange", "tailscale status printed something that is not status JSON. Trying again in 5 s."]], name);
        assert.equal(rows(v).length, 5, name);
        assert.equal(v.bar.look, "attention", name);
    }
});

t("2a 6: NoState: grey strip, no list, off; Health strips under it make it attention", () => {
    const v = view(answer(STATES.nostate));
    assert.deepEqual(v.header, { word: "loading", colour: "dim", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["dim", "The daemon is loading its state and has not reached the coordination server yet."]]);
    assert.deepEqual(v.groups, []);
    assert.equal(v.bar.look, "off");
    const h = view(answer(STATES["nostate-health"]));
    assert.deepEqual(stripTexts(h), [["dim", "The daemon is loading its state and has not reached the coordination server yet."], ["orange", "The state store could not be read."]]);
    assert.equal(h.bar.look, "attention");
});

t("2a 7: InUseOtherUser is drawn as an unknown state", () => {
    const st = clone(STATES.unknown);
    st.BackendState = "InUseOtherUser";
    const v = view(answer(st));
    assert.deepEqual(v.header, { word: "InUseOtherUser", colour: "orange", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["orange", "Tailscale reports a state this panel does not know: InUseOtherUser."]]);
});

t("2a 8: logged out: the login command, Y copies it, well has name and version", () => {
    const a = answer(STATES["logged-out"]);
    assert.equal(a.state, 8);
    const v = view(a);
    assert.deepEqual(v.header, { word: "logged out", colour: "orange", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["orange", "Logged out. This panel cannot log in; run sudo tailscale login in a terminal (Y copies it)."]]);
    assert.deepEqual(v.strips[0].parts.filter(p => p.code).map(p => p.text), ["sudo tailscale login"]);
    assert.equal(wellText(v), "brightfalls · 1.104.5");
    assert.deepEqual(v.groups, []);
    assert.deepEqual(v.hints, [["Y", "copy command"], ["O", "admin console"], ["F5", "refresh"], ["Esc", "close"]]);
    assert.equal(v.bar.look, "attention");
});

t("2a 9: login started: O opens the login page", () => {
    const a = answer(STATES["login-started"]);
    assert.equal(a.state, 9);
    const v = view(a);
    assert.deepEqual(v.header, { word: "logged out", colour: "orange", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["orange", "A login was started. Finish it in the browser: O opens the login page."]]);
    assert.deepEqual(v.hints, [["Y", "copy command"], ["O", "login page"], ["F5", "refresh"], ["Esc", "close"]]);
    assert.equal(v.bar.look, "attention");
});

t("2a 10: this computer's key expired: red, the map greyed; a kept map alone also means it", () => {
    const a = answer(STATES["key-expired"]);
    assert.equal(a.state, 10);
    const v = view(a);
    assert.deepEqual(v.header, { word: "key expired", colour: "red", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["red", "This computer's key expired, so it is off the tailnet. Log in again with sudo tailscale login (Y copies it)."]]);
    assert.deepEqual(rows(v).map(r => [r.name, r.chip.label, r.chip.colour, r.dim]), [["Nexus", "Direct", "dim", true]]);
    assert.equal(keyNames(row(v, "nNexus")), "Enter");
    assert.equal(wellText(v), "BrightFalls 100.64.0.1 · MagicDNS on · key expired 3 d ago[orange] · 1.104.5");
    assert.equal(v.bar.look, "attention");
    const st = clone(STATES["key-expired"]);
    delete st.Self.Expired;
    assert.equal(answer(st).state, 10);
});

t("2a 11: not approved: orange; the list greyed if the map is there", () => {
    const v = view(answer(STATES["machine-auth"]));
    assert.deepEqual(v.header, { word: "not approved", colour: "orange", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["orange", "This computer is waiting for a tailnet admin to approve it. O opens the admin console."]]);
    assert.deepEqual(rows(v).map(r => [r.chip.colour, r.dim]), [["dim", true]]);
    assert.equal(v.bar.look, "attention");
    const st = clone(STATES["machine-auth"]);
    st.Peer = null;
    assert.deepEqual(view(answer(st)).groups, []);
});

t("2a 12: stopped: grey, the kept map greyed, off", () => {
    const v = view(answer(STATES.stopped));
    assert.deepEqual(v.header, { word: "off", colour: "dim", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["dim", "Tailscale is off (tailscale down). Devices below are from before; turning it on needs sudo tailscale up."]]);
    assert.deepEqual(v.strips[0].parts.filter(p => p.code).map(p => p.text), ["tailscale down", "sudo tailscale up"]);
    assert.deepEqual(rows(v).map(r => [r.name, r.chip.label, r.chip.colour, r.dim]), [["Nexus", "Direct", "dim", true], ["CauldronLake", "Offline", "dim", true]]);
    assert.equal(v.bar.look, "off");
    const st = clone(STATES.stopped);
    st.Peer = null;
    assert.deepEqual(stripTexts(view(answer(st))), [["dim", "Tailscale is off (tailscale down). Turning it on needs sudo tailscale up."]]);
});

t("2a 13: starting: connecting, the list live, off", () => {
    const v = view(answer(STATES.starting));
    assert.deepEqual(v.header, { word: "connecting", colour: "cyan", meta: "read only" });
    assert.deepEqual(v.strips, []);
    assert.equal(v.live, true);
    assert.deepEqual(rows(v).map(r => [r.name, r.chip.label, r.chip.colour, r.dim]), [["Nexus", "Idle", "soft", false]]);
    assert.equal(keyNames(row(v, "nNexus")), "Enter Y T");
    assert.equal(v.bar.look, "off");
});

t("2a 15: unknown state named in the header and the strip", () => {
    const v = view(answer(STATES.unknown));
    assert.deepEqual(v.header, { word: "SomeNewState", colour: "orange", meta: "read only" });
    assert.deepEqual(stripTexts(v), [["orange", "Tailscale reports a state this panel does not know: SomeNewState."]]);
    assert.equal(v.bar.look, "attention");
});

t("a good answer after a failure clears it and becomes the new last good one", () => {
    const failed = failing("hung", lastGood());
    const back = answer(fixture("running"), failed, NOW);
    assert.equal(back.state, 14);
    assert.equal(back.good.at, NOW);
    assert.equal(view(back).header.meta, "read only");
    assert.equal(view(back).bar.look, "on");
});

// ---- 2b: lines over any state with a status --------------------------------

t("2b health: one orange strip each, whole", () => {
    const v = view(answer(overlay("health")));
    assert.deepEqual(stripTexts(v), OVERLAYS.health.Health.map(h => ["orange", h]));
    assert.equal(v.bar.look, "attention");
});

t("2b not connected to control: orange in the well, only while Running", () => {
    const v = view(answer(overlay("control-lost")));
    assert.equal(wellText(v), "BrightFalls 100.64.0.1 · MagicDNS on · control: not connected[orange] · key never expires · 1.104.5");
    assert.deepEqual(v.strips, []);
    assert.equal(v.bar.look, "attention");
    const st = overlay("control-lost");
    st.BackendState = "Starting";
    assert.ok(!wellText(view(answer(st))).includes("control"));
    assert.equal(view(answer(st)).bar.look, "off");
});

t("2b own key expiring: strip and orange well part; far: neither", () => {
    const v = view(answer(overlay("self-expiring")));
    assert.deepEqual(stripTexts(v), [["orange", "This computer's key expires in 5 d. Renew it in the admin console (O)."]]);
    assert.equal(wellText(v), "BrightFalls 100.64.0.1 · MagicDNS on · key expires in 5 d[orange] · 1.104.5");
    assert.equal(v.bar.look, "attention");
    const far = view(answer(overlay("self-far")));
    assert.deepEqual(far.strips, []);
    assert.equal(wellText(far), "BrightFalls 100.64.0.1 · MagicDNS on · key expires in 4 months · 1.104.5");
    assert.equal(far.bar.look, "on");
});

t("2b exit node in use, offline, and one that matches no peer", () => {
    const on = view(answer(overlay("exit-node")));
    assert.deepEqual(stripTexts(on), [["cyan", "Internet traffic leaves through Nexus."]]);
    assert.equal(on.bar.look, "on");
    const down = view(answer(overlay("exit-node-down")));
    assert.deepEqual(stripTexts(down), [["red", "Exit node Nexus is offline: internet traffic is not getting out."]]);
    assert.equal(down.bar.look, "attention");
    assert.deepEqual(stripTexts(view(answer(overlay("exit-node-unknown")))), [["cyan", "Internet traffic leaves through an exit node."]]);
    assert.deepEqual(stripTexts(view(answer(overlay("exit-node-unknown-down")))), [["red", "The exit node is offline: internet traffic is not getting out."]]);
});

t("2b versions: newer is a yellow line and not counted; urgent is a red strip", () => {
    const newer = view(answer(overlay("newer")));
    assert.equal(newer.versionLine, "1.106.0 exists · comes with a flake update");
    assert.deepEqual(newer.strips, []);
    assert.equal(newer.bar.look, "on");
    const urgent = view(answer(overlay("urgent")));
    assert.deepEqual(stripTexts(urgent), [["red", "Tailscale says 1.104.5 misses an urgent security fix. It comes with a flake update."]]);
    assert.equal(urgent.versionLine, "1.106.0 exists · comes with a flake update");
    assert.equal(urgent.bar.look, "attention");
    const latest = view(answer(overlay("latest")));
    assert.equal(latest.versionLine, "");
    assert.deepEqual(latest.strips, []);
});

t("2b all at once, in the table's order", () => {
    const v = view(answer(overlay("all")));
    assert.deepEqual(stripTexts(v), [
        ["orange", "One warning."],
        ["orange", "This computer's key expires in 5 d. Renew it in the admin console (O)."],
        ["red", "Exit node Nexus is offline: internet traffic is not getting out."],
        ["red", "Tailscale says 1.104.5 misses an urgent security fix. It comes with a flake update."]
    ]);
    assert.ok(wellText(v).includes("control: not connected[orange]"));
});

t("2b lines come after the state's own strip", () => {
    const st = clone(STATES.stopped);
    st.Health = ["A warning."];
    assert.deepEqual(view(answer(st)).strips.map(s => s.tone), ["dim", "orange"]);
});

// ---- 2c, 2d, 2e: device rows ---------------------------------------------

t("2d and 2e: every chip rule and second-line combination", () => {
    const v = view(answer(fixture("peers")));
    const want = {
        "expired-flag": ["Expired", "red", "android · last seen 22 d ago · key expired"],
        "expired-past": ["Expired", "red", "android · last seen 22 d ago · key expired 3 d ago"],
        "exit-down": ["Exit node down", "red", "linux · last seen 3 min ago · offers exit node"],
        expiring: ["Expiring", "orange", "android · last seen 22 d ago · key expires in 5 d"],
        offline: ["Offline", "dim", "linux · last seen 5 d ago"],
        "offline-unset": ["Offline", "dim", "linux · last seen unknown"],
        exit: ["Exit node", "cyan", "linux · 100.64.1.7 · offers exit node"],
        direct: ["Direct", "green", "linux · 100.64.1.8"],
        "peer-relay": ["Peer relay", "cyan", "linux · 100.64.1.9 · shared in"],
        relayed: ["Relayed", "yellow", "linux · 100.64.1.10 · via fra · shared in"],
        "no-path": ["No path", "orange", "linux · 100.64.1.11"],
        idle: ["Idle", "soft", "macOS · 100.64.1.12"],
        never: ["Idle", "soft", "macOS · 100.64.1.13"],
        "online-expired": ["Expired", "red", "linux · 100.64.1.14 · key expired 2 h ago"],
        "shared-offline": ["Offline", "dim", "linux · last seen 2 h ago · shared in"],
        tagged: ["Direct", "green", "linux · 100.64.1.16 · tagged · routes 2 subnets"],
        offers: ["Idle", "soft", "linux · 100.64.1.17 · offers exit node"],
        bare: ["Idle", "soft", "no address"],
        "hostname-only": ["Idle", "soft", "linux · 100.64.1.19"],
        "v6-only": ["Idle", "soft", "plan9 · fd7a:115c:a1e0::122"],
        ios: ["Idle", "soft", "iOS · 100.64.1.23"],
        punycode: ["Idle", "soft", "linux · 100.64.1.24"],
        sharer: ["Idle", "soft", "linux · 100.64.1.25 · shared in · tagged"],
        "far-key": ["Offline", "dim", "android · last seen 22 d ago · key expires in 4 months"],
        "exit-relayed": ["Exit node", "cyan", "linux · 100.64.1.27 · via lhr · offers exit node"],
        "no-online-field": ["Offline", "dim", "linux · last seen unknown"]
    };
    assert.deepEqual(v.ids.slice().sort(), Object.keys(want).sort());
    for (const [id, [label, colour, line]] of Object.entries(want)) {
        const r = row(v, id);
        assert.deepEqual(r.chip, { label, colour }, id);
        assert.equal(r.line, line, id);
        assert.equal(r.dim, label === "Offline" || ["expired-flag", "expired-past", "exit-down", "expiring", "far-key"].includes(id), id);
    }
});

t("2c hidden rows: ShareeNode, an unused Mullvad node, entries that are not objects", () => {
    const v = view(answer(fixture("peers")));
    for (const id of ["sharee", "mullvad"])
        assert.equal(row(v, id), undefined, id);
    const st = fixture("peers");
    st.Peer.k21.ExitNode = true;
    assert.equal(row(view(answer(st)), "mullvad").chip.label, "Exit node");
});

t("2c names: mesh label, suffix stripped, shared-in keeps its own, HostName, unnamed, xn-- as sent", () => {
    const v = view(answer(fixture("peers")));
    assert.equal(row(v, "direct").name, "direct");
    assert.equal(row(v, "relayed").name, "relayed.tail1111.ts.net");
    assert.equal(row(v, "hostname-only").name, "printer");
    assert.equal(row(v, "punycode").name, "xn--caf-dma");
    assert.deepEqual([row(v, "bare").name, row(v, "bare").unnamed], ["unnamed device", true]);
    assert.equal(row(v, "direct").unnamed, false);
    // MagicDNSSuffix only at the top level when CurrentTailnet is absent.
    const st = fixture("peers");
    delete st.CurrentTailnet;
    assert.equal(row(view(answer(st)), "direct").name, "direct");
});

t("2c glyphs: mesh kinds, phones, anything else", () => {
    const v = view(answer(fixture("peers")));
    assert.equal(row(v, "ios").glyph, "▯");
    assert.equal(row(v, "expiring").glyph, "▯");
    assert.equal(row(v, "v6-only").glyph, "◫");
    assert.equal(row(v, "bare").glyph, "◫");
    const r = view(running());
    assert.deepEqual(rows(r).map(x => x.glyph), ["▤", "▭", "▭", "◫", "▯"]);
});

t("2c details: each path, routes and exit node offered, tags as owner, bytes", () => {
    const ids = ["direct", "peer-relay", "relayed", "no-path", "tagged", "exit", "sharer"];
    const v = view(answer(fixture("peers")), { selected: "", unfolded: ids, chooser: null });
    const d = (id, label) => (row(v, id).details.find(x => x.label === label) || {}).value;
    assert.equal(d("peer-relay", "path"), "peer relay");
    assert.equal(d("relayed", "path"), "relayed via fra");
    assert.equal(d("no-path", "path"), "no path");
    assert.equal(d("no-path", "home relay"), undefined);
    assert.equal(d("tagged", "owner"), "tagged: tag:a, tag:b");
    assert.equal(d("tagged", "offers"), "192.0.2.0/25 · 198.51.100.0/24");
    assert.equal(d("exit", "offers"), "exit node");
    assert.equal(d("direct", "traffic"), "received 999 B · sent 9.9 kB");
    assert.equal(d("direct", "offers"), undefined);
    assert.equal(d("sharer", "owner"), "tagged: tag:a");
    const u = view(answer(fixture("peers")), { selected: "", unfolded: ["bare", "expired-past"], chooser: null });
    assert.equal(row(u, "bare").details.find(x => x.label === "addresses").value, "none");
    assert.equal(row(u, "bare").details.find(x => x.label === "dns"), undefined);
    assert.equal(row(u, "expired-past").details.find(x => x.label === "key").value, "expired 3 d ago");
});

t("sort: my hosts then other devices; online first, then by name ignoring case", () => {
    const v = view(answer(fixture("peers")));
    assert.deepEqual(v.groups.map(g => g.title), ["OTHER DEVICES"]);
    const names = rows(v).map(r => r.name);
    const online = rows(v).filter(r => !r.dim || r.chip.label === "Expired" && r.line.includes("100.64")).map(r => r.name);
    assert.deepEqual(names.slice(0, online.length), [
        "direct", "exit", "exit-relayed", "idle", "ios", "never", "no-path", "offers", "online-expired",
        "peer-relay.tail1111.ts.net", "printer", "relayed.tail1111.ts.net", "sharer", "tagged",
        "unnamed device", "v6-only", "xn--caf-dma"
    ]);
    assert.deepEqual(names.slice(online.length), [
        "exit-down", "expired-flag", "expired-past", "expiring", "far-key", "no-online-field", "offline",
        "offline-unset", "shared-offline.tail1111.ts.net"
    ]);
    const st = fixture("running");
    st.Peer["nodekey:0003"].HostName = "x";
    st.Peer["nodekey:0005"].DNSName = "Alpha.tail0000.ts.net.";
    st.Peer["nodekey:0005"].Online = true;
    assert.deepEqual(rows(view(answer(st))).map(r => r.name), ["Nexus", "NightSprings", "CauldronLake", "Alpha", "nas.tail1111.ts.net"]);
});

t("no mesh file: every peer is another device, T never offered", () => {
    const v = view(running(), null, null);
    assert.deepEqual(v.groups.map(g => g.title), ["OTHER DEVICES"]);
    assert.deepEqual(rows(v).map(r => r.name), ["nas.tail1111.ts.net", "nexus-ts", "nightsprings-ts", "cauldronlake-ts", "phone"]);
    assert.equal(rows(v).every(r => r.glyph === "◫" || r.glyph === "▯"), true);
    assert.equal(v.well.parts[0].text, "brightfalls-ts");
    const sel = view(running(), { selected: "nNexus", unfolded: [], chooser: null }, null);
    assert.equal(keyNames(row(sel, "nNexus")), "Enter Y");
});

// ---- wording -------------------------------------------------------------

t("last seen: every boundary", () => {
    const at = d => T.ago(NOW - d, NOW);
    assert.equal(at(59 * 1000), "just now");
    assert.equal(at(60 * 1000), "1 min ago");
    assert.equal(at(HOUR - 1000), "59 min ago");
    assert.equal(at(HOUR), "1 h ago");
    assert.equal(at(47 * HOUR), "47 h ago");
    assert.equal(at(48 * HOUR - 1000), "47 h ago");
    assert.equal(at(48 * HOUR), "2 d ago");
    assert.equal(at(59 * DAY), "59 d ago");
    assert.equal(at(60 * DAY - 1000), "59 d ago");
    assert.equal(at(60 * DAY), "2026-09-17");
    assert.equal(T.ago(NOW + 5 * MIN, NOW), "just now");
});

t("key expiry: future wording, past wording, the 14-day line", () => {
    const k = d => T.keyState({ KeyExpiry: new Date(NOW + d).toISOString() }, NOW);
    assert.deepEqual(k(30 * MIN), { kind: "expiring", text: "key expires in 30 min" });
    assert.deepEqual(k(59 * 1000), { kind: "expiring", text: "key expires in 1 min" });
    assert.deepEqual(k(HOUR), { kind: "expiring", text: "key expires in 1 h" });
    assert.deepEqual(k(47 * HOUR), { kind: "expiring", text: "key expires in 47 h" });
    assert.deepEqual(k(48 * HOUR), { kind: "expiring", text: "key expires in 2 d" });
    assert.deepEqual(k(13 * DAY), { kind: "expiring", text: "key expires in 13 d" });
    assert.deepEqual(k(14 * DAY), { kind: "expiring", text: "key expires in 14 d" });
    assert.deepEqual(k(14 * DAY + 1000), { kind: "far", text: "key expires in 14 d" });
    assert.deepEqual(k(59 * DAY), { kind: "far", text: "key expires in 59 d" });
    assert.deepEqual(k(60 * DAY), { kind: "far", text: "key expires in 2 months" });
    assert.deepEqual(k(124 * DAY), { kind: "far", text: "key expires in 4 months" });
    assert.deepEqual(k(-1000), { kind: "expired", text: "key expired just now" });
    assert.deepEqual(k(-3 * DAY), { kind: "expired", text: "key expired 3 d ago" });
    assert.deepEqual(T.keyState({}, NOW), { kind: "none", text: "" });
    assert.deepEqual(T.keyState({ Expired: true }, NOW), { kind: "expired", text: "key expired" });
    assert.deepEqual(T.keyState({ KeyExpiry: "0001-01-01T00:00:00Z" }, NOW), { kind: "none", text: "" });
});

t("bytes: decimal units, one decimal under 10, none from 10, zero", () => {
    const want = [[0, "none yet"], [undefined, "none yet"], [1, "1 B"], [999, "999 B"], [1000, "1.0 kB"], [9940, "9.9 kB"], [9999, "10 kB"], [312000, "312 kB"], [999499, "999 kB"], [999950, "1.0 MB"], [312000000, "312 MB"], [5502332656, "5.5 GB"], [1e12, "1.0 TB"], [2.5e15, "2500 TB"]];
    for (const [b, text] of want)
        assert.equal(T.bytes(b), text, String(b));
});

t("version: up to the first dash", () => {
    assert.equal(T.shortVersion("1.104.5-t0000000-g0000000"), "1.104.5");
    assert.equal(T.shortVersion("1.104.5"), "1.104.5");
    assert.equal(T.shortVersion(undefined), "");
});

// ---- keys ----------------------------------------------------------------

t("keys: navigation across both groups, J K and arrows, Home End", () => {
    const v = view(running());
    let ui = T.initialUi();
    const press = (key, at) => T.decide(view(running(), at), at, key);
    let r = press("Down", ui);
    assert.deepEqual(r, { kind: "ui", ui: { selected: "nNightSprings", unfolded: [], chooser: null } });
    r = press("J", r.ui);
    assert.equal(r.ui.selected, "nCauldronLake");
    r = press("Down", r.ui);
    assert.equal(r.ui.selected, "nNas");
    r = press("K", r.ui);
    assert.equal(r.ui.selected, "nCauldronLake");
    r = press("Up", r.ui);
    assert.equal(r.ui.selected, "nNightSprings");
    assert.equal(press("End", r.ui).ui.selected, "nPhone");
    assert.equal(press("Home", { selected: "nPhone", unfolded: [], chooser: null }).ui.selected, "nNexus");
    assert.equal(press("Up", ui).ui.selected, "nNexus");
    assert.equal(press("Down", { selected: "nPhone", unfolded: [], chooser: null }).ui.selected, "nPhone");
    assert.equal(v.ids.length, 5);
    // One row: navigation is not offered.
    const one = view(answer(STATES.starting));
    assert.equal(T.decide(one, T.initialUi(), "Down").kind, "none");
    assert.ok(!one.hints.some(h => h[1] === "device"));
});

t("keys: Enter unfolds and folds the selected row", () => {
    let r = T.decide(view(running()), T.initialUi(), "Enter");
    assert.deepEqual(r, { kind: "ui", ui: { selected: "nNexus", unfolded: ["nNexus"], chooser: null } });
    assert.equal(row(view(running(), r.ui), "nNexus").details.length > 0, true);
    r = T.decide(view(running(), r.ui), r.ui, "Enter");
    assert.deepEqual(r.ui.unfolded, []);
});

t("keys: Y opens the chooser; digits copy and close it; Esc goes back", () => {
    const r = T.decide(view(running()), T.initialUi(), "Y");
    assert.deepEqual(r, { kind: "ui", ui: { selected: "nNexus", unfolded: [], chooser: "nNexus" } });
    const v = view(running(), r.ui);
    assert.deepEqual(v.chooser, {
        id: "nNexus",
        title: "Copy from Nexus",
        keys: [{ key: "1", label: "name" }, { key: "2", label: "DNS name" }, { key: "3", label: "IPv4" }, { key: "4", label: "IPv6" }, { key: "Esc", label: "back" }]
    });
    assert.deepEqual(v.hints, [["1–4", "copy"], ["Esc", "back"]]);
    const closed = { selected: "nNexus", unfolded: [], chooser: null };
    assert.deepEqual(T.decide(v, r.ui, "2"), { kind: "copy", ui: closed, text: "nexus-ts.tail0000.ts.net", command: ["wl-copy", "--", "nexus-ts.tail0000.ts.net"], say: "Copied the DNS name of Nexus." });
    assert.equal(T.decide(v, r.ui, "1").text, "Nexus");
    assert.equal(T.decide(v, r.ui, "3").text, "100.64.0.2");
    assert.equal(T.decide(v, r.ui, "3").say, "Copied the IPv4 address of Nexus.");
    assert.equal(T.decide(v, r.ui, "4").text, "fd7a:115c:a1e0::2");
    assert.deepEqual(T.decide(v, r.ui, "Esc"), { kind: "ui", ui: closed });
    for (const key of ["T", "Down", "Enter", "O", "5"])
        assert.equal(T.decide(v, r.ui, key).kind, "none", key);
});

t("keys: the chooser leaves out what does not exist and keeps the numbers", () => {
    const st = answer(fixture("peers"));
    const v6 = view(st, { selected: "v6-only", unfolded: [], chooser: "v6-only" });
    assert.deepEqual(v6.chooser.keys.map(k => k.key), ["1", "2", "4", "Esc"]);
    assert.deepEqual(v6.hints[0], ["1–4", "copy"]);
    assert.equal(T.decide(v6, { selected: "v6-only", unfolded: [], chooser: "v6-only" }, "3").kind, "none");
    const host = view(st, { selected: "hostname-only", unfolded: [], chooser: "hostname-only" });
    assert.deepEqual(host.chooser.keys.map(k => k.key), ["1", "3", "Esc"]);
    const bare = view(st, { selected: "bare", unfolded: [], chooser: null });
    assert.equal(keyNames(row(bare, "bare")), "Enter");
    assert.deepEqual(T.decide(bare, { selected: "bare", unfolded: [], chooser: null }, "Y"), { kind: "say", ui: { selected: "bare", unfolded: [], chooser: null }, text: "copy: nothing to copy from unnamed device" });
});

t("keys: T opens ssh on an online mesh host with sshd; otherwise says why", () => {
    const sel = id => ({ selected: id, unfolded: [], chooser: null });
    const ok = T.decide(view(running()), sel("nNexus"), "T");
    assert.deepEqual(ok, { kind: "ssh", ui: sel("nNexus"), alias: "nexus", command: ["uwsm", "app", "--", "ghostty", "--title=Tailscale: Nexus", "-e", "ssh", "nexus"] });
    const say = (a, id) => T.decide(view(a, sel(id)), sel(id), "T");
    assert.deepEqual(say(running(), "nCauldronLake"), { kind: "say", ui: sel("nCauldronLake"), text: "ssh: CauldronLake is offline" });
    assert.equal(say(running(), "nPhone").text, "ssh: not a mesh host");
    assert.equal(say(failing("hung", lastGood()), "nNexus").text, "ssh: the device list is not live");
    assert.equal(say(answer(STATES.stopped), "nNexus").text, "ssh: the device list is not live");
    const st = fixture("running");
    st.Peer["nodekey:0005"].DNSName = "nosshd-ts.tail0000.ts.net.";
    st.Peer["nodekey:0005"].Online = true;
    assert.equal(say(answer(st), "nPhone").text, "ssh: NoSshd does not run sshd");
    assert.equal(T.decide(view(T.initial()), T.initialUi(), "T").kind, "none");
});

t("keys: O opens the admin console, or the login page while AuthURL is set", () => {
    const r = T.decide(view(running()), T.initialUi(), "O");
    assert.deepEqual(r, { kind: "open", ui: { selected: "nNexus", unfolded: [], chooser: null }, url: T.ADMIN_URL, command: ["uwsm", "app", "--", "xdg-open", T.ADMIN_URL] });
    assert.equal(T.decide(view(answer(STATES["login-started"])), T.initialUi(), "O").url, "https://login.tailscale.com/a/0000aaaa");
    assert.equal(T.decide(view(failing("no-daemon")), T.initialUi(), "O").url, T.ADMIN_URL);
});

t("keys: Y copies the login command in states 8 to 10, even over a row", () => {
    for (const name of ["logged-out", "login-started", "key-expired"]) {
        const r = T.decide(view(answer(STATES[name])), T.initialUi(), "Y");
        assert.equal(r.kind, "copy", name);
        assert.equal(r.text, "sudo tailscale login", name);
        assert.deepEqual(r.command, ["wl-copy", "--", "sudo tailscale login"]);
        assert.equal(r.say, "Copied the login command.");
    }
    // A chooser cannot open there.
    assert.equal(view(answer(STATES["key-expired"]), { selected: "nNexus", unfolded: [], chooser: "nNexus" }).chooser, null);
});

t("keys: F5, Esc, and keys with nothing selected", () => {
    const ui = { selected: "nNexus", unfolded: [], chooser: null };
    assert.deepEqual(T.decide(view(running()), ui, "F5"), { kind: "refresh", ui });
    assert.deepEqual(T.decide(view(running()), ui, "Esc"), { kind: "close", ui });
    const empty = view(T.initial());
    for (const key of ["Enter", "Y", "T", "Down", "X"])
        assert.equal(T.decide(empty, T.initialUi(), key).kind, "none", key);
    assert.equal(T.decide(empty, T.initialUi(), "F5").kind, "refresh");
});

t("keys: a held key's repeats move the selection and do nothing else", () => {
    const ui = { selected: "nNexus", unfolded: [], chooser: null };
    const v = view(running(), ui);
    for (const key of ["Enter", "Y", "T", "O", "F5", "Esc"])
        assert.deepEqual(T.decide(v, ui, key, true), { kind: "none", ui }, key);
    const chooser = { selected: "nNexus", unfolded: [], chooser: "nNexus" };
    for (const key of ["1", "2", "Esc"])
        assert.equal(T.decide(view(running(), chooser), chooser, key, true).kind, "none", key);
    assert.equal(T.decide(view(answer(STATES["logged-out"])), T.initialUi(), "Y", true).kind, "none");
    assert.equal(T.decide(v, ui, "Down", true).ui.selected, "nNightSprings");
    assert.equal(T.decide(v, ui, "J", true).ui.selected, "nNightSprings");
    assert.equal(T.decide(v, { selected: "nNightSprings", unfolded: [], chooser: null }, "K", true).ui.selected, "nNexus");
    assert.equal(T.decide(v, ui, "End", true).ui.selected, "nPhone");
});

t("selection is kept by peer ID across reads; a gone one falls back to the first", () => {
    const ui = { selected: "nNightSprings", unfolded: ["nNightSprings"], chooser: "nNightSprings" };
    const st = fixture("running");
    st.Peer["nodekey:0003"].Online = false;
    st.Peer["nodekey:0003"].LastSeen = "2026-11-16T11:59:00Z";
    const v = view(answer(st), ui);
    assert.deepEqual(v.ids, ["nNexus", "nCauldronLake", "nNightSprings", "nNas", "nPhone"]);
    assert.equal(v.selected, "nNightSprings");
    assert.equal(row(v, "nNightSprings").unfolded, true);
    assert.equal(v.chooser.id, "nNightSprings");
    delete st.Peer["nodekey:0003"];
    const gone = view(answer(st), ui);
    assert.equal(gone.selected, "nNexus");
    assert.equal(gone.chooser, null);
    assert.equal(T.decide(gone, ui, "Down").ui.selected, "nCauldronLake");
});

// ---- section 3: the bar ---------------------------------------------------

t("bar: every input of section 3", () => {
    const look = a => T.bar(a, false, NOW).look;
    assert.equal(look(T.initial()), "off");
    for (const name of ["no-daemon", "in-use", "hung", "not-json"])
        assert.equal(look(failing(name)), "attention", name);
    for (const name of ["logged-out", "login-started", "key-expired", "machine-auth", "unknown", "nostate-health"])
        assert.equal(look(answer(STATES[name])), "attention", name);
    for (const name of ["health", "control-lost", "self-expiring", "exit-node-down", "urgent"])
        assert.equal(look(answer(overlay(name))), "attention", name);
    for (const name of ["self-far", "exit-node", "newer", "latest"])
        assert.equal(look(answer(overlay(name))), "on", name);
    for (const name of ["stopped", "starting", "nostate"])
        assert.equal(look(answer(STATES[name])), "off", name);
    assert.equal(look(running()), "on");
    // Peers offline, relayed, idle, expiring or expired are not counted.
    assert.equal(look(answer(fixture("peers"))), "on");
    // This computer's key already past while Running.
    const st = fixture("running");
    st.Self.KeyExpiry = "2026-11-15T12:00:00Z";
    assert.equal(look(answer(st)), "attention");
});

t("bar colours: foreground, comment grey, orange, purple while open", () => {
    assert.deepEqual(T.bar(running(), false, NOW), { look: "on", colour: "fg" });
    assert.deepEqual(T.bar(answer(STATES.stopped), false, NOW), { look: "off", colour: "dim" });
    assert.deepEqual(T.bar(failing("hung"), false, NOW), { look: "attention", colour: "orange" });
    assert.deepEqual(T.bar(failing("hung"), true, NOW), { look: "attention", colour: "purple" });
    assert.deepEqual(T.bar(running(), true, NOW), { look: "on", colour: "purple" });
});

t("light answers: same entry point, give the bar, keep the last full list as of its time", () => {
    const st = fixture("running");
    st.Peer = null;
    const light = T.read(call(st, true), T.initial(), NOW);
    assert.equal(light.state, 14);
    assert.equal(light.light, true);
    assert.equal(light.good, null);
    assert.equal(T.bar(light, false, NOW).look, "on");
    assert.deepEqual(view(light).groups, []);
    const after = T.read(call(st, true), lastGood(), NOW);
    assert.equal(after.good.at, NOW - 2 * MIN);
    const v = view(after);
    assert.equal(v.header.meta, "as of 11:58");
    assert.equal(v.live, false);
    assert.equal(rows(v).length, 5);
    const lost = clone(st);
    lost.Health = ["A warning."];
    assert.equal(T.bar(T.read(call(lost, true), lastGood(), NOW), false, NOW).look, "attention");
    const out = clone(STATES["logged-out"]);
    assert.deepEqual(view(T.read(call(out, true), lastGood(), NOW)).groups, []);
});

// ---- junk ------------------------------------------------------------------

t("junk inside a status: Peer null, no Self, odd fields", () => {
    const st = fixture("running");
    st.Peer = null;
    const v = view(answer(st));
    assert.deepEqual(v.groups, []);
    assert.equal(v.selected, "");
    delete st.Self;
    st.Health = "not a list";
    const w = view(answer(st));
    assert.equal(w.well, null);
    assert.deepEqual(w.strips, []);
    st.Peer = [1, 2];
    assert.deepEqual(view(answer(st)).groups, []);
    const p = fixture("running");
    p.Peer["nodekey:0002"].TailscaleIPs = "100.64.0.2";
    p.Peer["nodekey:0002"].Tags = null;
    assert.equal(row(view(answer(p)), "nNexus").line, "linux · no address");
});

console.log(`ok: ${n} tests`);
