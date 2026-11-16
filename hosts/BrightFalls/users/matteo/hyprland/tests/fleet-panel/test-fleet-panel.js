// The fleet panel's library (quickshell/fleet/fleet.js) against recorded
// desk-fleet lines in fixtures/ (one file per state of the panel, built from
// the helper's own example rows) and inline events.
// Run: node test-fleet-panel.js <directory holding fleet.js>
process.env.TZ = "UTC";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const F = require(path.join(path.resolve(process.argv[2]), "fleet.js"));
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

const NOW = Date.parse("2026-11-16T12:00:20.000Z");
function load(name, st) {
    let s = st || F.initial("running");
    for (const line of fs.readFileSync(path.join(__dirname, "fixtures", name + ".jsonl"), "utf8").split("\n"))
        if (line.trim())
            s = F.apply(s, JSON.parse(line));
    return s;
}
const view = (st, host, unfolded) => F.rowView(st.rows[host], !!unfolded, st.actions[host] || null, st.messages[host] || "");
const keyNames = (st, host) => F.keys(st.rows[host], st.actions[host] || null).map(k => k.key).join(" ");

t("single lines: helper missing, stopped, running", () => {
    assert.equal(F.single(F.initial("missing")), "The fleet helper (desk-fleet) was not found.");
    assert.equal(F.single(F.initial("stopped")), "The fleet helper (desk-fleet) stopped. Trying again.");
    assert.equal(F.single(F.initial("running")), "");
    assert.deepEqual(F.barView(F.initial("missing")), { count: 0, dim: true });
});

t("before hello: starting, no header age, dim bar", () => {
    const st = F.initial("running");
    assert.equal(F.checking(st), "Starting…");
    assert.equal(F.checked(st, NOW), "");
    assert.equal(F.liveText(st), "");
    assert.deepEqual(F.barView(st), { count: 0, dim: true });
    assert.deepEqual(F.order(st), []);
});

t("hero: order, header, pipeline, bar count", () => {
    const st = load("hero");
    assert.deepEqual(F.order(st), ["BrightFalls", "Nexus", "NightSprings", "CauldronLake"]);
    assert.equal(F.checking(st), "");
    assert.equal(F.checked(st, NOW), "checked 20s ago");
    assert.equal(F.liveText(st), "read only");
    assert.deepEqual(F.pipeline(st).parts, [
        { label: "master", text: "f4cf437", tone: "" },
        { label: "build", text: "building", tone: "cyan" },
        { label: "deploy", text: "073c52e · 1 behind", tone: "orange" }
    ]);
    assert.deepEqual(F.barView(st), { count: 1, dim: false });
});

t("hero rows: glyphs, this computer, mode pills, chips, runs colours", () => {
    const st = load("hero");
    const bf = view(st, "BrightFalls");
    assert.equal(bf.glyph, "▣");
    assert.equal(bf.local, true);
    assert.deepEqual(bf.mode, { text: "manual", auto: false });
    assert.deepEqual(bf.chip, { label: "Pending", colour: "purple", busy: false });
    assert.deepEqual(bf.lines.map(l => [l.label, l.tone]), [["runs", "yellow"], ["held", ""], ["boot", ""]]);
    assert.equal(keyNames(st, "BrightFalls"), "S B D M R T I");
    assert.equal(F.keys(st.rows.BrightFalls, null).find(k => k.key === "T").label, "terminal");
    const ns = view(st, "NightSprings");
    assert.equal(ns.glyph, "▭");
    assert.deepEqual(ns.mode, { text: "auto switch", auto: true });
    assert.equal(keyNames(st, "NightSprings"), "M T I");
    const cl = view(st, "CauldronLake");
    assert.equal(cl.dim, true);
    assert.equal(cl.mode, null);
    assert.deepEqual(cl.lines.map(l => l.label), ["ssh"]);
    assert.equal(keyNames(st, "CauldronLake"), "");
});

