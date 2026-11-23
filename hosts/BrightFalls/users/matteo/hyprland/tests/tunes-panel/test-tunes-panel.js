// The tunes panel's library (quickshell/tunes/tunes.js) against invented
// desk-tunes snapshot lines, hand-written in the service's format in
// fixtures/ (a "@-N" or "@+N" time is N seconds before or after the base
// time the test applies the file at) and built here.
// Run: node test-tunes-panel.js <path to tunes.js>
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const T = require(path.resolve(process.argv[2]));
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

const NOW = 1795390000;

function events(name, base) {
    const text = fs.readFileSync(path.join(__dirname, "fixtures", name + ".jsonl"), "utf8");
    return text.split("\n").filter(l => l.trim() !== "").map(l => JSON.parse(l.replace(/"@([+-]\d+)"/g, (m, s) => String(base + Number(s)))));
}
function load(name, base, st) {
    return events(name, base).reduce((s, ev) => T.apply(s, ev, base), st || T.initial());
}
// A fixture's state with snapshot fields changed.
function edit(name, changes) {
    const st = load(name, NOW);
    st.snap = Object.assign({}, st.snap, changes);
    return st;
}
const ui = (st, now, changes) => Object.assign(T.initialUi(st, now), changes || {});
const viewAt = (name, now) => {
    const st = load(name, NOW);
    return T.view(st, ui(st, now === undefined ? NOW : now));
};
const hintsOf = (name, changes) => {
    const st = load(name, NOW);
    return T.hints(st, ui(st, NOW, changes));
};
const press = (st, u, list) => list.reduce((r, k) => T.key(r.ui, st, k, false), { ui: u, effect: { kind: "none", cmd: null } });
const rows = p => p.next.rows.map(r => [r.n, r.name, r.sub, r.right]);
const lines = p => p.composer.lines.map(l => l.pre + l.em + l.post + (l.right ? ` | ${l.right}` : ""));
const fixtures = () => fs.readdirSync(path.join(__dirname, "fixtures")).map(f => f.replace(/\.jsonl$/, ""));

t("formatting", () => {
    assert.equal(T.clock(0), "0:00");
    assert.equal(T.clock(84), "1:24");
    assert.equal(T.clock(172.4), "2:52");
    assert.equal(T.clock(59.99), "0:59");
    assert.equal(T.clock(725), "12:05");
    assert.equal(T.clock(null), "–:––");
    assert.equal(T.clock(-1), "–:––");
    const GIB = 1073741824;
    assert.equal(T.gib(6 * GIB), "6 GiB");
    assert.equal(T.gib(19.3 * GIB), "19.3 GiB");
    assert.equal(T.gib(7.57 * GIB, 2), "7.57 GiB");
    assert.equal(T.gib(226.4 * GIB), "226 GiB");
    assert.equal(T.gib(null), "");
    assert.equal(T.rate(28400000), "28 MB/s");
    assert.equal(T.rate(640000), "640 kB/s");
    assert.equal(T.elapsed(65), "1 min 5 s");
});

t("waveform columns: odd dot counts from 1 to 9, 78 of them", () => {
    assert.equal(T.ROWS, 9);
    const flat = T.waveColumns([]);
    assert.equal(flat.length, T.COLS);
    assert.ok(flat.every(c => c === 1));
    const cols = T.waveColumns(Array.from({ length: 78 }, (_, i) => i / 77));
    assert.ok(cols.every(c => c % 2 === 1 && c >= 1 && c <= T.ROWS));
    assert.deepEqual([cols[0], cols[77]], [1, 9]);
    // 0.5 * 9 = 4.5 rounds to 5; 0.4 * 9 = 3.6 rounds to 4, made odd: 3.
    assert.equal(T.waveColumns(new Array(78).fill(0.5))[0], 5);
    assert.equal(T.waveColumns(new Array(78).fill(0.4))[0], 3);
    const half = T.waveColumns([0, 1]);
    assert.deepEqual([half[0], half[38], half[39], half[77]], [1, 1, 9, 9]);
});

t("the service's lines: which apply, which reset the back-off", () => {
    const st = T.initial();
    assert.equal(T.apply(st, null, NOW), st);
    assert.equal(T.apply(st, { event: "error", text: "x" }, NOW), st);
    assert.equal(T.healthy({ event: "state", v: 1 }), true);
    assert.equal(T.healthy({ event: "error", text: "bad line" }), true);
    assert.equal(T.healthy({ event: "state", v: 2 }), false);
    assert.equal(T.healthy(null), false);
    const s = load("20-session", NOW);
    assert.equal(s.link, "up");
    assert.equal(s.snap.genre, "synthwave");
    assert.equal(s.snap.tune.name, "Neon Harbour");
    assert.equal(s.snap.tune.n, undefined);
});

t("a protocol version other than 1", () => {
    const v = viewAt("18-protocol-v2");
    assert.equal(v.kind, "old");
    assert.equal(v.setup.detail, "It speaks version 2 of the protocol; this panel reads version 1.");
    assert.deepEqual(hintsOf("18-protocol-v2"), [["Esc", "close"]]);
    assert.deepEqual(T.barView(load("18-protocol-v2", NOW)), { tone: "dim", text: "", dot: "" });
});

t("the link: connecting, not installed, not running (exit 3), closed (other exits)", () => {
    let st = T.initial();
    assert.equal(T.view(st, ui(st, NOW)).setup.title, "Connecting to the tunes service…");
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
    st = T.linkLost(T.initial(), "missing", null, "", NOW + 8);
    assert.equal(T.view(st, ui(st, NOW)).setup.detail, "desk-tunes is not on PATH. Trying again in 8 s.");
    st = T.linkLost(load("05-queue-full", NOW), "exited", 3, "the tunes service is not running", NOW + 7.5);
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "down");
    assert.deepEqual(v.setup.rows, [["unit", "desk-tunes.service"], ["last line", "the tunes service is not running"]]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["R", "try now"], ["Esc", "close"]]);
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "" });
    assert.equal(T.globalScrap(st, NOW), null);
    assert.equal(T.undoLine(st, ui(st, NOW)), "");
    st = T.linkLost(T.initial(), "exited", 1, "", NOW + 16);
    assert.equal(T.view(st, ui(st, NOW)).kind, "lost");
    assert.deepEqual(T.key(ui(st, NOW), st, "R", false).effect, { kind: "reattach", cmd: null });
    assert.equal(T.key(ui(st, NOW), st, "R", true).effect.kind, "none");
    assert.equal(T.linkLost(st, "back").link, "connecting");
});

t("not set up, downloading, a download that stopped: as built", () => {
    let v = viewAt("01-not-set-up");
    assert.equal(v.kind, "setup");
    assert.deepEqual(v.setup.rows, [["download", "7.57 GiB"], ["free on disk", "226 GiB"], ["memory while composing", "about 6 GiB of RAM"]]);
    assert.deepEqual(hintsOf("01-not-set-up"), [["Enter", "download"], ["Esc", "close"]]);
    v = viewAt("02-downloading");
    assert.equal(v.setup.detail, "File 2 of 4: the language model.");
    assert.deepEqual(v.setup.rows, [["downloaded", "2.9 of 7.57 GiB"], ["speed", "28 MB/s"]]);
    const dl = load("02-downloading", NOW);
    assert.deepEqual(T.key(ui(dl, NOW), dl, "C", false).effect.cmd, { cmd: "cancel_download" });
    assert.deepEqual(T.barView(dl), { tone: "dim", text: "", dot: "cyan" });
    v = viewAt("03-download-failed");
    assert.equal(v.setup.detail, "checksum mismatch on the language model. Finished files are kept.");
    assert.deepEqual(hintsOf("03-download-failed"), [["Enter", "resume"], ["Esc", "close"]]);
});

t("the chooser, first open: no genre yet", () => {
    const st = load("04-chooser-first", NOW);
    const u = ui(st, NOW);
    const v = T.view(st, u);
    assert.equal(v.kind, "chooser");
    assert.equal(v.chooser.title, "Genre");
    assert.equal(v.chooser.chip, "Enter plays what is kept");
    assert.deepEqual(v.chooser.cells.map(c => [c.name, c.sub, c.sel, c.cur]).slice(0, 5), [
        ["Lo-fi", "31 kept", true, false], ["Ambient", "12 kept", false, false], ["Synthwave", "none yet", false, false],
        ["Deep house", "4 kept", false, false], ["Jazz", "14 kept", false, false]
    ]);
    assert.deepEqual(T.hints(st, u), [["←↑↓→", "move"], ["Enter", "play Lo-fi"], ["E", "edit"], ["A", "add"], ["D", "delete"], ["Esc", "close"]]);
    const sel = list => press(st, u, list).ui.sel;
    assert.equal(sel(["Right"]), 1);
    assert.equal(sel(["Up"]), 0);
    // Nine genres, then "+ New genre" as the tenth cell.
    assert.equal(sel(["Down", "Down", "Down"]), 9);
    assert.equal(sel(["Down", "Down", "Down", "Down", "Right"]), 9);
    assert.equal(T.key(u, st, "Down", true).ui.sel, 3);
    const moved = press(st, u, ["Down", "Right"]);
    assert.deepEqual(T.hints(st, moved.ui)[1], ["Enter", "play Jazz"]);
    const r = T.key(moved.ui, st, "Enter", false);
    assert.deepEqual(r.effect, { kind: "send", cmd: { cmd: "genre", id: "jazz" } });
    assert.equal(T.key(moved.ui, st, "Enter", true).effect.kind, "none");
    assert.deepEqual(T.pick(u, st, 7).effect.cmd, { cmd: "genre", id: "postrock" });
    assert.equal(T.pick(u, st, 99).effect.kind, "none");
    assert.equal(T.needsTick(st, u), false);
});

t("the chooser: the selected genre says playing now, the cursor opens on it, Enter there goes back", () => {
    const st = load("05-queue-full", NOW);
    const g = T.key(ui(st, NOW), st, "G", false);
    assert.equal(g.ui.mode, "chooser");
    assert.equal(g.ui.sel, 4);
    const cells = T.view(st, g.ui).chooser.cells;
    assert.deepEqual(cells[4], { name: "Jazz", sub: "playing now", sel: true, cur: true });
    assert.deepEqual(cells.filter(c => c.cur).length, 1);
    assert.deepEqual(T.hints(st, g.ui), [["←↑↓→", "move"], ["Enter", "back to Jazz"], ["E", "edit"], ["A", "add"], ["D", "delete"], ["Esc", "back"]]);
    const back = T.key(g.ui, st, "Enter", false);
    assert.deepEqual([back.ui.mode, back.effect.kind], ["player", "none"]);
    assert.deepEqual(T.hints(st, T.key(g.ui, st, "Left", false).ui)[1], ["Enter", "play Deep house"]);
    assert.equal(T.key(g.ui, st, "Esc", false).ui.mode, "player");
    // With nothing playing the selected genre says "selected", and picking it
    // starts nothing.
    const quiet = load("08-nothing-kept", NOW);
    const q = T.key(ui(quiet, NOW), quiet, "G", false).ui;
    assert.equal(T.view(quiet, q).chooser.cells[2].sub, "selected");
    // Paused: "paused", not "playing now".
    const paused = load("17-paused", NOW);
    assert.equal(T.view(paused, T.key(ui(paused, NOW), paused, "G", false).ui).chooser.cells[4].sub, "paused");
    assert.deepEqual(T.pick(q, quiet, 2).effect, { kind: "none", cmd: null });
    assert.equal(T.needsTick(st, g.ui), false);
});

t("queue full: the composer rests", () => {
    const st = load("05-queue-full", NOW);
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "player");
    const p = v.player;
    assert.equal(p.strip, null);
    assert.deepEqual([p.now.head, p.now.name, p.now.nameTone, p.now.meta], ["Jazz", "Lazy Avenue", "normal", "139 BPM · C major"]);
    assert.deepEqual(p.now.time, { left: "2:25", leftTone: "soft", right: "2:57" });
    assert.equal(p.now.wave.cols.length, 78);
    assert.ok(p.now.wave.cols.every(c => c <= 9));
    assert.equal(p.now.wave.played, Math.floor(145 / 177 * 78));
    assert.deepEqual([p.now.main, p.now.mainLit, p.now.nextLit], ["pause", true, true]);
    assert.equal(p.next.head, "2 ready");
    assert.deepEqual(rows(p), [["", "Brass Lantern", "112 BPM · F major", "2:54"], ["", "Quiet Ledger", "96 BPM · D minor", "2:49"]]);
    assert.ok(p.next.rows.every(r => r.kind === "tune" && !r.sel));
    assert.deepEqual([p.composer.on, p.composer.label], [true, "on"]);
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | resting, queue is full"]);
    assert.equal(p.composer.lines[0].em, "Jazz");
    assert.equal(p.composer.lines[0].rightTone, "green");
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["N", "next"], ["S", "shuffle"], ["L", "repeat one"], ["Y", "share"], ["X", "scrap Lazy Avenue"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    const u = ui(st, NOW);
    assert.deepEqual(T.key(u, st, "Space", false).effect.cmd, { cmd: "toggle" });
    assert.deepEqual(T.key(u, st, "N", false).effect.cmd, { cmd: "next" });
    assert.deepEqual(T.key(u, st, "C", false).effect.cmd, { cmd: "compose", on: false });
    assert.equal(T.key(u, st, "Z", false).effect.kind, "none");
    assert.equal(T.key(u, st, "R", false).effect.kind, "none");
    assert.equal(T.undoLine(st, u), "");
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Jazz", dot: "" });
    assert.equal(T.needsTick(st, u), true);
});

