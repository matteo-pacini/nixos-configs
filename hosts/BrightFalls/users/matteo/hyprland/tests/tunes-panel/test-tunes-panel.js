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
    assert.deepEqual(T.hints(st, u), [["←↑↓→", "move"], ["Enter", "play Lo-fi"], ["Esc", "close"]]);
    const sel = list => press(st, u, list).ui.sel;
    assert.equal(sel(["Right"]), 1);
    assert.equal(sel(["Up"]), 0);
    assert.equal(sel(["Down", "Down", "Down"]), 6);
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
    assert.deepEqual(T.hints(st, g.ui), [["←↑↓→", "move"], ["Enter", "back to Jazz"], ["Esc", "back"]]);
    const back = T.key(g.ui, st, "Enter", false);
    assert.deepEqual([back.ui.mode, back.effect.kind], ["player", "none"]);
    assert.deepEqual(T.hints(st, T.key(g.ui, st, "Left", false).ui)[1], ["Enter", "play Deep house"]);
    assert.equal(T.key(g.ui, st, "Esc", false).ui.mode, "player");
    // With nothing playing the selected genre says "selected", and picking it
    // starts nothing.
    const quiet = load("08-nothing-kept", NOW);
    const q = T.key(ui(quiet, NOW), quiet, "G", false).ui;
    assert.equal(T.view(quiet, q).chooser.cells[2].sub, "selected");
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
    assert.deepEqual(rows(p), [[1, "Brass Lantern", "112 BPM · F major", "2:54"], [2, "Quiet Ledger", "96 BPM · D minor", "2:49"]]);
    assert.ok(p.next.rows.every(r => r.kind === "tune" && !r.sel));
    assert.deepEqual([p.composer.on, p.composer.label], [true, "on"]);
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | resting, queue is full"]);
    assert.equal(p.composer.lines[0].em, "Jazz");
    assert.equal(p.composer.lines[0].rightTone, "green");
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["N", "next"], ["X", "scrap Lazy Avenue"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
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
    assert.deepEqual(rows(p), [[1, "Being rendered", "about 0:40 left · written in 1:04", "composing"], [2, "Not started", "after the one above", ""]]);
    const job = p.next.rows[0];
    assert.deepEqual([job.kind, job.nTone, job.rightTone], ["job", "cyan", "cyan"]);
    assert.ok(Math.abs(job.bar - 18 / 58) < 1e-9);
    assert.equal(p.next.rows[1].kind, "placeholder");
    assert.deepEqual(lines(p), ["Makes Jazz, keeps 2 ahead | using 3.9 GiB of RAM", "ACE-Step 1.5 Turbo · 4B Q8 · Radeon 780M"]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    assert.equal(T.key(ui(st, NOW), st, "Space", false).effect.kind, "none");
    assert.equal(T.key(ui(st, NOW), st, "X", false).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "dim", text: "", dot: "cyan" });
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
});

t("the job row: the time left, never negative, never longer than the estimate", () => {
    const st = load("10-writing", NOW);
    const sub = now => T.view(st, ui(st, now)).player.next.rows[0].sub;
    const bar = now => T.view(st, ui(st, now)).player.next.rows[0].bar;
    // 120 s expected, 50 s spent.
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
    assert.deepEqual(rows(p), [[1, "Being written", "about 1:10 left", "composing"], [2, "Not started", "after the one above", ""]]);
    assert.deepEqual(p.next.rows.map(r => r.nameTone), ["soft", "dim"]);
    // Held with one ready: one placeholder, with no job above it.
    assert.deepEqual(rows(viewAt("12-held-game").player), [[1, "Dusty Notebook", "88 BPM · A major", "2:52"], [2, "Not started", "", ""]]);
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
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["N", "next"], ["X", "scrap Brass Lantern"], ["C", "composer on"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "C", false).effect.cmd, { cmd: "compose", on: true });
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Jazz", dot: "" });
    const lofi = viewAt("09-kept-tunes").player;
    assert.deepEqual([lofi.now.head, lofi.next.head], ["Lo-fi · kept tunes", "from 31 kept, shuffled"]);
    assert.deepEqual(lines(lofi), ["On, it makes new Lo-fi and keeps 2 ahead."]);
});