t("offline hosts go after online ones, in hello order", () => {
    let st = load("chips-1");
    assert.deepEqual(F.order(st), ["Host2", "Host3", "Host4", "Host1"]);
});

t("every chip: label, colour, counted, keys lit", () => {
    const st = ["chips-1", "chips-2", "chips-3", "chips-4"].reduce((s, f) => load(f, s), F.initial("running"));
    const want = {
        Host1: ["Offline", "dim", false, ""],
        Host2: ["No comin", "dim", false, "R T I"],
        Host3: ["Deploy failed", "red", true, "S D M R T I"],
        Host4: ["Build failed", "red", true, "M R T I"],
        Host5: ["Fetch failed", "red", true, "M R T I"],
        Host6: ["Suspended", "orange", false, "R T I"],
        Host7: ["Deploying", "cyan", false, "D T I"],
        Host8: ["Building", "cyan", false, "T I"],
        Host9: ["Pending", "purple", true, "S B D M R T I"],
        Host10: ["Testing", "pink", false, "D M R T I"],
        Host11: ["By hand", "yellow", false, "D M R T I"],
        Host12: ["Behind", "orange", true, "M R T I"],
        Host13: ["Reboot", "orange", true, "S D M R T I"],
        Host14: ["Reboot (kernel)", "orange", true, "M R T I"],
        Host15: ["Up to date", "green", false, "M R T I"]
    };
    for (const [host, [label, colour, counts, k]] of Object.entries(want)) {
        const v = view(st, host);
        assert.equal(v.chip.label, label, host);
        assert.equal(v.chip.colour, colour, host);
        assert.equal(st.rows[host].counts, counts, host);
        assert.equal(keyNames(st, host), k, host);
    }
    assert.equal(view(st, "Host7").chip.busy, true);
    assert.equal(view(st, "Host8").chip.busy, true);
    assert.equal(view(st, "Host9").chip.busy, false);
    // Red, Pending, Behind, Reboot and Reboot (kernel).
    assert.deepEqual(F.barView(st), { count: 7, dim: false });
});

t("the cases that used to read wrong", () => {
    const st = load("wrong");
    assert.deepEqual(view(st, "HandBuild").lines.map(l => l.label + " " + l.text), ["runs built by hand · xxxxxxx · not a comin system", "boot unknown", "comin 1111111 · deploy · last deployed 2d ago"]);
    assert.equal(view(st, "HandBuild").chip.label, "By hand");
    assert.equal(view(st, "HandMerged").lines[1].text, "073c52e · same system · S or B makes it comin's");
    assert.equal(keyNames(st, "HandMerged"), "S B M R T I");
    assert.equal(view(st, "OnTesting").lines[0].tone, "pink");
    assert.equal(view(st, "OnTesting").lines[1].text, "1111111 · deploy · reboot leaves testing");
    assert.deepEqual(view(st, "TestRejected").lines[1], { label: "test", text: "testing-TestRejected ignored: not on top of deploy", tone: "orange" });
    assert.equal(view(st, "TestBuilding").chip.busy, true);
    assert.equal(view(st, "SameSystem").lines[0].text, "f4cf437 · deploy · same system as 073c52e, switch 3h ago");
    assert.equal(keyNames(st, "TestingHeld"), "S D M R T I");
});

t("a many-line error folds to its first line; I unfolds it and the info", () => {
    const st = load("long");
    const folded = view(st, "LongError");
    assert.equal(folded.lines[1].text, "2222222 · error: … while evaluating the attribute 'config.system.build.toplevel' … (I for all)");
    assert.deepEqual(folded.info, []);
    const open = view(st, "LongError", true);
    assert.equal(open.lines[1].text, st.rows.LongError.lines[0].text);
    assert.ok(open.lines[1].text.split("\n").length === 5);
    assert.ok(keyNames(st, "LongError").includes("I"));
});