t("the first tune of a genre: being rendered, with an estimate", () => {
    const st = load("06-first-tune", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual([p.now.head, p.now.name, p.now.nameTone, p.now.meta], ["Jazz", "Nothing yet", "soft", "The first tune starts by itself when it is ready."]);
    assert.deepEqual([p.now.wave, p.now.time, p.now.mainLit, p.now.nextLit], [null, null, false, false]);
    assert.equal(p.next.head, "0 ready");
    // 58 s expected, 18 s spent: 40 s left.
    assert.deepEqual(rows(p), [["", "Being rendered", "about 0:40 left · written in 1:04", "composing"], ["", "Not started", "after the one above", ""]]);
    const job = p.next.rows[0];
    assert.deepEqual([job.kind, job.nTone, job.rightTone], ["job", "cyan", "cyan"]);
    assert.ok(Math.abs(job.bar - 18 / 58) < 1e-9);
    assert.equal(p.next.rows[1].kind, "placeholder");
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | using 3.9 GiB of RAM", "ACE-Step 1.5 Turbo · 4B Q8 · Radeon 780M"]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["S", "shuffle"], ["L", "repeat one"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    assert.equal(T.key(ui(st, NOW), st, "Space", false).effect.kind, "none");
    assert.equal(T.key(ui(st, NOW), st, "X", false).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "cyan" });
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
});

t("the job row: the time left, never negative, never longer than the estimate", () => {
    const st = load("10-writing", NOW);
    const sub = now => T.view(st, ui(st, now)).player.next.rows[0].sub;
    const bar = now => T.view(st, ui(st, now)).player.next.rows[0].bar;
    // 120 s expected (the writing median), 50 s spent.
    assert.equal(sub(NOW), "about 1:10 left");
    assert.equal(sub(NOW + 3), "about 1:10 left");
    assert.equal(sub(NOW + 6), "about 1:00 left");
    assert.equal(sub(NOW + 68), "about 0:10 left");
    assert.equal(sub(NOW + 69.9), "about 0:10 left");
    assert.equal(sub(NOW + 70), "any moment now");
    assert.equal(sub(NOW + 500), "any moment now");
    assert.equal(bar(NOW + 500), 1);
    // A clock behind the job's start: the whole estimate, no more.
    assert.equal(sub(NOW - 200), "about 2:00 left");
    assert.equal(bar(NOW - 200), 0);
    // No estimate: the stage and the time spent.
    const none = load("22-writing-again", NOW);
    const r = T.view(none, ui(none, NOW + 5)).player.next.rows[0];
    assert.deepEqual([r.name, r.sub, r.bar], ["Being written", "0:35 so far", null]);
    // No start time either.
    const bare = edit("22-writing-again", { job: { stage: "rendering", started: null, expect: null, written: 64 } });
    assert.equal(T.view(bare, ui(bare, NOW)).player.next.rows[0].sub, "written in 1:04");
});

t("the placeholder rows: only with the switch on, up to ahead", () => {
    const p = viewAt("10-writing").player;
    assert.deepEqual(rows(p), [["", "Being written", "about 1:10 left", "composing"], ["", "Not started", "after the one above", ""]]);
    assert.deepEqual(p.next.rows.map(r => r.nameTone), ["soft", "dim"]);
    // Held with one ready: one placeholder, with no job above it.
    assert.deepEqual(rows(viewAt("12-held-game").player), [["", "Dusty Notebook", "88 BPM · A major", "2:52"], ["", "Not started", "", ""]]);
    // Nothing ready and no job: two.
    assert.deepEqual(rows(viewAt("13-held-memory").player).map(r => r[1]), ["Not started", "Not started"]);
    // ahead from the snapshot.
    const three = edit("13-held-memory", { ahead: 3 });
    assert.equal(T.view(three, ui(three, NOW)).player.next.rows.length, 3);
    // Off: none.
    assert.deepEqual(rows(viewAt("08-nothing-kept").player), []);
    assert.deepEqual(rows(viewAt("07-composer-off-kept").player), [[1, "Lazy Avenue", "139 BPM · C major", "2:57"]]);
    // A job held by the snapshot while the switch is off is not drawn.
    const off = edit("10-writing", { composing: false });
    assert.deepEqual(rows(T.view(off, ui(off, NOW)).player), []);
});