t("a genre with nothing kept: nothing happens by itself", () => {
    const st = load("08-nothing-kept", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.deepEqual([p.now.head, p.now.name, p.now.nameTone, p.now.meta], ["Synthwave", "No Synthwave tunes yet", "soft", "Turn the composer on to make some."]);
    assert.deepEqual([p.now.mainLit, p.now.nextLit, p.now.wave], [false, false, null]);
    assert.equal(p.next.head, "nothing");
    // expect: 62 + 58 s is 2 min.
    assert.deepEqual(lines(p), ["On, it makes Synthwave and keeps 2 ahead.", "A tune takes about 2 min and 6 GiB of RAM while it is made."]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["C", "composer on"], ["G", "genre"], ["Esc", "close"]]);
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
    assert.deepEqual(d1.row, { kind: "queue", i: 0, name: "Brass Lantern" });
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
    assert.deepEqual(T.hints(st, d2), [["↑↓", "select"], ["Enter", "play it now"], ["X", "scrap Quiet Ledger"], ["Space", "pause"], ["Esc", "close"]]);
    const play = T.key(d2, st, "Enter", false);
    assert.deepEqual(play.effect.cmd, { cmd: "play", i: 1 });
    assert.equal(play.ui.row, null);
    const scrap = T.key(d2, st, "X", false);
    assert.deepEqual(scrap.effect.cmd, { cmd: "scrap", i: 1 });
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
    assert.deepEqual(T.key(d2, moved, "X", false).effect.cmd, { cmd: "scrap", i: 0 });
    // ...and is gone with it.
    const gone = edit("05-queue-full", { queue: [st.snap.queue[0]], ready: 1 });
    assert.deepEqual(T.view(gone, d2).player.next.rows.filter(r => r.kind === "tune").map(r => r.sel), [false]);
    assert.deepEqual(T.key(d2, gone, "X", false).effect.cmd, { cmd: "scrap" });
    assert.equal(T.key(d2, gone, "Enter", false).effect.kind, "none");
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
    assert.deepEqual(T.key(ui(st, NOW), st, "X", false).effect.cmd, { cmd: "scrap" });
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
    assert.deepEqual(rows(p), [[1, "Quiet Ledger", "96 BPM · D minor", "2:49"], [2, "Being written", "about 1:50 left", "composing"]]);
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
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["X", "scrap Dusty Notebook"], ["R", "try now"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
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

t("no device: as built, with C to turn the composer off", () => {
    const st = load("14-no-device", NOW);
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "device");
    assert.deepEqual(v.setup.rows, [["found", "1 device, not this one"]]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["R", "try now"], ["C", "composer off"], ["G", "genre"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "C", false).effect.cmd, { cmd: "compose", on: false });
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
    assert.deepEqual(T.globalScrap(load("05-queue-full", NOW), NOW), { cmd: { cmd: "scrap" }, summary: "Scrapped Lazy Avenue", body: "Super+Shift+M again within 10 s brings it back." });
    const after = load("11-after-scrap", NOW);
    assert.deepEqual(T.globalScrap(after, NOW), { cmd: { cmd: "undo" }, summary: "Brought back Lazy Avenue", body: "It plays next." });
    // Once the undo has run out, a scrap of what plays.
    assert.equal(T.globalScrap(after, NOW + 10).summary, "Scrapped Brass Lantern");
    // Nothing plays: nothing.
    assert.equal(T.globalScrap(load("06-first-tune", NOW), NOW), null);
    // Nothing plays but an undo is offered: the undo.
    assert.equal(T.globalScrap(edit("11-after-scrap", { tune: null, player: "none" }), NOW).cmd.cmd, "undo");
    assert.equal(T.globalScrap(load("17-paused", NOW), NOW).cmd.cmd, "scrap");
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

t("unknown values fall back to the empty ones", () => {
    const st = T.apply(T.initial(), { event: "state", v: 1, setup: "ready", genre: "a", genres: [{ id: "a" }], composing: "yes", job: { stage: "dancing", started: "x", expect_s: -4 }, queue: [5, null, { name: 3 }], undo: { until: 9 }, expect: { writing_s: 0, rendering_s: 1 }, ahead: "two" }, NOW);
    const s = st.snap;
    assert.equal(s.composing, false);
    assert.deepEqual(s.job, { stage: "writing", started: null, expect: null, written: null });
    assert.deepEqual(s.queue, [{ name: "", bpm: null, key: "", length: null, kept: false }]);
    assert.equal(s.undo, null);
    assert.equal(s.expect, null);
    assert.equal(s.ahead, 2);
    assert.equal(s.stopped, false);
    assert.equal(T.view(st, ui(st, NOW)).kind, "player");
});

console.log(`ok: ${n} tunes-panel tests`);