t("info lines: nested keys, lists one per line, nulls as a dash, empties left out", () => {
    const lines = F.infoLines({ a: "/x", b: null, c: { d: "1", e: {} }, f: ["one", "two"], g: [] });
    assert.deepEqual(lines, [
        { label: "a", value: "/x" },
        { label: "b", value: "—" },
        { label: "c d", value: "1" },
        { label: "f", value: "one" },
        { label: "f", value: "two" }
    ]);
    const st = load("chips-3");
    const v = view(st, "Host9", true);
    assert.ok(v.info.some(l => l.label === "deployment commit" && l.value === "1111111111111111111111111111111111111111"));
    assert.ok(v.info.some(l => l.label === "next_boot_why"));
});

t("actions: running with the last tail line, ok, failed with exit, sudo message", () => {
    const st = load("actions");
    assert.deepEqual(view(st, "Running").action, { text: "switch: running · setting up /etc...", tone: "", busy: true });
    assert.deepEqual(view(st, "Done").action, { text: "mode: ok", tone: "green", busy: false });
    assert.deepEqual(view(st, "Failed").action, { text: "switch: failed (exit 4) · switch-to-configuration exited with status 4", tone: "red", busy: false });
    const sudo = view(st, "SudoAsks");
    assert.equal(sudo.action.busy, true);
    assert.equal(sudo.message, "sudo on SudoAsks needs a password: type it in the terminal that opened.");
    assert.equal(view(st, "Running").message, "");
    for (const h of ["Running", "Done", "Failed", "SudoAsks"])
        assert.ok(keyNames(st, h).endsWith("A"), h);
    // The final event clears the message.
    const done = F.apply(st, { event: "action", id: 14, host: "SudoAsks", action: "reboot", state: "ok", tail: [], exit: 0 });
    assert.equal(done.messages.SudoAsks, undefined);
    assert.equal(view(done, "SudoAsks").action.text, "reboot: ok");
});

t("a running event keeps the tail it had; a started one clears it", () => {
    let st = load("actions");
    st = F.apply(st, { event: "action", id: 11, host: "Running", action: "switch", state: "running" });
    assert.equal(st.actions.Running.tail.length, 3);
    st = F.apply(st, { event: "action", id: 15, host: "Running", action: "switch", state: "started" });
    assert.deepEqual(st.actions.Running.tail, []);
});

t("refusals and diff/ssh/attach do not become the row's action", () => {
    const st = load("refusals", load("hero"));
    assert.deepEqual(st.actions, {});
});

t("footer texts for refusals and windows that failed", () => {
    const lines = fs.readFileSync(path.join(__dirname, "fixtures", "refusals.jsonl"), "utf8").trim().split("\n").map(l => F.footer(JSON.parse(l)));
    assert.deepEqual(lines, [
        "switch: refused, the helper is read-only.",
        "No output: nothing has run on Host1 yet.",
        "switch: refused, the held generation is 00000004-0000-4000-8000-000000000000 now.",
        "reboot: refused, an action is running on this host.",
        "diff: the window did not open (No such file or directory: 'ghostty')."
    ]);
    assert.equal(F.footer({ event: "action", id: 1, host: "H", action: "switch", state: "failed", exit: 1 }), "");
    assert.equal(F.footer({ event: "host" }), "");
});

t("the panel closes when a window opened or sudo wants a password, not on a refusal or failure", () => {
    for (const action of ["diff", "ssh", "attach"]) {
        assert.equal(F.closesPanel({ event: "action", id: 1, host: "H", action, state: "ok" }), true, action);
        assert.equal(F.closesPanel({ event: "action", id: 1, host: "H", action, state: "failed", reason: "x" }), false, action);
        assert.equal(F.closesPanel({ event: "action", id: 1, host: "H", action, state: "refused", reason: "offline" }), false, action);
    }
    for (const action of ["switch", "boot", "mode", "reboot"])
        assert.equal(F.closesPanel({ event: "action", id: 1, host: "H", action, state: "ok", tail: [], exit: 0 }), false, action);
    assert.equal(F.closesPanel({ event: "message", host: "H", kind: "sudo-password", text: "t" }), true);
    assert.equal(F.closesPanel({ event: "message", host: "H", kind: "other", text: "t" }), false);
    const lines = fs.readFileSync(path.join(__dirname, "fixtures", "refusals.jsonl"), "utf8").trim().split("\n").map(l => F.closesPanel(JSON.parse(l)));
    assert.deepEqual(lines, [false, false, false, false, false]);
    const sudo = fs.readFileSync(path.join(__dirname, "fixtures", "actions.jsonl"), "utf8").trim().split("\n").map(l => JSON.parse(l)).filter(F.closesPanel);
    assert.deepEqual(sudo.map(e => [e.event, e.host]), [["message", "SudoAsks"]]);
});