t("composer off, kept tunes playing", () => {
    const st = load("07-composer-off-kept", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual([p.now.head, p.now.name, p.now.meta], ["Jazz · kept tunes", "Brass Lantern", "112 BPM · F major"]);
    assert.deepEqual(p.now.time, { left: "0:35", leftTone: "soft", right: "2:54" });
    assert.equal(p.next.head, "from 14 kept, shuffled");
    assert.deepEqual([p.composer.on, p.composer.label], [false, "off"]);
    assert.deepEqual(lines(p), ["On, it makes new Jazz and keeps 2 ahead."]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["N", "next"], ["S", "shuffle"], ["L", "repeat one"], ["Y", "share"], ["X", "scrap Brass Lantern"], ["C", "composer on"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "C", false).effect.cmd, { cmd: "compose", on: true });
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Jazz", dot: "" });
    const lofi = viewAt("09-kept-tunes").player;
    assert.deepEqual([lofi.now.head, lofi.next.head], ["Lo-fi · kept tunes", "from 31 kept, shuffled"]);
    assert.deepEqual(lines(lofi), ["On, it makes new Lo-fi and keeps 2 ahead."]);
});

t("a kept tune playing with a new one ready: the heading counts the new one", () => {
    const st = load("25-kept-playing-new-ready", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.equal(p.now.head, "Jazz · kept tunes");
    assert.equal(p.next.head, "1 ready");
    assert.deepEqual(rows(p).map(r => r[1]), ["Paper Kite", "Being written"]);
    // Also when a service says kept_playing with a new tune first in line.
    const old = edit("25-kept-playing-new-ready", { keptPlaying: true });
    assert.equal(T.view(old, ui(old, NOW)).player.next.head, "1 ready");
    // An undone kept tune first in line: still the kept heading.
    const undone = edit("25-kept-playing-new-ready", { keptPlaying: true, ready: 0, queue: [Object.assign({}, st.snap.queue[0], { kept: true })] });
    assert.equal(T.view(undone, ui(undone, NOW)).player.next.head, "from 14 kept, shuffled");
});

t("a genre with nothing kept: nothing happens by itself", () => {
    const st = load("08-nothing-kept", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual([p.now.head, p.now.name, p.now.nameTone, p.now.meta], ["Synthwave", "No Synthwave tunes yet", "soft", "Turn the composer on to make some."]);
    assert.deepEqual([p.now.mainLit, p.now.nextLit, p.now.wave], [false, false, null]);
    assert.equal(p.next.head, "nothing");
    // expect: 62 + 58 s is 2 min.
    assert.deepEqual(lines(p), ["On, it makes Synthwave and keeps 2 ahead.", "A tune takes about 2 min and 6 GiB of RAM while it is made."]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["S", "shuffle"], ["L", "repeat one"], ["C", "composer on"], ["G", "genre"], ["Esc", "close"]]);
    // Without the medians, only the memory.
    const fresh = edit("08-nothing-kept", { expect: null });
    assert.deepEqual(lines(T.view(fresh, ui(fresh, NOW)).player)[1], "A tune takes about 6 GiB of RAM while it is made.");
    // Minutes rounded, at least one.
    const quick = edit("08-nothing-kept", { expect: { writing: 10, rendering: 5 } });
    assert.equal(lines(T.view(quick, ui(quick, NOW)).player)[1], "A tune takes about 1 min and 6 GiB of RAM while it is made.");
    const slow = load("08-nothing-kept", NOW);
    const ev = events("08-nothing-kept", NOW)[0];
    ev.expect = { writing_s: 100, rendering_s: 95 };
    assert.equal(lines(T.view(T.apply(slow, ev, NOW), ui(slow, NOW)).player)[1], "A tune takes about 3 min and 6 GiB of RAM while it is made.");
    ev.expect = { writing_s: 100 };
    assert.equal(T.apply(slow, ev, NOW).snap.expect, null);
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
});

t("queue selection: Up/Down, clearing, Enter plays i, X scraps i, the hint names the tune", () => {
    const st = load("05-queue-full", NOW);
    const u = ui(st, NOW);
    assert.equal(u.row, null);
    const d1 = T.key(u, st, "Down", false).ui;
    assert.deepEqual(d1.row, { kind: "queue", i: 0, name: "Brass Lantern", file: "" });
    assert.deepEqual(T.view(st, d1).player.next.rows.map(r => r.sel), [true, false]);
    const d2 = press(st, u, ["Down", "Down"]).ui;
    assert.equal(d2.row.i, 1);
    // Past the last row it stays; a held arrow moves.
    assert.equal(press(st, u, ["Down", "Down", "Down", "Down"]).ui.row.i, 1);
    assert.equal(T.key(d1, st, "Down", true).ui.row.i, 1);
    // Up from the first row clears; Up with nothing selected stays clear.
    assert.equal(T.key(d1, st, "Up", false).ui.row, null);
    assert.equal(T.key(u, st, "Up", false).ui.row, null);
    assert.equal(T.key(d2, st, "Up", false).ui.row.i, 0);
    assert.deepEqual(T.hints(st, d2), [["↑↓", "select"], ["Enter", "play it now"], ["X", "scrap Quiet Ledger"], ["Y", "share"], ["Space", "pause"], ["Esc", "close"]]);
    const play = T.key(d2, st, "Enter", false);
    assert.deepEqual(play.effect.cmd, { cmd: "play", i: 1, name: "Quiet Ledger" });
    assert.equal(play.ui.row, null);
    const scrap = T.key(d2, st, "X", false);
    assert.deepEqual(scrap.effect.cmd, { cmd: "scrap", i: 1, name: "Quiet Ledger" });
    assert.equal(scrap.ui.row, null);
    // Held Enter and X act once.
    assert.equal(T.key(d2, st, "Enter", true).effect.kind, "none");
    assert.equal(T.key(d2, st, "X", true).effect.kind, "none");
    // Keys not named in the selected footer still act.
    assert.deepEqual(T.key(d2, st, "N", false).effect.cmd, { cmd: "next" });
    assert.deepEqual(T.key(d2, st, "C", false).effect.cmd, { cmd: "compose", on: false });
    assert.equal(T.key(d2, st, "G", false).ui.mode, "chooser");
    // The selection follows its tune when the head is played...
    const moved = edit("05-queue-full", { queue: [st.snap.queue[1]], ready: 1 });
    assert.deepEqual(T.view(moved, d2).player.next.rows.filter(r => r.kind === "tune").map(r => r.sel), [true]);
    assert.deepEqual(T.key(d2, moved, "X", false).effect.cmd, { cmd: "scrap", i: 0, name: "Quiet Ledger" });
    // ...and is gone with it.
    const gone = edit("05-queue-full", { queue: [st.snap.queue[0]], ready: 1 });
    assert.deepEqual(T.view(gone, d2).player.next.rows.filter(r => r.kind === "tune").map(r => r.sel), [false]);
    assert.deepEqual(T.key(d2, gone, "X", false).effect.cmd, { cmd: "scrap", name: "Lazy Avenue" });
    assert.equal(T.key(d2, gone, "Enter", false).effect.kind, "none");
    // A kept entry named by its file, then by its title once read: the
    // selection stays on it, and the commands name it as it is now.
    const FILE = "20260105-100000-70bpm-G-major";
    const unread = edit("09-kept-tunes", { queue: [{ name: FILE, file: FILE, bpm: 70, key: "G major", length: null, kept: true }] });
    const k = T.key(ui(unread, NOW), unread, "Down", false).ui;
    assert.deepEqual(k.row, { kind: "queue", i: 0, name: FILE, file: FILE });
    const read = edit("09-kept-tunes", { queue: [{ name: "Invented Hall", file: FILE, bpm: 70, key: "G major", length: 90, kept: true }] });
    assert.deepEqual(T.view(read, k).player.next.rows.map(r => r.sel), [true]);
    assert.deepEqual(T.key(k, read, "X", false).effect.cmd, { cmd: "scrap", i: 0, name: "Invented Hall" });
    // An empty queue: the arrows do nothing.
    const empty = load("08-nothing-kept", NOW);
    assert.equal(T.key(ui(empty, NOW), empty, "Down", false).ui.row, null);
});

t("the job row can be selected and scrapped; Enter does nothing on it", () => {
    const st = load("11-after-scrap", NOW);
    const job = press(st, ui(st, NOW), ["Down", "Down"]).ui;
    assert.deepEqual(job.row, { kind: "job" });
    assert.deepEqual(T.view(st, job).player.next.rows.map(r => r.sel), [false, true]);
    assert.deepEqual(T.hints(st, job), [["↑↓", "select"], ["X", "scrap the tune being written"], ["Space", "pause"], ["Esc", "close"]]);
    assert.deepEqual(T.key(job, st, "X", false).effect.cmd, { cmd: "scrap", job: true });
    assert.equal(T.key(job, st, "Enter", false).effect.kind, "none");
    assert.equal(press(st, job, ["Down"]).ui.row.kind, "job");
    // The job finished: the selection is gone.
    const done = edit("11-after-scrap", { job: null });
    assert.equal(T.key(job, done, "X", false).effect.cmd.cmd, "scrap");
    assert.equal(T.key(job, done, "X", false).effect.cmd.job, undefined);
    const r = load("06-first-tune", NOW);
    assert.deepEqual(T.hints(r, T.key(ui(r, NOW), r, "Down", false).ui)[1], ["X", "scrap the tune being rendered"]);
});

t("X with no selection: the playing tune, or nothing", () => {
    const st = load("05-queue-full", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "X", false).effect.cmd, { cmd: "scrap", name: "Lazy Avenue" });
    assert.equal(T.key(ui(st, NOW), st, "X", true).effect.kind, "none");
    for (const f of ["06-first-tune", "08-nothing-kept", "13-held-memory", "21-stopped"]) {
        const s = load(f, NOW);
        assert.equal(T.key(ui(s, NOW), s, "X", false).effect.kind, "none", f);
        assert.ok(!T.hints(s, ui(s, NOW)).some(h => h[0] === "X"), f);
    }
});

t("just after a scrap: Z and the undo footer with its countdown", () => {
    const st = load("11-after-scrap", NOW);
    const u = ui(st, NOW);
    const p = T.view(st, u).player;
    assert.deepEqual([p.now.name, p.now.time.left, p.next.head], ["Brass Lantern", "0:03", "1 ready"]);
    assert.deepEqual(rows(p), [["", "Quiet Ledger", "96 BPM · D minor", "2:49"], ["", "Being written", "about 1:50 left", "composing"]]);
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | using 5.8 GiB of RAM", "ACE-Step 1.5 Turbo · 4B Q8 · Radeon 780M"]);
    assert.equal(T.undoLine(st, u), "Scrapped Lazy Avenue. Z brings it back for 10 s.");
    assert.equal(T.undoLine(st, ui(st, NOW + 2.5)), "Scrapped Lazy Avenue. Z brings it back for 8 s.");
    assert.equal(T.undoLine(st, ui(st, NOW + 9.9)), "Scrapped Lazy Avenue. Z brings it back for 1 s.");
    assert.equal(T.undoLine(st, ui(st, NOW + 10)), "");
    assert.deepEqual(T.key(u, st, "Z", false).effect.cmd, { cmd: "undo" });
    assert.equal(T.key(u, st, "Z", true).effect.kind, "none");
    assert.equal(T.key(ui(st, NOW + 10), st, "Z", false).effect.kind, "none");
    assert.ok(T.hints(st, u).some(h => h[0] === "Z"));
    // Not in the chooser.
    assert.equal(T.undoLine(st, ui(st, NOW, { mode: "chooser" })), "");
    // The countdown alone keeps the tick on.
    const paused = edit("11-after-scrap", { player: "paused", job: null, composing: false });
    assert.equal(T.needsTick(paused, ui(paused, NOW)), true);
    assert.equal(T.needsTick(paused, ui(paused, NOW + 10)), false);
});

t("C on/off wording in each state", () => {
    const c = name => T.hints(load(name, NOW), ui(load(name, NOW), NOW)).find(h => h[0] === "C")[1];
    assert.equal(c("08-nothing-kept"), "composer on");
    assert.equal(c("10-writing"), "composer off");
    assert.equal(c("05-queue-full"), "composer off");
    assert.equal(c("12-held-game"), "composer off");
    assert.equal(c("15-failed-playing"), "composer off");
    const label = name => {
        const p = viewAt(name).player;
        return [p.composer.on, p.composer.label, p.composer.labelTone];
    };
    assert.deepEqual(label("08-nothing-kept"), [false, "off", "soft"]);
    assert.deepEqual(label("10-writing"), [true, "on", "soft"]);
    assert.deepEqual(label("05-queue-full"), [true, "on", "soft"]);
    assert.deepEqual(label("12-held-game"), [true, "held for a game", "orange"]);
    assert.deepEqual(label("13-held-memory"), [true, "held for memory", "orange"]);
    assert.deepEqual(label("15-failed-playing"), [true, "failed", "red"]);
    for (const f of ["08-nothing-kept", "05-queue-full", "12-held-game", "15-failed-playing"]) {
        const s = load(f, NOW);
        assert.deepEqual(T.key(ui(s, NOW), s, "C", false).effect.cmd, { cmd: "compose", on: !s.snap.composing }, f);
        assert.equal(T.key(ui(s, NOW), s, "C", true).effect.kind, "none", f);
    }
});

t("held for a game and for memory", () => {
    const p = viewAt("12-held-game").player;
    assert.equal(p.strip, null);
    assert.deepEqual([p.now.name, p.now.time.left], ["Paper Lantern", "0:22"]);
    assert.deepEqual(lines(p), ["Makes Lo-fi, keeps 2 ahead", "A game is running. Composing waits and carries on by itself when the game closes; tunes already made keep playing."]);
    assert.equal(p.composer.lines[1].tone, "orange");
    assert.deepEqual(T.barView(load("12-held-game", NOW)), { tone: "normal", text: "Lo-fi", dot: "orange" });
    const m = viewAt("13-held-memory").player;
    assert.deepEqual([m.now.name, m.now.meta], ["Nothing yet", ""]);
    assert.deepEqual(lines(m)[1], "Not enough free memory: a tune needs 6 GiB and 3.1 GiB is free. Composing carries on by itself when there is room.");
    assert.deepEqual(T.barView(load("13-held-memory", NOW)), { tone: "dim", text: "", dot: "orange" });
    assert.equal(T.needsTick(load("13-held-memory", NOW), ui(load("13-held-memory", NOW), NOW)), false);
});

t("failed: the composer says so, R tries now", () => {
    const st = load("15-failed-playing", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.equal(p.now.name, "Dusty Notebook");
    assert.deepEqual(lines(p), [
        "Makes Lo-fi, keeps 2 ahead",
        "Failed: ggml_vulkan: device lost. 2 failures in a row. Trying again in 30 s.",
        "ACE-Step 1.5 Turbo · 4B Q8 · Radeon 780M"
    ]);
    assert.equal(p.composer.lines[1].tone, "red");
    assert.equal(lines(T.view(st, ui(st, NOW + 31)).player)[1], "Failed: ggml_vulkan: device lost. 2 failures in a row. Trying again now.");
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["S", "shuffle"], ["L", "repeat one"], ["Y", "share"], ["X", "scrap Dusty Notebook"], ["R", "try now"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "R", false).effect.cmd, { cmd: "retry" });
    assert.equal(T.key(ui(st, NOW), st, "R", true).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Lo-fi", dot: "red" });
    // Nothing playing, no retry time: R is the way, and only it counts down.
    const later = edit("15-failed-playing", { player: "none", tune: null, model: Object.assign({}, st.snap.model, { retryAt: null, detail: null, failures: 1 }) });
    assert.equal(lines(T.view(later, ui(later, NOW)).player)[1], "Failed. 1 failure in a row. R tries again.");
    assert.equal(T.needsTick(later, ui(later, NOW)), false);
    const counting = edit("15-failed-playing", { player: "none", tune: null });
    assert.equal(T.needsTick(counting, ui(counting, NOW)), true);
});

t("writing again after a silence", () => {
    const p = viewAt("22-writing-again").player;
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | using 5.8 GiB of RAM", "Writing again: the last plan had 39 s of silence.", "ACE-Step 1.5 Turbo · 4B Q8 · Radeon 780M"]);
});

t("paused", () => {
    const st = load("17-paused", NOW);
    const p = T.view(st, ui(st, NOW + 60)).player;
    assert.deepEqual([p.now.name, p.now.nameTone, p.now.meta, p.now.main, p.now.mainLit], ["Lazy Avenue", "soft", "139 BPM · C major · paused", "play", true]);
    assert.equal(p.now.time.left, "2:25");
    assert.deepEqual(T.hints(st, ui(st, NOW))[0], ["Space", "play"]);
    assert.deepEqual(T.barView(st), { tone: "normal", text: "", dot: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
});

t("the position between snapshots", () => {
    const st = load("05-queue-full", NOW);
    assert.equal(T.position(st.snap, NOW + 10.5), 155.5);
    assert.equal(T.position(st.snap, NOW - 5), 145);
    assert.equal(T.position(st.snap, NOW + 1000), 177);
    assert.equal(T.view(st, ui(st, NOW + 1000)).player.now.wave.played, 78);
});

t("a click on the waveform seeks", () => {
    const st = load("05-queue-full", NOW);
    assert.deepEqual(T.seek(st, 0.5), { cmd: "seek", t: 88.5 });
    assert.deepEqual(T.seek(st, 1.4), { cmd: "seek", t: 177 });
    assert.equal(T.seek(load("06-first-tune", NOW), 0.5), null);
    assert.equal(T.seek(T.initial(), 0.5), null);
});

t("stopped by the user: nothing starts by itself, Space plays", () => {
    const st = load("21-stopped", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual([p.now.name, p.now.mainLit, p.now.main], ["Stopped. Space plays.", true, "play"]);
    assert.deepEqual(p.strip, { tone: "orange", text: "mpv could not play the tune: audio output initialization failed" });
    assert.deepEqual(T.key(ui(st, NOW), st, "Space", false).effect.cmd, { cmd: "toggle" });
    // Stopped with nothing ready yet: the first tune will not start by itself.
    const wait = edit("06-first-tune", { stopped: true });
    assert.deepEqual([T.view(wait, ui(wait, NOW)).player.now.name, T.view(wait, ui(wait, NOW)).player.now.meta], ["Nothing yet", "The player is stopped: Space starts it once a tune is ready."]);
    // Composer off, kept tunes, stopped.
    const kept = edit("08-nothing-kept", { genre: "lofi", keptTotal: 31, stopped: true });
    assert.equal(T.view(kept, ui(kept, NOW)).player.now.name, "Stopped. Space plays.");
    assert.deepEqual(T.hints(kept, ui(kept, NOW))[0], ["Space", "play"]);
});

t("a genre change starts clean: paused or stopped does not carry over", () => {
    const after = (name, upTo) => {
        const st = events(name, NOW).slice(0, upTo).reduce((s, ev) => T.apply(s, ev, NOW), T.initial());
        return [st, T.view(st, ui(st, NOW)).player];
    };
    for (const f of ["23-pick-after-pause", "24-pick-after-stop"]) {
        // Before: paused, or stopped.
        const [, before] = after(f, 1);
        assert.ok(/paused/.test(before.now.meta) || before.now.name === "Stopped. Space plays.", f);
        // A genre with nothing kept: the drawing, no Space.
        const [none, p] = after(f, 2);
        assert.deepEqual([p.now.head, p.now.name, p.now.meta, p.now.mainLit], ["Synthwave", "No Synthwave tunes yet", "Turn the composer on to make some.", false], f);
        assert.ok(!T.hints(none, ui(none, NOW)).some(h => h[0] === "Space"), f);
        assert.deepEqual(T.barView(none), { tone: "dim", text: "", dot: "" }, f);
        // A genre with kept tunes: they play, nothing says paused or stopped.
        const [kept, k] = after(f, 4);
        assert.deepEqual([k.now.head, k.now.name, k.now.meta, k.now.main], ["Classical · kept tunes", "Amber Stair", "72 BPM · G major", "pause"], f);
        assert.deepEqual(T.hints(kept, ui(kept, NOW))[0], ["Space", "pause"], f);
        assert.deepEqual(T.barView(kept), { tone: "normal", text: "Classical", dot: "" }, f);
    }
    // Kept tunes not started yet in a fresh genre: not worded as a stop.
    const fresh = edit("24-pick-after-stop", { player: "none", tune: null, stopped: false });
    assert.equal(T.view(fresh, ui(fresh, NOW)).player.now.name, "Nothing playing. Space plays.");
});

t("a queue entry and a tune not read yet", () => {
    const st = edit("05-queue-full", {
        queue: [{ name: "20260105-100000-70bpm-G-major", bpm: null, key: "", length: null, kept: true }],
        tune: Object.assign({}, load("05-queue-full", NOW).snap.tune, { length: null, bpm: null, key: "", wave: [] })
    });
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual(rows(p)[0], [1, "20260105-100000-70bpm-G-major", "", ""]);
    assert.equal(p.now.meta, "");
    assert.deepEqual(p.now.time, { left: "2:25", leftTone: "soft", right: "–:––" });
    assert.equal(T.seek(st, 0.5), null);
});

t("a broken genres file", () => {
    const st = load("16-genres-error", NOW);
    assert.deepEqual(T.view(st, ui(st, NOW)).player.strip, { tone: "orange", text: "genres file: line 4: expected a comma" });
    assert.deepEqual(T.view(st, T.key(ui(st, NOW), st, "G", false).ui).chooser.strip.text, "genres file: line 4: expected a comma");
});

t("no device: the player stays, the composer says why, R and C", () => {
    const st = load("14-no-device", NOW);
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "player");
    assert.deepEqual([v.player.now.name, v.player.now.mainLit], ["Nothing playing. Space plays.", true]);
    assert.deepEqual([v.player.composer.on, v.player.composer.label, v.player.composer.labelTone], [true, "no device", "red"]);
    assert.deepEqual(lines(v.player), ["Makes Lo-fi, keeps 2 ahead", "The model server did not find the Radeon 780M among the Vulkan devices: 1 device, not this one. R tries again, C turns the composer off."]);
    assert.equal(v.player.composer.lines[1].tone, "red");
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "play"], ["S", "shuffle"], ["L", "repeat one"], ["R", "try now"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "R", false).effect.cmd, { cmd: "retry" });
    assert.deepEqual(T.key(ui(st, NOW), st, "C", false).effect.cmd, { cmd: "compose", on: false });
    // Kept tunes playing: Space, N and X stay.
    const playing = edit("07-composer-off-kept", { composing: true, model: st.snap.model });
    assert.deepEqual(T.hints(playing, ui(playing, NOW)).map(h => h[0]), ["Space", "N", "S", "L", "Y", "X", "R", "C", "G", "Esc"]);
    // Nothing found to name.
    const bare = edit("14-no-device", { model: Object.assign({}, st.snap.model, { detail: null }) });
    assert.equal(lines(T.view(bare, ui(bare, NOW)).player)[1], "The model server did not find the Radeon 780M among the Vulkan devices. R tries again, C turns the composer off.");
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "red" });
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
});

t("the bar: the note and the dot in every combination", () => {
    const bar = (name, changes) => T.barView(changes ? edit(name, changes) : load(name, NOW));
    const base = load("05-queue-full", NOW).snap.model;
    const m = state => ({ model: Object.assign({}, base, { state }) });
    // Playing, paused, nothing: the note; with each composer state: the dot.
    for (const [player, tone, text] of [["playing", "normal", "Jazz"], ["paused", "normal", ""], ["none", "dim", ""]]) {
        const tune = player === "none" ? { tune: null } : {};
        for (const [state, dot] of [["idle", ""], ["starting", "cyan"], ["writing", "cyan"], ["rendering", "cyan"], ["held_game", "orange"], ["held_memory", "orange"], ["failed", "red"], ["no_device", "red"]])
            assert.deepEqual(bar("05-queue-full", Object.assign({ player, composing: true }, tune, m(state))), { tone, text, dot }, `${player} ${state}`);
        assert.deepEqual(bar("05-queue-full", Object.assign({ player, composing: false }, tune, m("unloaded"))), { tone, text, dot: "" }, `${player} off`);
    }
    // Off with a stale working state: no dot.
    assert.equal(bar("05-queue-full", Object.assign({ composing: false }, m("writing"))).dot, "");
    // No genre yet.
    assert.deepEqual(bar("04-chooser-first"), { tone: "dim", text: "", dot: "" });
});

t("the global scrap: undo, scrap, or nothing, and its notification", () => {
    const full = load("05-queue-full", NOW);
    const first = T.globalScrap(full, NOW);
    assert.deepEqual([first.cmd, first.summary, first.body, first.flash], [{ cmd: "scrap", name: "Lazy Avenue" }, "Scrapped Lazy Avenue", "Super+Shift+M again within 10 s brings it back.", true]);
    // A second press before the service has answered: an undo, never a
    // second scrap.
    const second = T.globalScrap(first.st, NOW + 0.1);
    assert.deepEqual([second.cmd, second.summary, second.body, second.flash], [{ cmd: "undo" }, "Brought back Lazy Avenue", "It plays next.", false]);
    assert.equal(T.globalScrap(second.st, NOW + 0.2).cmd.cmd, "scrap");
    // The service's next snapshot answers it; one it ignored lapses.
    assert.equal(T.globalScrap(T.apply(first.st, events("05-queue-full", NOW)[0], NOW), NOW + 0.1).cmd.cmd, "scrap");
    assert.equal(T.globalScrap(first.st, NOW + 2).cmd.cmd, "scrap");
    const after = load("11-after-scrap", NOW);
    const undo = T.globalScrap(after, NOW);
    assert.deepEqual([undo.cmd, undo.summary, undo.body, undo.flash], [{ cmd: "undo" }, "Brought back Lazy Avenue", "It plays next.", false]);
    // Scrapped in another genre than the one picked now: it goes back there,
    // it does not play next.
    const elsewhere = edit("11-after-scrap", { undo: Object.assign({}, after.snap.undo, { genre: "lofi" }) });
    assert.equal(T.globalScrap(elsewhere, NOW).body, "It is back with the kept Lo-fi tunes.");
    const unknown = edit("11-after-scrap", { undo: Object.assign({}, after.snap.undo, { genre: "gone" }) });
    assert.equal(T.globalScrap(unknown, NOW).body, "It is back in its folder.");
    // Once the undo has run out, a scrap of what plays.
    assert.equal(T.globalScrap(after, NOW + 10).summary, "Scrapped Brass Lantern");
    // Nothing plays: nothing.
    assert.equal(T.globalScrap(load("06-first-tune", NOW), NOW), null);
    // Nothing plays but an undo is offered: the undo.
    assert.equal(T.globalScrap(edit("11-after-scrap", { tune: null, player: "none" }), NOW).cmd.cmd, "undo");
    assert.equal(T.globalScrap(load("17-paused", NOW), NOW).cmd.cmd, "scrap");
    // The bar's note flashes orange while the flash is on, over any playback
    // tone; the dot is the composer's still.
    assert.deepEqual(T.barView(full, true), { tone: "orange", text: "Jazz", dot: "" });
    assert.deepEqual(T.barView(load("17-paused", NOW), true).tone, "orange");
    assert.deepEqual(T.barView(full, false), T.barView(full));
    assert.ok(T.FLASH_MS > 0 && T.FLASH_MS <= 1000);
    assert.equal(T.globalScrap(T.initial(), NOW), null);
});

t("outside text passes through unchanged, for the QML to draw as plain text", () => {
    const st = load("19-outside-text", NOW);
    const u = ui(st, NOW);
    const p = T.view(st, u).player;
    assert.equal(p.now.head, "<b>Bold</b> & co");
    assert.equal(p.now.name, "<i>Name</i> & <font color=red>tag</font>");
    assert.equal(p.now.meta, "88 BPM · B♭ minor");
    assert.equal(p.next.rows[0].name, "<u>Queued</u>");
    assert.equal(p.composer.lines[0].em, "<b>Bold</b> & co");
    assert.equal(lines(p)[1], "Failed: <u>server</u> said: oops. 1 failure in a row. Trying again in 30 s.");
    assert.equal(T.undoLine(st, u), "Scrapped <s>Gone</s>. Z brings it back for 6 s.");
    assert.ok(T.hints(st, ui(st, NOW + 7)).some(h => h[1] === "scrap <i>Name</i> & <font color=red>tag</font>"));
    assert.equal(T.globalScrap(st, NOW + 7).summary, "Scrapped <i>Name</i> & <font color=red>tag</font>");
    assert.deepEqual(T.barView(st), { tone: "normal", text: "<b>Bold</b> & co", dot: "red" });
});

t("a session: chooser, a genre with nothing kept, the composer on, the first tune", () => {
    const evs = events("20-session", NOW);
    let st = T.initial();
    const seen = [];
    for (const ev of evs) {
        st = T.apply(st, ev, NOW);
        const v = T.view(st, ui(st, NOW));
        seen.push(v.kind === "player" ? [v.player.now.name, v.player.composer.label] : [v.kind]);
    }
    assert.deepEqual(seen, [["chooser"], ["chooser"], ["No Synthwave tunes yet", "off"], ["Nothing yet", "on"], ["Nothing yet", "on"], ["Neon Harbour", "on"]]);
    const starting = evs.slice(0, 4).reduce((s, ev) => T.apply(s, ev, NOW), T.initial());
    const p = T.view(starting, ui(starting, NOW)).player;
    assert.deepEqual(lines(p)[0], "Makes Synthwave, keeps 2 ahead | starting the model");
    assert.deepEqual(rows(p).map(r => r[1]), ["Not started", "Not started"]);
    assert.deepEqual(T.barView(starting), { tone: "dim", text: "", dot: "cyan" });
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Synthwave", dot: "cyan" });
});

t("the load and unload keys are gone; every key in every fixture is safe", () => {
    assert.ok(!T.KEY_NAMES.includes("U"));
    for (const f of fixtures()) {
        const s = load(f, NOW);
        for (const mode of ["player", "chooser"])
            for (const row of [null, { kind: "queue", i: 0, name: "Brass Lantern" }, { kind: "job" }])
                for (const k of T.KEY_NAMES.concat(["U"])) {
                    const r = T.key(ui(s, NOW, { mode, row }), s, k, false);
                    const cmd = r.effect.cmd && r.effect.cmd.cmd;
                    assert.ok(cmd !== "load" && cmd !== "unload", `${f} ${k}`);
                    if (k === "U")
                        assert.equal(r.effect.kind, "none", f);
                    // A held key acts once, except the arrows.
                    if (!["Left", "Right", "Up", "Down"].includes(k))
                        assert.equal(T.key(ui(s, NOW, { mode, row }), s, k, true).effect.kind, "none", `${f} ${k} held`);
                }
    }
});

t("the tick runs only while something on screen counts", () => {
    const tick = (name, changes, now) => {
        const s = load(name, NOW);
        return T.needsTick(s, ui(s, now === undefined ? NOW : now, changes));
    };
    assert.equal(tick("05-queue-full"), true);
    assert.equal(tick("05-queue-full", { mode: "chooser" }), false);
    assert.equal(tick("07-composer-off-kept"), true);
    assert.equal(tick("08-nothing-kept"), false);
    assert.equal(tick("12-held-game"), true);
    assert.equal(tick("06-first-tune"), true);
    assert.equal(tick("01-not-set-up"), false);
    assert.equal(tick("02-downloading"), false);
    assert.equal(tick("17-paused"), false);
    assert.equal(tick("21-stopped"), false);
});

// The genre editor. The chooser opened over 05-queue-full, the cursor on
// Jazz (14 kept); the service's answers in 26-genre-jazz and
// 27-genre-results.
const chooserOf = name => {
    const st = load(name, NOW);
    return [st, T.key(ui(st, NOW), st, "G", false).ui];
};
const RESULTS = events("27-genre-results", NOW);
const JAZZ = events("26-genre-jazz", NOW)[0];
const typeIn = (u, fields) => Object.keys(fields).reduce((x, f) => T.typed(x, f, fields[f]), u);
// The editor on Jazz with its line answered.
const jazzEditor = () => {
    const [st, c] = chooserOf("05-queue-full");
    return [st, T.answer(T.key(c, st, "E", false).ui, st, JAZZ, NOW)];
};
const errorsOf = e => [e.fields.name.error, e.fields.caption.error, e.fields.turns.error, e.tempoError];
const LETTERS = ["Space", "N", "G", "C", "X", "Z", "R", "E", "A", "D", "Left", "Right", "Up", "Down"];

t("the chooser: the + New genre cell, and the keys with the cursor on it", () => {
    const [st, c] = chooserOf("05-queue-full");
    const add = press(st, c, ["Down", "Right", "Right"]).ui;
    assert.equal(add.sel, 9);
    const v = T.view(st, add).chooser;
    assert.deepEqual(v.add, { name: "+ New genre", sel: true });
    assert.ok(v.cells.every(x => !x.sel));
    assert.equal(T.view(st, c).chooser.add.sel, false);
    assert.deepEqual(T.hints(st, add), [["←↑↓→", "move"], ["Enter", "add a genre"], ["Esc", "back"]]);
    for (const k of ["Enter", "A"]) {
        const r = T.key(add, st, k, false);
        assert.deepEqual([r.ui.mode, r.effect.kind, T.view(st, r.ui).editor.title], ["editor", "none", "New genre"], k);
    }
    assert.equal(T.key(add, st, "E", false).effect.kind, "none");
    assert.equal(T.key(add, st, "D", false).ui.mode, "chooser");
    // A click on the cell; past it, nothing.
    assert.equal(T.pick(c, st, 9).ui.mode, "editor");
    assert.deepEqual(T.pick(c, st, 10), { ui: c, effect: { kind: "none", cmd: null } });
    // A file with no genres: only the cell, the line over it.
    const none = edit("04-chooser-first", { genres: [] });
    const n = ui(none, NOW);
    assert.deepEqual([T.view(none, n).chooser.empty, T.view(none, n).chooser.add.sel], ["The genres file lists no genres.", true]);
    assert.deepEqual(T.hints(none, n), [["Enter", "add a genre"], ["Esc", "close"]]);
    assert.equal(T.key(n, none, "Enter", false).ui.mode, "editor");
});

t("deleting a genre: the question, its words, Enter sends, Esc keeps it, never the last", () => {
    const [st, c] = chooserOf("05-queue-full");
    const at = press(st, c, ["Right"]).ui;
    const ask = T.key(at, st, "D", false);
    assert.deepEqual([ask.ui.mode, ask.effect.kind], ["ask", "none"]);
    const v = T.view(st, ask.ui);
    assert.equal(v.kind, "chooser");
    assert.deepEqual(v.chooser.ask, { title: "Delete Classical?", detail: "Its 9 kept tunes stay in ~/Music/Tunes/Classical. Only the genre leaves the panel.", error: "" });
    assert.equal(v.chooser.cells[5].sel, true);
    assert.deepEqual(T.hints(st, ask.ui), [["Enter", "delete Classical"], ["Esc", "keep it"]]);
    // Nothing else acts while it asks, a click on a cell included.
    for (const k of LETTERS)
        assert.equal(T.key(ask.ui, st, k, false).effect.kind, "none", k);
    assert.equal(T.key(ask.ui, st, "Left", false).ui.sel, 5);
    assert.equal(T.pick(ask.ui, st, 0).effect.kind, "none");
    assert.equal(T.pick(ask.ui, st, 9).effect.kind, "none");
    const keep = T.key(ask.ui, st, "Esc", false).ui;
    assert.deepEqual([keep.mode, keep.ask], ["chooser", null]);
    const sent = T.key(ask.ui, st, "Enter", false);
    assert.deepEqual(sent.effect.cmd, { cmd: "genre_delete", id: "classical" });
    assert.equal(T.key(ask.ui, st, "Enter", true).effect.kind, "none");
    // Sent once until answered or WAIT_S has passed.
    assert.equal(T.key(sent.ui, st, "Enter", false).effect.kind, "none");
    assert.equal(T.key(Object.assign({}, sent.ui, { now: NOW + T.WAIT_S }), st, "Enter", false).effect.kind, "send");
    // Answered: the chooser; refused: the reason in the question.
    const done = T.answer(sent.ui, st, { event: "genre_result", ok: true, id: "classical" }, NOW);
    assert.deepEqual([done.mode, done.ask, done.waiting], ["chooser", null, null]);
    const no = T.answer(sent.ui, st, { event: "genre_result", ok: false, field: null, text: "The last genre cannot be deleted." }, NOW);
    assert.deepEqual([no.mode, T.view(st, no).chooser.ask.error], ["ask", "The last genre cannot be deleted."]);
    assert.equal(T.key(no, st, "Enter", false).effect.kind, "send");
    assert.equal(T.view(st, T.key(no, st, "Enter", false).ui).chooser.ask.error, "");
    // Nothing kept: only the genre leaves; one kept tune.
    const detail = (s, u) => T.view(s, u).chooser.ask.detail;
    assert.equal(detail(st, T.key(press(st, c, ["Left", "Left"]).ui, st, "D", false).ui), "Only the genre leaves the panel.");
    const one = edit("05-queue-full", { genres: st.snap.genres.map(g => g.id === "classical" ? Object.assign({}, g, { kept: 1 }) : g) });
    assert.equal(detail(one, ask.ui), "Its 1 kept tune stays in ~/Music/Tunes/Classical. Only the genre leaves the panel.");
    // The last genre: D is not offered and does nothing.
    const last = load("28-one-genre", NOW);
    const l = ui(last, NOW);
    assert.deepEqual(T.hints(last, l), [["←↑↓→", "move"], ["Enter", "play Ambient"], ["E", "edit"], ["A", "add"], ["Esc", "close"]]);
    assert.equal(T.key(l, last, "D", false).ui.mode, "player");
    assert.equal(T.view(last, T.key(l, last, "D", false).ui).chooser.ask, null);
});