t("Esc in the footer: close, cancel a question, back from the mode chooser", () => {
    assert.equal(F.escLabel(null), "close");
    assert.equal(F.escLabel({ host: "H", what: "switch" }), "cancel");
    assert.equal(F.escLabel({ host: "H", what: "reboot" }), "cancel");
    assert.equal(F.escLabel({ host: "H", what: "mode" }), "back");
    const row = load("hero").rows.Nexus;
    assert.equal(F.question(row, "mode").keys.at(-1).label, F.escLabel({ host: "Nexus", what: "mode" }));
});

t("GitHub error: banner text, checking line, header still checking", () => {
    const st = load("github-error");
    assert.deepEqual(F.pipeline(st), { error: "GitHub: gh is not logged in. Hosts are still read; Behind cannot be judged." });
    assert.equal(F.checking(st), "Checking Nexus · NightSprings · CauldronLake…");
    assert.equal(F.checked(st, NOW), "checking…");
    assert.deepEqual(F.order(st), ["BrightFalls"]);
});

t("pipeline: passed, failed, older run, no run, ahead unknown", () => {
    const g = (over, run) => F.pipeline({ github: Object.assign({ state: "ok", master: "a".repeat(40), deploy: "a".repeat(40), ahead: 0, run: run === undefined ? { status: "completed", conclusion: "success", head_sha: "a".repeat(40) } : run }, over) }).parts;
    assert.deepEqual(g({}), [{ label: "master", text: "aaaaaaa", tone: "" }, { label: "build", text: "passed", tone: "green" }, { label: "deploy", text: "aaaaaaa", tone: "" }]);
    assert.deepEqual(g({}, { status: "completed", conclusion: "failure", head_sha: "b".repeat(40) })[1], { label: "build", text: "failure (bbbbbbb)", tone: "red" });
    assert.deepEqual(g({}, null)[1], { label: "build", text: "no run", tone: "" });
    assert.deepEqual(g({ ahead: null, deploy: "c".repeat(40) })[2], { label: "deploy", text: "ccccccc", tone: "" });
    assert.equal(F.pipeline({ github: null }), null);
});

t("checked: seconds, minutes, hours", () => {
    const st = F.apply(F.apply(F.initial("running"), { event: "hello", read_only: false, hosts: [] }), { event: "round", state: "done", at: "2026-11-16T12:00:00.000Z" });
    assert.equal(F.checked(st, NOW), "checked 20s ago");
    assert.equal(F.checked(st, NOW + 120000), "checked 2m ago");
    assert.equal(F.checked(st, NOW + 7200000), "checked 2h ago");
    assert.equal(F.liveText(st), "live");
});