t("editing a genre: E asks the service for it, its line fills the fields", () => {
    const [st, c] = chooserOf("05-queue-full");
    const r = T.key(c, st, "E", false);
    assert.deepEqual(r.effect, { kind: "send", cmd: { cmd: "genre_get", id: "jazz" } });
    assert.equal(T.key(c, st, "E", true).effect.kind, "none");
    let e = T.view(st, r.ui).editor;
    assert.deepEqual([T.view(st, r.ui).kind, e.title, e.chip, e.focus], ["editor", "Edit Jazz", "14 kept", "name"]);
    assert.equal(e.hint, "Changes apply to the next tune composed. The 14 kept tunes stay as they are.");
    assert.deepEqual(e.values, { name: "", caption: "", turns: "", lo: "", hi: "" });
    // Nothing to complain about, nothing saved, before the answer.
    assert.deepEqual(errorsOf(e), ["", "", "", ""]);
    assert.equal(T.key(r.ui, st, "CtrlS", false).effect.kind, "none");
    assert.deepEqual(T.hints(st, r.ui), [["Tab", "next field"], ["Ctrl+S", "save"], ["Esc", "discard"]]);
    const filled = T.answer(r.ui, st, JAZZ, NOW);
    e = T.view(st, filled).editor;
    assert.deepEqual(e.values, {
        name: "Jazz",
        caption: "small combo jazz, walking upright bass, brushed snare, warm tenor saxophone lead",
        turns: "smoky club\nlate set, slow and close\nmuted trumpet takes the lead\npiano trio, no horns\nvibraphone solo\nrainy evening\nbossa feel\na slow ballad",
        lo: "90",
        hi: "150"
    });
    assert.ok(e.rev > T.view(st, r.ui).editor.rev);
    assert.equal(filled.waiting, null);
    assert.deepEqual([e.fields.name.label, e.fields.caption.label, e.fields.turns.label, e.fields.lo.label, e.fields.hi.label], ["NAME", "PROMPT", "VARIATIONS", "SLOWEST", "FASTEST"]);
    assert.deepEqual([e.fields.caption.side, e.fields.turns.side, e.fields.caption.placeholder, e.fields.turns.placeholder], ["what every tune has", "one per line, two are picked per tune", "instruments, mood, style, in a few phrases", "one per line"]);
    // A line for another genre, or none asked for: nothing changes.
    assert.equal(T.answer(r.ui, st, Object.assign({}, JAZZ, { id: "lofi" }), NOW), r.ui);
    assert.equal(T.answer(filled, st, JAZZ, NOW), filled);
    assert.equal(T.answer(null, st, JAZZ, NOW), null);
    // The hint and the chip with one kept tune and with none.
    const kept = n => T.view(edit("05-queue-full", { genres: st.snap.genres.map(g => g.id === "jazz" ? Object.assign({}, g, { kept: n }) : g) }), filled).editor;
    assert.deepEqual([kept(1).chip, kept(1).hint], ["1 kept", "Changes apply to the next tune composed. The 1 kept tune stays as it is."]);
    assert.deepEqual([kept(0).chip, kept(0).hint], ["none yet", "Changes apply to the next tune composed."]);
});

t("the editor's keys: Tab and Enter move, letters go to the field, held keys act once, Esc discards", () => {
    const [st, u] = jazzEditor();
    const focusAfter = list => T.view(st, press(st, u, list).ui).editor.focus;
    assert.deepEqual(["Tab", "Tab", "Tab", "Tab", "Tab"].map((_, i, a) => focusAfter(a.slice(0, i + 1))), ["caption", "turns", "lo", "hi", "name"]);
    assert.equal(focusAfter(["ShiftTab"]), "hi");
    assert.equal(focusAfter(["Enter"]), "caption");
    assert.equal(focusAfter(["Tab", "Tab", "Tab", "Tab", "Enter"]), "name");
    // In VARIATIONS Enter is the field's: a new line.
    const turns = press(st, u, ["Tab", "Tab"]).ui;
    assert.deepEqual(T.key(turns, st, "Enter", false), { ui: turns, effect: { kind: "pass", cmd: null } });
    // No single-letter panel key acts: they and the arrows type or move the caret.
    for (const k of LETTERS) {
        const r = T.key(u, st, k, false);
        assert.deepEqual(r, { ui: u, effect: { kind: "pass", cmd: null } }, k);
        assert.equal(T.key(u, st, k, true).effect.kind, "pass", `${k} held`);
    }
    // Held, the editor's own keys act once.
    for (const k of ["Tab", "ShiftTab", "Enter", "CtrlS", "Esc"])
        assert.deepEqual(T.key(u, st, k, true), { ui: u, effect: { kind: "none", cmd: null } }, k);
    assert.equal(T.key(turns, st, "Enter", true).effect.kind, "none");
    // A click on a field.
    assert.equal(T.view(st, T.focus(u, "turns")).editor.focus, "turns");
    assert.equal(T.focus(u, "moods"), u);
    // Esc: nothing sent, the chooser with the cursor on the genre.
    const esc = T.key(typeIn(u, { name: "Changed" }), st, "Esc", false);
    assert.deepEqual([esc.ui.mode, esc.ui.ed, esc.effect.kind], ["chooser", null, "none"]);
    assert.equal(T.view(st, esc.ui).chooser.cells[4].sel, true);
    assert.equal(T.typed(esc.ui, "name", "x"), esc.ui);
    // Esc while a save is out: its result is not waited for.
    const saving = T.key(u, st, "CtrlS", false).ui;
    const left = T.key(saving, st, "Esc", false).ui;
    assert.equal(T.answer(left, st, RESULTS[0], NOW), left);
});

t("a new genre: its defaults, errors show as they are typed, Save does nothing while one stands", () => {
    const [st, c] = chooserOf("05-queue-full");
    let u = T.key(c, st, "A", false).ui;
    let e = T.view(st, u).editor;
    assert.deepEqual([e.title, e.chip, e.focus, e.hint], ["New genre", "", "name", "Tune names come from a shared word list until this genre has its own."]);
    assert.deepEqual(e.values, { name: "", caption: "", turns: "", lo: "70", hi: "120" });
    assert.equal(e.fields.turns.side, "optional");
    assert.deepEqual(errorsOf(e), ["", "", "", ""]);
    assert.ok(!e.fields.name.bad && !e.fields.lo.bad && !e.fields.hi.bad);
    // The drawn mistake.
    u = T.typed(u, "name", "Jazz");
    e = T.view(st, u).editor;
    assert.deepEqual([e.fields.name.error, e.fields.name.bad, e.fields.caption.error], ["There is already a genre called Jazz.", true, ""]);
    assert.equal(T.view(st, T.typed(u, "name", "jAZZ")).editor.fields.name.error, "There is already a genre called Jazz.");
    // Ctrl+S with errors: nothing sent, every error shown.
    const tried = T.key(u, st, "CtrlS", false);
    assert.equal(tried.effect.kind, "none");
    assert.deepEqual(errorsOf(T.view(st, tried.ui).editor), ["There is already a genre called Jazz.", "A genre needs a prompt.", "", ""]);
    // Fixed: trimmed, blank and repeated lines dropped.
    u = typeIn(tried.ui, { name: "  Bossa nova ", caption: " nylon guitar, soft shaker ", turns: "beach at dusk\n\n  beach at dusk \nslow samba" });
    assert.deepEqual(errorsOf(T.view(st, u).editor), ["", "", "", ""]);
    const sent = T.key(u, st, "CtrlS", false);
    assert.deepEqual(sent.effect.cmd, { cmd: "genre_save", id: null, genre: { name: "Bossa nova", caption: "nylon guitar, soft shaker", turns: ["beach at dusk", "slow samba"], bpm: [70, 120] } });
    assert.equal(T.key(sent.ui, st, "CtrlS", false).effect.kind, "none");
    // Saved: the chooser, the cursor on it once the snapshot lists it.
    const done = T.answer(sent.ui, st, RESULTS[1], NOW);
    assert.deepEqual([done.mode, done.ed, done.selId, T.notice(st, done)], ["chooser", null, "bossanova", ""]);
    const after = load("29-after-save", NOW);
    const v = T.view(after, done).chooser;
    assert.deepEqual([v.cells[9].name, v.cells[9].sel, v.add.sel], ["Bossa nova", true, false]);
    assert.deepEqual(T.hints(after, done)[1], ["Enter", "play Bossa nova"]);
    assert.equal(press(after, done, ["Left"]).ui.sel, 8);
    // An empty name typed and cleared shows its error; an untouched one does not.
    assert.equal(T.view(st, typeIn(T.key(c, st, "A", false).ui, { name: "x" })).editor.fields.name.error, "");
    assert.equal(T.view(st, T.typed(T.typed(T.key(c, st, "A", false).ui, "name", "x"), "name", "")).editor.fields.name.error, "A genre needs a name.");
    // Tempo errors under the row, the boxes they are about in red.
    const tempo = T.view(st, typeIn(T.key(c, st, "A", false).ui, { lo: "130" })).editor;
    assert.deepEqual([tempo.tempoError, tempo.fields.lo.bad, tempo.fields.hi.bad], ["The slowest tempo is above the fastest.", true, true]);
    const high = T.view(st, typeIn(T.key(c, st, "A", false).ui, { hi: "301" })).editor;
    assert.deepEqual([high.tempoError, high.fields.lo.bad, high.fields.hi.bad], ["Tempos go from 30 to 300 BPM.", false, true]);
});

t("the rules, at and across each boundary, as the service has them", () => {
    const genres = load("05-queue-full", NOW).snap.genres;
    const ok = { name: "Bossa nova", caption: "nylon guitar", turns: "", lo: "70", hi: "120" };
    const err = (changes, id) => T.check(Object.assign({}, ok, changes), genres, id === undefined ? null : id).errors;
    const name = (n, id) => err({ name: n }, id).name;
    const x = (c, n) => c.repeat(n);
    assert.deepEqual(T.check(ok, genres, null), { errors: { name: "", caption: "", turns: "", bpm: "" }, bad: { lo: false, hi: false }, genre: { name: "Bossa nova", caption: "nylon guitar", turns: [], bpm: [70, 120] } });
    // name: trimmed, 1..40 characters (code points), no slash, no leading
    // dot, no control characters, unique ignoring case but for itself.
    assert.equal(name(""), "A genre needs a name.");
    assert.equal(name(" \t "), "A genre needs a name.");
    assert.equal(name("a"), "");
    assert.equal(name(x("a", 40)), "");
    assert.equal(name(` ${x("a", 40)}\t`), "");
    assert.equal(name(x("a", 41)), "A name is at most 40 characters; this one has 41.");
    assert.equal(name(x("🎷", 40)), "");
    assert.equal(name(x("🎷", 41)), "A name is at most 40 characters; this one has 41.");
    assert.equal(name("AC/DC"), "A name cannot contain a slash: it is also a folder's name.");
    assert.equal(name(".hidden"), "A name cannot start with a dot.");
    assert.equal(name("  .hidden"), "A name cannot start with a dot.");
    assert.equal(name("Vol. 2"), "");
    for (const ch of ["\u0000", "\u0007", "\t", "\n", "\u001f", "\u007f", "\u0085", "\u009f"])
        assert.equal(name(`a${ch}b`), "A name cannot hold control characters or line breaks.", JSON.stringify(ch));
    assert.equal(name("a b"), "");
    assert.equal(name("LO-FI"), "There is already a genre called Lo-fi.");
    assert.equal(name(" deep HOUSE "), "There is already a genre called Deep house.");
    assert.equal(name("lo-fi", "lofi"), "");
    assert.equal(name("Jazz", "lofi"), "There is already a genre called Jazz.");
    // caption: trimmed, 1..400.
    const cap = c => err({ caption: c }).caption;
    assert.equal(cap(""), "A genre needs a prompt.");
    assert.equal(cap("   "), "A genre needs a prompt.");
    assert.equal(cap("a"), "");
    assert.equal(cap(x("a", 400)), "");
    assert.equal(cap(`  ${x("a", 400)}  `), "");
    assert.equal(cap(x("a", 401)), "A prompt is at most 400 characters; this one has 401.");
    // turns: 0..20 after blank and repeated lines are dropped, each 1..120
    // trimmed; the line counted is the one typed.
    const lines = n => Array.from({ length: n }, (_, i) => `turn ${i + 1}`).join("\n");
    const tu = t => err({ turns: t }).turns;
    assert.equal(tu(""), "");
    assert.equal(tu(lines(20)), "");
    assert.equal(tu(lines(21)), "At most 20 variations; this has 21.");
    assert.equal(tu(`${lines(20)}\n\n   \nturn 3\n turn 20 `), "");
    assert.equal(tu(x("a", 120)), "");
    assert.equal(tu(`  ${x("a", 120)}  `), "");
    assert.equal(tu(`one\n\n${x("a", 121)}`), "Line 3 is longer than 120 characters.");
    assert.equal(tu(`${x("é", 120)}`), "");
    assert.deepEqual(T.parseTurns(" a \r\nb\r\rc\n a\n"), { turns: ["a", "b", "c"], long: 0 });
    assert.deepEqual(T.check(Object.assign({}, ok, { turns: "x\ny\nx" }), genres, null).genre.turns, ["x", "y"]);
    // bpm: whole numbers, 30 <= lo <= hi <= 300.
    const bpm = (lo, hi) => {
        const c = T.check(Object.assign({}, ok, { lo, hi }), genres, null);
        return [c.errors.bpm, c.bad.lo, c.bad.hi];
    };
    assert.deepEqual(bpm("30", "300"), ["", false, false]);
    assert.deepEqual(bpm("90", "90"), ["", false, false]);
    assert.deepEqual(bpm(" 090 ", "150"), ["", false, false]);
    assert.equal(T.check(Object.assign({}, ok, { lo: " 090 " }), genres, null).genre.bpm[0], 90);
    assert.deepEqual(bpm("29", "120"), ["Tempos go from 30 to 300 BPM.", true, false]);
    assert.deepEqual(bpm("70", "301"), ["Tempos go from 30 to 300 BPM.", false, true]);
    assert.deepEqual(bpm("20", "400"), ["Tempos go from 30 to 300 BPM.", true, true]);
    assert.deepEqual(bpm("91", "90"), ["The slowest tempo is above the fastest.", true, true]);
    assert.deepEqual(bpm("", "120"), ["The slowest tempo needs a whole number.", true, false]);
    assert.deepEqual(bpm("70", "fast"), ["The fastest tempo needs a whole number.", false, true]);
    assert.deepEqual(bpm("", ""), ["The slowest tempo needs a whole number.", true, true]);
    for (const v of ["7.5", "-40", "1e2", "+90", "9 0", "٩٠"])
        assert.equal(bpm(v, "120")[0], "The slowest tempo needs a whole number.", v);
    assert.equal(T.check(Object.assign({}, ok, { lo: "29" }), genres, null).genre, null);
});

t("the service's answers: a rename, refusals under their field, a genre gone", () => {
    const [st, u] = jazzEditor();
    const bebop = T.typed(u, "name", "Bebop");
    const sent = T.key(bebop, st, "CtrlS", false);
    assert.deepEqual(sent.effect.cmd, { cmd: "genre_save", id: "jazz", genre: { name: "Bebop", caption: JAZZ.caption, turns: JAZZ.turns, bpm: [90, 150] }, base: { name: "Jazz", caption: JAZZ.caption, turns: JAZZ.turns, bpm: [90, 150] } });
    // Saved and renamed: the chooser on the genre, the footer says so for
    // NOTICE_S and the tick runs until it goes.
    const done = T.answer(sent.ui, st, RESULTS[0], NOW);
    assert.deepEqual([done.mode, done.selId], ["chooser", "jazz"]);
    const after = load("29-after-save", NOW);
    assert.equal(T.notice(after, done), "Renamed Jazz to Bebop. Its folder in ~/Music/Tunes moved with it.");
    assert.equal(T.view(after, done).chooser.cells[4].sel, true);
    assert.equal(T.needsTick(after, done), true);
    const later = Object.assign({}, done, { now: NOW + T.NOTICE_S });
    assert.deepEqual([T.notice(after, later), T.needsTick(after, later)], ["", false]);
    assert.equal(T.notice(after, T.key(done, after, "Esc", false).ui), "");
    // Refused for the name: under it, Save stays off until the name changes.
    const name = T.answer(sent.ui, st, RESULTS[2], NOW);
    let e = T.view(st, name).editor;
    assert.deepEqual([name.mode, e.fields.name.error, e.fields.name.bad, e.tempoError], ["editor", "A folder called Bebop is already in ~/Music/Tunes.", true, ""]);
    assert.equal(T.key(name, st, "CtrlS", false).effect.kind, "none");
    const stillName = T.typed(name, "caption", "other");
    assert.equal(T.view(st, stillName).editor.fields.name.error, "A folder called Bebop is already in ~/Music/Tunes.");
    const renamed = T.typed(name, "name", "Hard bop");
    assert.equal(T.view(st, renamed).editor.fields.name.error, "");
    assert.equal(T.key(renamed, st, "CtrlS", false).effect.cmd.genre.name, "Hard bop");
    // A local error shows in place of the refusal.
    assert.equal(T.view(st, T.typed(T.typed(name, "caption", "x"), "name", "Lo-fi")).editor.fields.name.error, "There is already a genre called Lo-fi.");
    // Refused naming no field: under the last one; Save may try again; any
    // change clears it.
    const file = T.answer(sent.ui, st, RESULTS[3], NOW);
    e = T.view(st, file).editor;
    assert.deepEqual([e.tempoError, e.fields.lo.bad, e.fields.hi.bad, e.fields.name.error], ["The genres file on disk is broken: line 4: expected a comma.", true, true, ""]);
    assert.equal(T.key(file, st, "CtrlS", false).effect.kind, "send");
    assert.equal(T.view(st, T.typed(file, "turns", "one")).editor.tempoError, "");
    // Refused for the tempo: under the row until a tempo changes.
    const bpm = T.answer(sent.ui, st, RESULTS[4], NOW);
    assert.equal(T.view(st, bpm).editor.tempoError, "The tempo range is not valid.");
    assert.equal(T.view(st, T.typed(bpm, "name", "Cool jazz")).editor.tempoError, "The tempo range is not valid.");
    assert.equal(T.view(st, T.typed(bpm, "hi", "149")).editor.tempoError, "");
    // The genre was gone when E asked for it: the chooser, and the footer says so.
    const [, c] = chooserOf("05-queue-full");
    const gone = T.answer(T.key(c, st, "E", false).ui, st, RESULTS[5], NOW);
    assert.deepEqual([gone.mode, gone.ed, T.notice(st, gone)], ["chooser", null, "That genre no longer exists."]);
    // No command waiting: results change nothing.
    for (const ev of RESULTS)
        assert.equal(T.answer(c, st, ev, NOW), c);
    // Unknown fields and texts.
    const odd = T.answer(sent.ui, st, { event: "genre_result", ok: false, field: "moods" }, NOW);
    assert.equal(T.view(st, odd).editor.tempoError, "The genre was not saved.");
});

t("a genre command unanswered: the tick runs, the wait runs out and a save says so; the link dropping ends the wait", () => {
    const [st, u] = jazzEditor();
    const sent = T.key(T.typed(u, "name", "Bebop"), st, "CtrlS", false);
    assert.equal(sent.effect.kind, "send");
    // Nothing in the editor moves with the clock but the wait.
    assert.deepEqual([T.needsTick(st, u), T.needsTick(st, sent.ui)], [false, true]);
    const waited = Object.assign({}, sent.ui, { now: NOW + T.WAIT_S });
    assert.equal(T.needsTick(st, waited), false);
    assert.equal(T.view(st, sent.ui).editor.tempoError, "");
    assert.equal(T.NO_ANSWER, "The tunes service did not answer. Ctrl+S tries again.");
    assert.deepEqual([T.view(st, waited).editor.tempoError, T.view(st, waited).editor.fields.hi.bad], [T.NO_ANSWER, true]);
    // Ctrl+S sends again, and the line goes while that waits; a late answer still lands.
    const again = T.key(waited, st, "CtrlS", false);
    assert.equal(again.effect.kind, "send");
    assert.equal(T.view(st, again.ui).editor.tempoError, "");
    assert.equal(T.answer(waited, st, RESULTS[0], NOW).mode, "chooser");
    // The link drops: no wait left, the line at once, Ctrl+S sends.
    const down = T.linkDown(sent.ui, NOW);
    assert.equal(down.waiting, null);
    assert.equal(T.view(st, down).editor.tempoError, T.NO_ANSWER);
    assert.equal(T.key(down, st, "CtrlS", false).effect.kind, "send");
    // An editor still waiting for its genre: back to the chooser, which says so.
    const [, c] = chooserOf("05-queue-full");
    const lost = T.linkDown(T.key(c, st, "E", false).ui, NOW);
    assert.deepEqual([lost.mode, lost.ed, lost.waiting, lost.selId, T.notice(st, lost)], ["chooser", null, null, "jazz", "The tunes service did not answer."]);
    // The delete question: the wait cleared, Enter sends again.
    const asked = T.key(T.key(press(st, c, ["Right"]).ui, st, "D", false).ui, st, "Enter", false).ui;
    assert.equal(T.needsTick(st, asked), true);
    const askDown = T.linkDown(asked, NOW);
    assert.deepEqual([askDown.mode, askDown.waiting], ["ask", null]);
    assert.equal(T.key(askDown, st, "Enter", false).effect.kind, "send");
    // Nothing waiting: nothing changes.
    assert.equal(T.linkDown(u, NOW), u);
    assert.equal(T.linkDown(null, NOW), null);
});

t("a result left over from a command given up on closes nothing that waits now", () => {
    const [st, u] = jazzEditor();
    const saving = T.key(u, st, "CtrlS", false).ui;
    const asked = T.key(T.key(saving, st, "Esc", false).ui, st, "E", false).ui;
    assert.deepEqual([asked.mode, asked.waiting.kind, asked.waiting.id], ["editor", "get", "jazz"]);
    // The old save's success: the new editor stays, its genre still asked for.
    assert.equal(T.answer(asked, st, RESULTS[0], NOW), asked);
    assert.equal(T.answer(asked, st, JAZZ, NOW).ed.loading, false);
    // A save of one genre: another genre's success is not its own.
    assert.equal(T.answer(saving, st, RESULTS[1], NOW), saving);
    const [, c] = chooserOf("05-queue-full");
    const deleting = T.key(T.key(press(st, c, ["Right"]).ui, st, "D", false).ui, st, "Enter", false).ui;
    assert.equal(T.answer(deleting, st, RESULTS[0], NOW), deleting);
});

t("genre lines: healthy for the back-off, no change to the state", () => {
    const st = load("05-queue-full", NOW);
    for (const ev of [JAZZ].concat(RESULTS)) {
        assert.equal(T.healthy(ev), true, ev.event);
        assert.equal(T.apply(st, ev, NOW), st);
    }
});

t("outside text in the editor and the delete question passes through unchanged", () => {
    const st = edit("05-queue-full", { genres: [{ id: "x", name: "<i>X & co", kept: 2 }, { id: "y", name: "Y", kept: 0 }] });
    const c = ui(st, NOW, { mode: "chooser", sel: 0 });
    const q = T.view(st, T.key(c, st, "D", false).ui).chooser.ask;
    assert.deepEqual([q.title, q.detail], ["Delete <i>X & co?", "Its 2 kept tunes stay in ~/Music/Tunes/<i>X & co. Only the genre leaves the panel."]);
    assert.equal(T.view(st, T.key(c, st, "E", false).ui).editor.title, "Edit <i>X & co");
    const n = T.view(st, T.typed(T.key(c, st, "A", false).ui, "name", "<I>x & CO")).editor.fields.name.error;
    assert.equal(n, "There is already a genre called <i>X & co.");
});

t("unknown values fall back to the empty ones", () => {
    const st = T.apply(T.initial(), { event: "state", v: 1, setup: "ready", genre: "a", genres: [{ id: "a" }], composing: "yes", job: { stage: "dancing", started: "x", expect_s: -4 }, queue: [5, null, { name: 3 }], undo: { until: 9 }, expect: { writing_s: 0, rendering_s: 1 }, ahead: "two" }, NOW);
    const s = st.snap;
    assert.equal(s.composing, false);
    assert.deepEqual(s.job, { stage: "writing", started: null, expect: null, written: null });
    assert.deepEqual(s.queue, [{ name: "", file: "", bpm: null, key: "", length: null, kept: false, new: false, pinned: false, pos: null }]);
    assert.equal(s.undo, null);
    assert.equal(s.expect, null);
    assert.equal(s.ahead, 2);
    assert.equal(s.stopped, false);
    assert.equal(T.view(st, ui(st, NOW)).kind, "player");
});

// Shuffle, repeat, sharing and keeping for good. 30-34 are Jazz with 14
// kept tunes in each mode; 35-share-lines holds the service's answers to
// the share sheet's commands, for a home of /home/someone.
const HOME = "/home/someone";
const SHARE = events("35-share-lines", NOW);
const pills = p => p.modes.map(m => [m.key, m.label, m.lit, m.dim]);
// The share sheet opened on `name`'s state (with `changes` to the ui), and
// its tune described.
const sheet = (name, keys) => {
    const st = load(name, NOW);
    const r = press(st, T.initialUi(st, NOW, HOME), (keys || []).concat(["Y"]));
    return [st, r.ui, r.effect];
};
const described = (name, line) => {
    const [st, u] = sheet(name, line === SHARE[5] ? ["Down"] : []);
    return [st, T.answer(u, st, line || SHARE[0], NOW)];
};
const LAZY = "/home/someone/Music/Tunes/Jazz/20261123-070612-139bpm-C-major.mp3";

t("the mode pills: lit while on, share dim with nothing to share; S and L send, L names the mode it switches to", () => {
    const p = name => T.view(load(name, NOW), ui(load(name, NOW), NOW)).player;
    assert.deepEqual(pills(p("30-modes-default")), [["S", "shuffle", true, false], ["L", "repeat all", true, false], ["Y", "share", false, false]]);
    assert.deepEqual(pills(p("31-shuffle-off")), [["S", "shuffle", false, false], ["L", "repeat all", true, false], ["Y", "share", false, false]]);
    assert.deepEqual(pills(p("32-repeat-one")), [["S", "shuffle", true, false], ["L", "repeat one", true, false], ["Y", "share", false, false]]);
    assert.deepEqual(pills(p("33-ended")), [["S", "shuffle", true, false], ["L", "repeat off", false, false], ["Y", "share", false, true]]);
    assert.deepEqual(p("30-modes-default").modes.map(m => m.icon), ["shuffle", "repeat", "share"]);
    const k = (name, key) => {
        const s = load(name, NOW);
        return [T.hints(s, ui(s, NOW)).find(h => h[0] === key), T.key(ui(s, NOW), s, key, false).effect.cmd, T.key(ui(s, NOW), s, key, true).effect.kind];
    };
    assert.deepEqual(k("30-modes-default", "S"), [["S", "shuffle"], { cmd: "shuffle", on: false }, "none"]);
    assert.deepEqual(k("31-shuffle-off", "S"), [["S", "shuffle"], { cmd: "shuffle", on: true }, "none"]);
    assert.deepEqual(k("30-modes-default", "L"), [["L", "repeat one"], { cmd: "repeat", mode: "one" }, "none"]);
    assert.deepEqual(k("32-repeat-one", "L"), [["L", "repeat off"], { cmd: "repeat", mode: "off" }, "none"]);
    assert.deepEqual(k("33-ended", "L"), [["L", "repeat all"], { cmd: "repeat", mode: "all" }, "none"]);
    // A row selected: S and L still act, unnamed.
    const s = load("30-modes-default", NOW);
    const sel = T.key(ui(s, NOW), s, "Down", false).ui;
    assert.ok(!T.hints(s, sel).some(h => h[0] === "S" || h[0] === "L"));
    assert.deepEqual(T.key(sel, s, "L", false).effect.cmd, { cmd: "repeat", mode: "one" });
    // The footer as drawn for the defaults.
    assert.deepEqual(T.hints(s, ui(s, NOW)).map(h => h[0]), ["Space", "N", "S", "L", "Y", "X", "C", "G", "Esc"]);
});