t("questions: switch names what is replaced; testing and same-system wording", () => {
    const hero = load("hero");
    assert.deepEqual(F.question(hero.rows.BrightFalls, "switch"), {
        title: "Switch BrightFalls to 2222222 now?",
        text: "It replaces a system built by hand. Changed services restart, and it becomes the next boot.",
        keys: [{ key: "Enter", label: "switch", hl: true }, { key: "D", label: "diff first" }, { key: "Esc", label: "cancel" }]
    });
    const wrong = load("wrong");
    const merged = F.question(wrong.rows.HandMerged, "switch");
    assert.equal(merged.title, "Switch HandMerged to 073c52e now?");
    assert.equal(merged.text, "Nothing that runs changes; comin records it as deployed.");
    assert.deepEqual(merged.keys.map(k => k.key), ["Enter", "Esc"]);
    assert.equal(F.question(wrong.rows.TestingHeld, "switch").text, "comin runs a testing generation with test: live until the next reboot, never the next boot.");
    const chips = load("chips-1", load("chips-4"));
    assert.equal(F.question(chips.rows.Host3, "switch").title, "Retry the deploy of 2222222 on Host3 now?");
    assert.equal(F.question(chips.rows.Host13, "switch").title, "Switch Host13 to 2222222 now?");
});

t("questions: a switch away from testing names the branch", () => {
    const st = load("long");
    const row = Object.assign({}, st.rows.LongBranch, { actions: Object.assign({}, st.rows.LongBranch.actions, { switch: { allowed: true, target: "staged", generation: null } }) });
    assert.match(F.question(row, "switch").text, /^It replaces 7777777 from testing-Nexus-a-rather-long-branch-name/);
});

t("questions: reboot says when it leaves testing, and what boots", () => {
    const wrong = load("wrong");
    assert.deepEqual(F.question(wrong.rows.OnTesting, "reboot"), {
        title: "Reboot OnTesting now?",
        text: "It comes back on 1111111 and leaves the testing branch. If sudo asks for a password, a terminal opens for it.",
        keys: [{ key: "Enter", label: "reboot", danger: true }, { key: "Esc", label: "cancel" }]
    });
    const hero = load("hero");
    assert.deepEqual(F.question(hero.rows.BrightFalls, "reboot"), {
        title: "Reboot this computer now?",
        text: "Which system it boots is not known (I says why). This computer restarts at once.",
        keys: [{ key: "Enter", label: "reboot", danger: true }, { key: "Esc", label: "cancel" }]
    });
    const st = load("chips-4");
    assert.equal(F.question(st.rows.Host13, "reboot").text, "It comes back on 2222222. If sudo asks for a password, a terminal opens for it.");
});

t("mode chooser: values numbered 1 2 3, current ticked, macOS 1 and 3", () => {
    const hero = load("hero");
    assert.deepEqual(F.question(hero.rows.Nexus, "mode").keys.map(k => [k.key, k.label]), [["1", "manual ✓"], ["2", "automatic boot"], ["3", "automatic switch"], ["Esc", "back"]]);
    assert.deepEqual(F.question(hero.rows.NightSprings, "mode").keys.map(k => [k.key, k.label]), [["1", "manual"], ["3", "automatic switch ✓"], ["Esc", "back"]]);
});

t("keys: S asks, Enter sends the generation as given, D diffs first, Esc cancels", () => {
    const row = load("hero").rows.BrightFalls;
    assert.deepEqual(F.decide(row, null, "S", ""), { kind: "ask", what: "switch" });
    const ask = { host: "BrightFalls", what: "switch" };
    assert.deepEqual(F.decide(row, ask, "Enter", ""), { kind: "send", cmd: { cmd: "switch", host: "BrightFalls", generation: "00000002-0000-4000-8000-000000000000" } });
    assert.deepEqual(F.decide(row, ask, "D", ""), { kind: "send", cmd: { cmd: "diff", host: "BrightFalls" }, keepAsk: true });
    assert.deepEqual(F.decide(row, ask, "Esc", ""), { kind: "cancel" });
    assert.deepEqual(F.decide(row, ask, "R", ""), { kind: "none" });
});

t("keys: a switch with no generation omits it", () => {
    const row = load("chips-4").rows.Host13;
    assert.deepEqual(F.decide(row, { host: "Host13", what: "switch" }, "Enter", ""), { kind: "send", cmd: { cmd: "switch", host: "Host13" } });
});

t("keys: B sends at once, R asks, M chooses, T and A send", () => {
    const st = load("hero");
    const row = st.rows.BrightFalls;
    assert.deepEqual(F.decide(row, null, "B", ""), { kind: "send", cmd: { cmd: "boot", host: "BrightFalls", generation: "00000002-0000-4000-8000-000000000000" } });
    assert.deepEqual(F.decide(row, null, "R", ""), { kind: "ask", what: "reboot" });
    assert.deepEqual(F.decide(row, { host: "BrightFalls", what: "reboot" }, "Enter", ""), { kind: "send", cmd: { cmd: "reboot", host: "BrightFalls" } });
    assert.deepEqual(F.decide(row, null, "M", ""), { kind: "ask", what: "mode" });
    const mode = { host: "BrightFalls", what: "mode" };
    assert.deepEqual(F.decide(row, mode, "3", ""), { kind: "send", cmd: { cmd: "mode", host: "BrightFalls", value: "switch" } });
    assert.deepEqual(F.decide(row, mode, "1", ""), { kind: "cancel" });
    assert.deepEqual(F.decide(st.rows.NightSprings, { host: "NightSprings", what: "mode" }, "2", ""), { kind: "none" });
    assert.deepEqual(F.decide(row, null, "T", ""), { kind: "send", cmd: { cmd: "ssh", host: "BrightFalls" } });
    assert.deepEqual(F.decide(row, null, "A", ""), { kind: "send", cmd: { cmd: "attach", host: "BrightFalls" } });
    assert.deepEqual(F.decide(row, null, "I", ""), { kind: "info" });
});

t("keys: not allowed shows the helper's reason; O, F5, Esc", () => {
    const st = load("hero");
    assert.deepEqual(F.decide(st.rows.Nexus, null, "S", ""), { kind: "say", text: "switch: nothing held, staged or failed" });
    assert.deepEqual(F.decide(st.rows.NightSprings, null, "B", ""), { kind: "say", text: "next boot: macOS has no boot" });
    assert.deepEqual(F.decide(st.rows.CauldronLake, null, "T", ""), { kind: "say", text: "ssh: offline" });
    assert.deepEqual(F.decide(st.rows.Nexus, null, "O", "https://x"), { kind: "open", url: "https://x" });
    assert.deepEqual(F.decide(st.rows.Nexus, null, "O", ""), { kind: "say", text: "No build run to open." });
    assert.deepEqual(F.decide(null, null, "F5", ""), { kind: "refresh" });
    assert.deepEqual(F.decide(st.rows.Nexus, null, "Esc", ""), { kind: "close" });
    assert.deepEqual(F.decide(null, null, "S", ""), { kind: "none" });
});

t("keys: a question whose action went away says why and closes", () => {
    const st = load("hero");
    assert.deepEqual(F.decide(st.rows.Nexus, { host: "Nexus", what: "switch" }, "Enter", ""), { kind: "say", text: "switch: nothing held, staged or failed", cancel: true });
});

t("navigation: up, down, home, end, clamps, unknown selection", () => {
    const names = ["A", "B", "C"];
    assert.equal(F.move(names, "B", "Up"), "A");
    assert.equal(F.move(names, "A", "Up"), "A");
    assert.equal(F.move(names, "B", "Down"), "C");
    assert.equal(F.move(names, "C", "Down"), "C");
    assert.equal(F.move(names, "B", "Home"), "A");
    assert.equal(F.move(names, "A", "End"), "C");
    assert.equal(F.move(names, "gone", "Down"), "A");
    assert.equal(F.move([], "A", "Down"), "");
});

t("sent commands are kept until their final event", () => {
    let st = F.sent(F.initial("running"), 7, { cmd: "diff", host: "H" });
    assert.deepEqual(st.commands[7], { cmd: "diff", host: "H" });
    st = F.apply(st, { event: "action", id: 7, host: "H", action: "diff", state: "ok" });
    assert.equal(st.commands[7], undefined);
});

console.log(`ok: ${n} tests`);