t("every heading and wording in every combination of shuffle, repeat, composer, new tunes ready and ended", () => {
    const base = load("31-shuffle-off", NOW).snap;
    const NEW = { name: "Neon Harbour", file: "20261123-080000-104bpm-A-minor", bpm: 104, key: "A minor", length: 175.6, kept: false, new: true, pinned: false, pos: null };
    let seen = 0;
    for (const shuffle of [true, false])
        for (const repeat of ["all", "one", "off"])
            for (const composing of [true, false])
                for (const fresh of [true, false])
                    for (const ended of [true, false]) {
                        // A round ends only with nothing new ready, and only under repeat off.
                        if (ended && (fresh || repeat !== "off"))
                            continue;
                        const kept = shuffle ? [Object.assign({}, base.queue[0], { pos: null })] : base.queue;
                        const queue = ended ? [] : (fresh ? [NEW] : []).concat(kept);
                        const st = edit("31-shuffle-off", {
                            shuffle, repeat, composing, ended, queue,
                            ready: fresh ? 1 : 0,
                            keptPlaying: !fresh && !ended,
                            tune: ended ? null : base.tune,
                            player: ended ? "none" : "playing",
                            canNext: !ended,
                            model: Object.assign({}, base.model, { state: composing ? "idle" : "unloaded" })
                        });
                        const u = ui(st, NOW);
                        const p = T.view(st, u).player;
                        const at = `${shuffle} ${repeat} ${composing} ${fresh} ${ended}`;
                        let now = "Jazz · kept tunes";
                        if (ended)
                            now = "Jazz";
                        else if (repeat === "one")
                            now = "Jazz · repeating";
                        assert.equal(p.now.head, now, at);
                        let next;
                        if (ended)
                            next = composing ? "0 ready" : "nothing";
                        else if (repeat === "one")
                            next = "after the repeat";
                        else if (fresh)
                            next = "1 ready";
                        else
                            next = shuffle ? "from 14 kept, shuffled" : "4 of 14, in the order made";
                        assert.equal(p.next.head, next, at);
                        const tunes = p.next.rows.filter(r => r.kind === "tune");
                        assert.ok(tunes.every(r => r.dim === (repeat === "one")), at);
                        assert.deepEqual(tunes.map(r => r.tag), queue.map(q => q.new ? "new" : ""), at);
                        // New tunes carry no number; kept ones their place (5, 6, 7 in the fixture), or their turn with shuffle on.
                        assert.deepEqual(tunes.map(r => r.n), ended ? [] : (fresh ? [""] : []).concat(shuffle ? [1] : [5, 6, 7]), at);
                        const wait = lines(p).filter(l => l.includes("until the repeat ends"));
                        assert.deepEqual(wait, repeat === "one" && fresh ? ["1 new tune waits until the repeat ends."] : [], at);
                        assert.deepEqual([p.now.name, p.now.meta], ended ? ["Played all 14 Jazz tunes", "Space starts over. L turns repeat on."] : ["Lazy Avenue", "139 BPM · C major"], at);
                        const h = T.hints(st, u);
                        assert.deepEqual(h.find(x => x[0] === "Space"), ["Space", ended ? "start over" : "pause"], at);
                        assert.deepEqual(h.find(x => x[0] === "L"), ["L", `repeat ${{ all: "one", one: "off", off: "all" }[repeat]}`], at);
                        assert.equal(h.some(x => x[0] === "Y"), !ended, at);
                        seen++;
                    }
    assert.equal(seen, 2 * 3 * 2 * 2 + 2 * 2);
    // Two new tunes waiting: the plural, in the composer's well under its first line.
    const two = T.view(load("32-repeat-one", NOW), ui(load("32-repeat-one", NOW), NOW)).player;
    assert.deepEqual(lines(two), ["Makes Jazz, keeps 2 ahead | resting, queue is full", "2 new tunes wait until the repeat ends."]);
    assert.deepEqual(rows(two), [["", "Neon Harbour", "104 BPM · A minor", "2:55"], ["", "Slow Signal", "118 BPM · E minor", "2:50"]]);
    assert.deepEqual(T.hints(load("32-repeat-one", NOW), ui(load("32-repeat-one", NOW), NOW)).map(h => h.join(" ")),
        ["Space pause", "N next", "S shuffle", "L repeat off", "Y share", "X scrap Lazy Avenue", "C composer off", "G genre", "Esc close"]);
});

t("repeat off at the end of the round: the ended state as drawn, Space starts over", () => {
    const st = load("33-ended", NOW);
    const u = ui(st, NOW);
    const p = T.view(st, u).player;
    assert.deepEqual([p.now.name, p.now.nameTone, p.now.meta, p.now.main, p.now.mainLit, p.now.nextLit, p.now.wave, p.now.time], ["Played all 14 Jazz tunes", "soft", "Space starts over. L turns repeat on.", "play", true, false, null, null]);
    assert.deepEqual([p.next.head, p.next.rows], ["nothing", []]);
    assert.deepEqual(T.hints(st, u), [["Space", "start over"], ["S", "shuffle"], ["L", "repeat all"], ["C", "composer on"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(u, st, "Space", false).effect.cmd, { cmd: "toggle" });
    assert.equal(T.key(u, st, "Space", true).effect.kind, "none");
    for (const k of ["Y", "X", "N"])
        assert.equal(T.key(u, st, k, false).effect.kind, "none", k);
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "" });
    assert.equal(T.needsTick(st, u), false);
    // One kept tune.
    const one = edit("33-ended", { keptTotal: 1, genres: st.snap.genres.map(g => g.id === "jazz" ? Object.assign({}, g, { kept: 1 }) : g) });
    assert.equal(T.view(one, ui(one, NOW)).player.now.name, "Played all 1 Jazz tune");
});

t("kept for good: the star beside the playing tune's name and in its queue row; shuffle off numbers kept rows by their place", () => {
    const p = viewAt("34-pinned").player;
    assert.equal(p.now.badge, "★ kept for good");
    assert.deepEqual(p.next.rows.map(r => [r.name, r.star, r.tag, r.dim]), [["Brass Lantern", true, "", false]]);
    const plain = viewAt("30-modes-default").player;
    assert.equal(plain.now.badge, "");
    assert.deepEqual(plain.next.rows.map(r => r.star), [false]);
    assert.deepEqual(rows(viewAt("31-shuffle-off").player).map(r => [r[0], r[1]]), [[5, "Brass Lantern"], [6, "Quiet Ledger"], [7, "Late Tram"]]);
});

t("the share sheet: Y on the playing tune or the selected row, the info line, the rows in order", () => {
    const [st, u, e] = sheet("30-modes-default");
    assert.deepEqual(e, { kind: "send", cmd: { cmd: "share_info", name: "Lazy Avenue" } });
    let v = T.view(st, u);
    assert.equal(v.kind, "share");
    assert.deepEqual([v.share.head, v.share.name, v.share.meta, v.share.error], ["Jazz", "Lazy Avenue", "Asking the tunes service…", ""]);
    assert.deepEqual(v.share.rows.map(r => r.key), ["F", "P", "O", "E", "K"]);
    assert.equal(T.needsTick(st, u), true);
    // Nothing acts before the service has described the tune.
    for (const k of T.SHARE_KEYS.concat(["Enter"]))
        assert.equal(T.key(u, st, k, false).effect.kind, "none", k);
    const d = T.answer(u, st, SHARE[0], NOW);
    assert.equal(d.waiting, null);
    v = T.view(st, d);
    assert.deepEqual([v.share.head, v.share.name, v.share.meta], ["Jazz", "Lazy Avenue", "139 BPM · C major · 2:57 · MP3, 4.1 MB"]);
    assert.deepEqual(v.share.rows.map(r => [r.key, r.label, r.sub, r.right, r.sel]), [
        ["F", "Copy the file", "paste it into a chat, a mail or a folder", "", true],
        ["P", "Copy its path", "~/Music/Tunes/Jazz/20261123-070612-139bpm-C-major.mp3", "", false],
        ["O", "Show it in the file manager", "", "", false],
        ["E", "Export a copy", "to ~/Music/Tunes/Exports/Jazz - Lazy Avenue.mp3", "", false],
        ["K", "Keep it for good", "never removed by the newest-50 rule", "off", false]
    ]);
    assert.deepEqual(T.hints(st, d), [["↑↓", "move"], ["Enter", "do it"], ["F P O E K", "directly"], ["Esc", "back"]]);
    assert.equal(T.needsTick(st, d), false);
    // Without "keep" in the snapshot, no figure.
    const nokeep = edit("30-modes-default", { keep: null });
    assert.equal(T.view(nokeep, d).share.rows[4].sub, "never removed by the rule that keeps the newest");
    // Without a home, the path in full.
    assert.equal(T.view(st, Object.assign({}, d, { home: "" })).share.rows[1].sub, LAZY);
    // A line for another tune changes nothing.
    assert.equal(T.answer(u, st, SHARE[5], NOW), u);
    // The selected row: its tune, by index; a pinned one reads on.
    const [, r, re] = sheet("30-modes-default", ["Down"]);
    assert.deepEqual(re.cmd, { cmd: "share_info", name: "Brass Lantern", i: 0 });
    const b = T.answer(r, st, SHARE[5], NOW);
    assert.deepEqual([T.view(st, b).share.name, T.view(st, b).share.meta, T.view(st, b).share.rows[4].right], ["Brass Lantern", "112 BPM · F major · 2:54 · MP3, 980 kB", "on"]);
    // Nothing to share: the job row selected, or no tune.
    const job = load("11-after-scrap", NOW);
    assert.equal(T.key(press(job, ui(job, NOW), ["Down", "Down"]).ui, job, "Y", false).effect.kind, "none");
    assert.equal(T.key(ui(load("08-nothing-kept", NOW), NOW), load("08-nothing-kept", NOW), "Y", false).effect.kind, "none");
});

t("the share sheet's keys: Up/Down and Enter, the letters, Esc, held keys once", () => {
    const [st, d] = described("30-modes-default");
    const sel = list => T.view(st, press(st, d, list).ui).share.rows.findIndex(r => r.sel);
    assert.deepEqual([sel(["Down"]), sel(["Down", "Down", "Down", "Down", "Down", "Down"]), sel(["Up"]), sel(["Down", "Down", "Up"])], [1, 4, 0, 1]);
    assert.equal(T.view(st, T.key(d, st, "Down", true).ui).share.rows[1].sel, true);
    const enter = T.key(press(st, d, ["Down"]).ui, st, "Enter", false);
    assert.deepEqual(enter.effect, { kind: "run", cmd: null, run: { what: "path", command: ["wl-copy", "--", LAZY] } });
    assert.deepEqual(T.key(d, st, "F", false).effect.run, { what: "file", command: ["wl-copy", "--type", "text/uri-list", "--", "file://" + LAZY] });
    assert.deepEqual(T.key(d, st, "O", false).effect.run, { what: "show", command: ["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1", "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems", `['file://${LAZY}']`, "''"] });
    assert.deepEqual(T.key(d, st, "E", false).effect, { kind: "send", cmd: { cmd: "export", name: "Lazy Avenue" } });
    assert.deepEqual(T.key(d, st, "K", false).effect, { kind: "send", cmd: { cmd: "pin", on: true, name: "Lazy Avenue" } });
    // A shell action closes the sheet at once; the command's end says the rest.
    const f = T.key(d, st, "F", false).ui;
    assert.deepEqual([f.mode, f.share, f.running.what], ["player", null, "file"]);
    for (const k of T.SHARE_KEYS.concat(["Enter", "Esc"]))
        assert.equal(T.key(d, st, k, true).effect.kind, "none", `${k} held`);
    const esc = T.key(d, st, "Esc", false);
    assert.deepEqual([esc.ui.mode, esc.ui.share, esc.ui.waiting, esc.effect.kind], ["player", null, null, "none"]);
    // Esc while asking: the late answer is not waited for.
    const [, asking] = sheet("30-modes-default");
    const left = T.key(asking, st, "Esc", false).ui;
    assert.equal(T.answer(left, st, SHARE[0], NOW), left);
    // The player's keys do nothing in the sheet.
    for (const k of ["Space", "N", "S", "L", "Y", "X", "C", "G", "Z", "R"])
        assert.equal(T.key(d, st, k, false).effect.kind, "none", k);
});

t("the service's description is taken by name or by file: the name can change to the title on its way", () => {
    const [st, u] = sheet("30-modes-default");
    const titled = T.answer(u, st, Object.assign({}, SHARE[0], { name: "Invented Title" }), NOW);
    assert.deepEqual([titled.waiting, titled.share.info.name], [null, "Invented Title"]);
    const other = Object.assign({}, SHARE[0], { name: "Invented Title", path: "/home/someone/Music/Tunes/Jazz/20261101-090000-112bpm-F-major.mp3" });
    assert.equal(T.answer(u, st, other, NOW), u);
});

t("a path with spaces and quotes: the URI percent-encoded, the GVariant quoted", () => {
    const [st, u] = sheet("30-modes-default");
    const odd = "/home/someone/Music/Tunes/Deep house/it's #1.mp3";
    const d = T.answer(u, st, Object.assign({}, SHARE[0], { path: odd }), NOW);
    assert.equal(T.key(d, st, "F", false).effect.run.command[4], "file:///home/someone/Music/Tunes/Deep%20house/it's%20%231.mp3");
    assert.equal(T.key(d, st, "O", false).effect.run.command[9], "['file:///home/someone/Music/Tunes/Deep%20house/it\\'s%20%231.mp3']");
    assert.deepEqual(T.key(d, st, "P", false).effect.run.command, ["wl-copy", "--", odd]);
});

t("each action's result in the footer: the commands' successes and failures, ShowItems falling back to the folder", () => {
    const [st, d] = described("30-modes-default");
    const after = (letter, result) => T.ran(T.key(d, st, letter, false).ui, result, NOW);
    const said = r => T.notice(st, r.ui);
    assert.equal(said(after("F", { code: 0 })), "Copied Lazy Avenue as a file. Paste it anywhere.");
    assert.equal(said(after("P", { code: 0 })), "Copied the path of Lazy Avenue.");
    assert.equal(said(after("O", { code: 0 })), "Showed Lazy Avenue in the file manager.");
    assert.equal(said(after("F", { code: 1, said: "Failed to connect to a Wayland server" })), "Failed to connect to a Wayland server");
    assert.equal(said(after("P", { code: 1, said: "" })), "wl-copy exited with status 1.");
    assert.equal(said(after("P", { failedToStart: true })), "wl-copy could not be started.");
    assert.equal(said(after("F", { timedOut: true, code: 15 })), `wl-copy did not finish within ${T.RUN_S} s.`);
    // ShowItems refused: the folder opens instead.
    const show = after("O", { code: 1, said: "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable" });
    assert.deepEqual(show.effect, { kind: "run", cmd: null, run: { what: "open", command: ["uwsm", "app", "--", "xdg-open", "/home/someone/Music/Tunes/Jazz"] } });
    assert.equal(said(show), "");
    assert.equal(said(T.ran(show.ui, { code: 0 }, NOW)), "Opened the folder of Lazy Avenue.");
    assert.equal(said(T.ran(show.ui, { failedToStart: true }, NOW)), "uwsm could not be started.");
    assert.equal(said(T.ran(show.ui, { code: 2, said: "uwsm: no such unit" }, NOW)), "uwsm: no such unit");
    // ShowItems stopped by the watchdog falls back too.
    assert.equal(T.ran(T.key(d, st, "O", false).ui, { timedOut: true }, NOW).effect.run.what, "open");
    // The line goes after NOTICE_S; the tick runs until then.
    const ok = after("F", { code: 0 }).ui;
    const paused = edit("30-modes-default", { player: "paused" });
    assert.deepEqual([T.needsTick(paused, ok), T.needsTick(paused, Object.assign({}, ok, { now: NOW + T.NOTICE_S }))], [true, false]);
    assert.equal(T.notice(st, Object.assign({}, ok, { now: NOW + T.NOTICE_S })), "");
    // While a command runs, the next F, P or O waits; nothing ran: nothing changes.
    const running = T.key(d, st, "F", false).ui;
    const again = T.key(T.key(running, st, "Y", false).ui, st, "F", false);
    assert.equal(again.effect.kind, "none");
    const idle = ui(st, NOW);
    assert.equal(T.ran(idle, { code: 0 }, NOW).ui, idle);
    assert.equal(T.ran(null, { code: 0 }, NOW).ui, null);
});

t("export and keep for good: the service's answer closes the sheet with its line; a refusal says its own words", () => {
    const [st, d] = described("30-modes-default");
    const e = T.key(d, st, "E", false).ui;
    assert.deepEqual(e.waiting.kind, "export");
    // Waiting: nothing else is sent.
    for (const k of ["E", "K", "F"])
        assert.equal(T.key(e, st, k, false).effect.kind, "none", k);
    // A pin's answer is not an export's.
    assert.equal(T.answer(e, st, SHARE[2], NOW), e);
    let r = T.answer(e, st, SHARE[1], NOW);
    assert.deepEqual([r.mode, r.share, r.waiting, T.notice(st, r)], ["player", null, null, "Exported Lazy Avenue to ~/Music/Tunes/Exports."]);
    const k = T.key(d, st, "K", false).ui;
    assert.equal(T.answer(k, st, SHARE[1], NOW), k);
    assert.equal(T.answer(k, st, Object.assign({}, SHARE[2], { what: "export" }), NOW), k);
    assert.equal(T.notice(st, T.answer(k, st, SHARE[2], NOW)), "Lazy Avenue is kept for good.");
    const [, b] = described("30-modes-default", SHARE[5]);
    assert.deepEqual(T.key(b, st, "K", false).effect.cmd, { cmd: "pin", on: false, name: "Brass Lantern", i: 0 });
    assert.equal(T.notice(st, T.answer(T.key(b, st, "K", false).ui, st, Object.assign({}, SHARE[3], { name: "Brass Lantern" }), NOW)), "Brass Lantern is no longer kept for good.");
    // The queue moved while the sheet was open: the command follows the
    // tune to its place, or names it by its file when it is nowhere (it has
    // finished, and the service finds it in the genre's folder).
    const moved = edit("30-modes-default", { queue: [load("31-shuffle-off", NOW).snap.queue[1], load("30-modes-default", NOW).snap.queue[0]] });
    assert.deepEqual(T.key(b, moved, "E", false).effect.cmd, { cmd: "export", name: "Brass Lantern", i: 1 });
    const gone = edit("30-modes-default", { queue: [] });
    assert.deepEqual(T.key(b, gone, "E", false).effect.cmd, { cmd: "export", name: "20261101-090000-112bpm-F-major" });
    const ended = edit("30-modes-default", { tune: load("31-shuffle-off", NOW).snap.queue[2], queue: [] });
    assert.deepEqual(T.key(d, ended, "K", false).effect.cmd, { cmd: "pin", on: true, name: "20261123-070612-139bpm-C-major" });
    // Refusals: for the info (the tune gone meanwhile), the export, the pin.
    const [, asking] = sheet("30-modes-default");
    for (const w of [asking, e, k]) {
        r = T.answer(w, st, SHARE[4], NOW);
        assert.deepEqual([r.mode, r.share, r.waiting, T.notice(st, r)], ["player", null, null, "Lazy Avenue is no longer there."]);
    }
    assert.equal(T.notice(st, T.answer(e, st, { event: "share_result", ok: false }, NOW)), "The tunes service refused.");
});

t("share commands unanswered: the wait runs out and the sheet says so; the link dropping ends it", () => {
    const [st, asking] = sheet("30-modes-default");
    const late = Object.assign({}, asking, { now: NOW + T.WAIT_S });
    assert.equal(T.needsTick(st, late), false);
    assert.deepEqual([T.view(st, late).share.error, T.view(st, late).share.meta], [T.NOT_ANSWERED, ""]);
    // A late answer still lands.
    assert.equal(T.answer(late, st, SHARE[0], NOW).share.info.name, "Lazy Avenue");
    const [, d] = described("30-modes-default");
    const e = T.key(d, st, "E", false).ui;
    const eLate = Object.assign({}, e, { now: NOW + T.WAIT_S });
    assert.equal(T.view(st, eLate).share.error, T.NOT_ANSWERED);
    assert.equal(T.key(eLate, st, "E", false).effect.kind, "send");
    // The link drops: the info's wait goes back to the player, saying so;
    // an export's stays in the sheet, saying so, and can be sent again.
    const down = T.linkDown(asking, NOW);
    assert.deepEqual([down.mode, down.waiting, T.notice(st, down)], ["player", null, T.NOT_ANSWERED]);
    const eDown = T.linkDown(e, NOW);
    assert.deepEqual([eDown.mode, T.view(st, eDown).share.error], ["share", T.NOT_ANSWERED]);
    assert.equal(T.key(eDown, st, "E", false).effect.kind, "send");
});

t("share and genre lines: each answers only what it was asked; healthy; no change to the state", () => {
    const st = load("30-modes-default", NOW);
    for (const ev of SHARE) {
        assert.equal(T.healthy(ev), true);
        assert.equal(T.apply(st, ev, NOW), st);
    }
    const [, asking] = sheet("30-modes-default");
    for (const ev of RESULTS.concat([JAZZ]))
        assert.equal(T.answer(asking, st, ev, NOW), asking, ev.event);
    const [jst, editing] = jazzEditor();
    const saving = T.key(editing, jst, "CtrlS", false).ui;
    for (const ev of SHARE)
        assert.equal(T.answer(saving, jst, ev, NOW), saving);
});

t("a share notice in the player: in place of the undo line while it shows, then the undo line again", () => {
    const st = load("11-after-scrap", NOW);
    const u = Object.assign(ui(st, NOW), { notice: { text: "Copied the path of Quiet Ledger.", until: NOW + 3 } });
    assert.deepEqual([T.notice(st, u), T.undoLine(st, u)], ["Copied the path of Quiet Ledger.", ""]);
    const later = Object.assign({}, u, { now: NOW + 3 });
    assert.deepEqual([T.notice(st, later), T.undoLine(st, later)], ["", "Scrapped Lazy Avenue. Z brings it back for 7 s."]);
    // G and Y clear it.
    assert.equal(T.key(u, st, "G", false).ui.notice, null);
    assert.equal(T.key(u, st, "Y", false).ui.notice, null);
});

t("S, L and Y do nothing in the editor, the delete question, the setup cards and the link's cards", () => {
    const [st, editing] = jazzEditor();
    for (const k of ["S", "L", "Y", "F", "P", "O", "K"])
        assert.deepEqual(T.key(editing, st, k, false), { ui: editing, effect: { kind: "pass", cmd: null } }, k);
    const [, c] = chooserOf("30-modes-default");
    const asked = T.key(c, st, "D", false).ui;
    assert.equal(asked.mode, "ask");
    for (const k of ["S", "L", "Y"]) {
        assert.equal(T.key(asked, st, k, false).effect.kind, "none", k);
        assert.equal(T.key(c, st, k, false).effect.kind, "none", k);
    }
    for (const f of ["01-not-set-up", "02-downloading", "03-download-failed", "18-protocol-v2"]) {
        const s = load(f, NOW);
        for (const k of ["S", "L", "Y"])
            assert.equal(T.key(ui(s, NOW), s, k, false).effect.kind, "none", `${f} ${k}`);
    }
    const lost = T.linkLost(T.initial(), "exited", 3, "", NOW + 2);
    assert.equal(T.key(ui(lost, NOW), lost, "S", false).effect.kind, "none");
});

t("the genre editor refuses the name Exports, ignoring case", () => {
    const g = [{ id: "jazz", name: "Jazz" }];
    const v = name => T.check({ name, caption: "x", turns: "", lo: "70", hi: "120" }, g, null).errors.name;
    for (const n of ["Exports", "exports", " EXPORTS "])
        assert.equal(v(n), "Exports is the folder for exported copies; pick another name.", n);
    assert.deepEqual([v("Exports 2"), v("Export")], ["", ""]);
    const [st, c] = chooserOf("30-modes-default");
    const e = T.view(st, T.typed(T.key(c, st, "A", false).ui, "name", "Exports")).editor;
    assert.equal(e.fields.name.error, "Exports is the folder for exported copies; pick another name.");
});

t("the footer wraps inside 420 px: every hint fits on a line in every state, a long name elides in its hint", () => {
    // 420 px less the 1 px border each side and 14 px padding each side, in
    // 11 px Fira Code (0.6 em a character).
    assert.equal(T.FOOTER_CHARS, Math.floor((420 - 2 - 28) / (11 * 0.6)));
    const len = h => Array.from(`${h[0]} ${h[1]}`).length;
    const LONG = "A Very Long Tune Name That Somebody Typed Into The File Title Tag";
    const long = q => Object.assign({}, q, { name: LONG });
    let checked = 0;
    const every = (st, u, at) => {
        for (const h of T.hints(st, u)) {
            assert.ok(len(h) <= T.FOOTER_CHARS, `${at}: ${h.join(" ")}`);
            checked++;
        }
    };
    for (const f of fixtures().filter(f => !/^(26|27|35)-/.test(f))) {
        const s = load(f, NOW);
        const variants = [s];
        if (s.snap && s.snap.tune)
            variants.push(edit(f, { tune: long(s.snap.tune), queue: s.snap.queue.map(long) }));
        for (const st of variants)
            for (const mode of ["player", "chooser"])
                for (const keys of [[], ["Down"], ["Down", "Down"], ["Y"]]) {
                    const u = press(st, ui(st, NOW, { mode }), keys).ui;
                    every(st, u, `${f} ${mode} ${keys}`);
                }
    }
    const [st, d] = described("30-modes-default");
    every(st, d, "share sheet");
    assert.ok(checked > 1000);
    // The long name: elided in the hint, kept whole in the row and the command.
    const st2 = edit("30-modes-default", { tune: long(load("30-modes-default", NOW).snap.tune) });
    const x = T.hints(st2, ui(st2, NOW)).find(h => h[0] === "X");
    assert.equal(len(x), T.FOOTER_CHARS);
    assert.ok(x[1].startsWith("scrap A Very Long Tune Name") && x[1].endsWith("…"));
    assert.deepEqual(T.key(ui(st2, NOW), st2, "X", false).effect.cmd, { cmd: "scrap", name: LONG });
    assert.equal(T.view(st2, ui(st2, NOW)).player.now.name, LONG);
});

t("unknown mode values fall back to the defaults", () => {
    const st = T.apply(T.initial(), { event: "state", v: 1, setup: "ready", genre: "a", genres: [{ id: "a" }], shuffle: "no", repeat: "twice", ended: "yes", round_left: -3, keep: "fifty", tune: { name: "T", new: 1, pinned: "yes", pos: -2 } }, NOW);
    const s = st.snap;
    assert.deepEqual([s.shuffle, s.repeat, s.ended, s.roundLeft, s.keep], [true, "all", false, 0, null]);
    assert.deepEqual([s.tune.new, s.tune.pinned, s.tune.pos], [false, false, null]);
    const off = T.apply(T.initial(), { event: "state", v: 1, setup: "ready", shuffle: false, repeat: "off" }, NOW).snap;
    assert.deepEqual([off.shuffle, off.repeat], [false, "off"]);
});

console.log(`ok: ${n} tunes-panel tests`);
