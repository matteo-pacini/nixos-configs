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
const GIB = 1073741824;

function events(name, base) {
    const text = fs.readFileSync(path.join(__dirname, "fixtures", name + ".jsonl"), "utf8");
    return text.split("\n").filter(l => l.trim() !== "").map(l => JSON.parse(l.replace(/"@([+-]\d+)"/g, (m, s) => String(base + Number(s)))));
}
function load(name, base, st) {
    return events(name, base).reduce((s, ev) => T.apply(s, ev, base), st || T.initial());
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

t("formatting", () => {
    assert.equal(T.clock(0), "0:00");
    assert.equal(T.clock(84), "1:24");
    assert.equal(T.clock(172.4), "2:52");
    assert.equal(T.clock(59.99), "0:59");
    assert.equal(T.clock(725), "12:05");
    assert.equal(T.clock(null), "–:––");
    assert.equal(T.clock(-1), "–:––");
    assert.equal(T.gib(6 * GIB), "6 GiB");
    assert.equal(T.gib(19.3 * GIB), "19.3 GiB");
    assert.equal(T.gib(7.57 * GIB, 2), "7.57 GiB");
    assert.equal(T.gib(226.4 * GIB), "226 GiB");
    assert.equal(T.gib(99.96 * GIB), "100 GiB");
    assert.equal(T.gib(null), "");
    assert.equal(T.rate(28400000), "28 MB/s");
    assert.equal(T.rate(640000), "640 kB/s");
    assert.equal(T.rate(null), "");
    assert.equal(T.elapsed(12.7), "12 s");
    assert.equal(T.elapsed(65), "1 min 5 s");
    assert.equal(T.elapsed(180), "3 min");
    assert.equal(T.elapsed(-3), "0 s");
});

t("waveform columns: odd dot counts from 1 to 13, 78 of them", () => {
    const flat = T.waveColumns([]);
    assert.equal(flat.length, T.COLS);
    assert.ok(flat.every(c => c === 1));
    const cols = T.waveColumns(Array.from({ length: 78 }, (_, i) => i / 77));
    assert.equal(cols.length, 78);
    assert.ok(cols.every(c => c % 2 === 1 && c >= 1 && c <= T.ROWS));
    assert.equal(cols[0], 1);
    assert.equal(cols[77], 13);
    // 0.5 * 13 = 6.5 rounds to 7; 0.48 * 13 = 6.24 rounds to 6, made odd: 5.
    assert.deepEqual(T.waveColumns(new Array(78).fill(0.5)).slice(0, 2), [7, 7]);
    assert.deepEqual(T.waveColumns(new Array(78).fill(0.48)).slice(0, 2), [5, 5]);
    // A shorter wave is stretched over the 78 columns.
    const half = T.waveColumns([0, 1]);
    assert.deepEqual([half[0], half[38], half[39], half[77]], [1, 1, 13, 13]);
});

t("the service's lines: which apply, which reset the back-off", () => {
    const st = T.initial();
    assert.equal(st.link, "connecting");
    assert.equal(T.apply(st, null, NOW), st);
    assert.equal(T.apply(st, "state", NOW), st);
    assert.equal(T.apply(st, { event: "error", text: "x" }, NOW), st);
    assert.equal(T.apply(st, { event: "future" }, NOW), st);
    assert.equal(T.healthy({ event: "state", v: 1 }), true);
    assert.equal(T.healthy({ event: "error", text: "bad line" }), true);
    assert.equal(T.healthy({ event: "state", v: 2 }), false);
    assert.equal(T.healthy({ event: "other" }), false);
    assert.equal(T.healthy(null), false);
    assert.equal(T.healthy([1]), false);
    // Extra fields and an error reply in between change nothing.
    const s = load("20-session", NOW);
    assert.equal(s.link, "up");
    assert.equal(s.snap.genre, "jazz");
    assert.equal(s.snap.tune.name, "Late Ferry");
    assert.equal(s.snap.extra, undefined);
});

t("a protocol version other than 1", () => {
    const v = viewAt("18-protocol-v2");
    assert.equal(v.kind, "old");
    assert.equal(v.setup.title, "The tunes service is newer than this panel");
    assert.equal(v.setup.detail, "It speaks version 2 of the protocol; this panel reads version 1.");
    assert.deepEqual(hintsOf("18-protocol-v2"), [["Esc", "close"]]);
    assert.deepEqual(T.barView(load("18-protocol-v2", NOW)), { tone: "dim", text: "" });
});

t("the link: connecting, not installed, not running (exit 3), closed (other exits)", () => {
    let st = T.initial();
    let v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "connecting");
    assert.equal(v.setup.title, "Connecting to the tunes service…");
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Esc", "close"]]);
    assert.equal(T.needsTick(st, ui(st, NOW)), false);

    st = T.linkLost(T.initial(), "missing", null, "", NOW + 8);
    v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "missing");
    assert.equal(v.setup.title, "The tunes service is not installed");
    assert.equal(v.setup.detail, "desk-tunes is not on PATH. Trying again in 8 s.");
    assert.deepEqual(v.setup.rows, []);
    assert.equal(T.view(st, ui(st, NOW + 8.2)).setup.detail, "desk-tunes is not on PATH. Trying again now.");

    st = T.linkLost(load("05-playing-idle", NOW), "exited", 3, "desk-tunes: no socket at the runtime directory", NOW + 7.5);
    v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "down");
    assert.equal(v.setup.title, "The tunes service is not running");
    assert.equal(v.setup.detail, "Trying again in 8 s.");
    assert.deepEqual(v.setup.rows, [["unit", "desk-tunes.service"], ["last line", "desk-tunes: no socket at the runtime directory"]]);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["R", "try now"], ["Esc", "close"]]);
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
    // The bar does not trust the last snapshot once the link is down.
    assert.deepEqual(T.barView(st), { tone: "dim", text: "" });

    st = T.linkLost(T.initial(), "exited", 1, "", NOW + 16);
    v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "lost");
    assert.equal(v.setup.title, "The link to the tunes service closed");
    assert.equal(v.setup.detail, "Trying again in 16 s.");
    assert.deepEqual(v.setup.rows, [["unit", "desk-tunes.service"], ["last line", "exited, status 1"]]);
    assert.deepEqual(T.view(T.linkLost(st, "exited", 1, "socket closed", NOW + 4), ui(st, NOW)).setup.rows[1], ["last line", "socket closed"]);

    const r = T.key(ui(st, NOW), st, "R", false);
    assert.deepEqual(r.effect, { kind: "reattach", cmd: null });
    assert.deepEqual(T.key(ui(st, NOW), st, "R", true).effect, { kind: "none", cmd: null });
    assert.deepEqual(T.key(ui(st, NOW), st, "Space", false).effect, { kind: "none", cmd: null });

    st = T.linkLost(st, "back");
    assert.equal(st.link, "connecting");
    assert.equal(T.apply(st, events("05-playing-idle", NOW)[0], NOW).link, "up");
});

t("not set up", () => {
    const v = viewAt("01-not-set-up");
    assert.equal(v.kind, "setup");
    assert.equal(v.setup.title, "Tunes needs a music model");
    assert.equal(v.setup.detail, "ACE-Step 1.5 Turbo composes on this computer. Nothing is sent anywhere after the download.");
    assert.deepEqual(v.setup.rows, [["download", "7.57 GiB"], ["free on disk", "226 GiB"], ["memory while composing", "about 6 GiB of RAM"]]);
    assert.equal(v.setup.bar, null);
    assert.deepEqual(hintsOf("01-not-set-up"), [["Enter", "download"], ["Esc", "close"]]);
    const st = load("01-not-set-up", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "Enter", false).effect, { kind: "send", cmd: { cmd: "download" } });
    assert.deepEqual(T.key(ui(st, NOW), st, "Enter", true).effect.kind, "none");
    assert.deepEqual(T.key(ui(st, NOW), st, "G", false).effect.kind, "none");
    assert.deepEqual(T.key(ui(st, NOW), st, "Esc", false).effect.kind, "close");
    assert.deepEqual(T.barView(st), { tone: "dim", text: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
});

t("downloading", () => {
    const v = viewAt("02-downloading");
    assert.equal(v.kind, "download");
    assert.equal(v.setup.title, "Downloading the music model");
    assert.equal(v.setup.detail, "File 2 of 4: the language model.");
    assert.deepEqual(v.setup.rows, [["downloaded", "2.9 of 7.57 GiB"], ["speed", "28 MB/s"]]);
    assert.ok(Math.abs(v.setup.bar - 2.9 / 7.57) < 1e-3);
    assert.deepEqual(hintsOf("02-downloading"), [["C", "cancel"], ["Esc", "close"]]);
    const st = load("02-downloading", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "C", false).effect, { kind: "send", cmd: { cmd: "cancel_download" } });
    assert.equal(T.key(ui(st, NOW), st, "C", true).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "cyan", text: "" });
});

t("a download that stopped", () => {
    const v = viewAt("03-download-failed");
    assert.equal(v.kind, "failed");
    assert.equal(v.setup.title, "The download stopped");
    assert.equal(v.setup.detail, "checksum mismatch on the language model. Finished files are kept.");
    assert.deepEqual(v.setup.rows, [["downloaded", "2.9 of 7.57 GiB"]]);
    assert.deepEqual(hintsOf("03-download-failed"), [["Enter", "resume"], ["Esc", "close"]]);
    const st = load("03-download-failed", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "Enter", false).effect.cmd, { cmd: "download" });
});

t("the chooser, first open after setup", () => {
    const st = load("04-chooser-first", NOW);
    const u = ui(st, NOW);
    assert.equal(u.sel, 0);
    const v = T.view(st, u);
    assert.equal(v.kind, "chooser");
    assert.equal(v.chooser.title, "What do you want to hear?");
    assert.equal(v.chooser.strip, null);
    assert.equal(v.chooser.empty, "");
    assert.deepEqual(v.chooser.cells.map(c => [c.name, c.sub, c.sel]), [
        ["Lo-fi", "31 kept", true], ["Ambient", "12 kept", false], ["Synthwave", "none yet", false],
        ["Deep house", "4 kept", false], ["Jazz", "none yet", false], ["Classical", "9 kept", false],
        ["Downtempo", "none yet", false], ["Post-rock", "2 kept", false], ["Acoustic", "none yet", false]
    ]);
    // With no genre yet there is nothing to go back to.
    assert.deepEqual(T.hints(st, u), [["←↑↓→", "move"], ["Enter", "play"], ["Esc", "close"]]);
    assert.equal(T.key(u, st, "Esc", false).effect.kind, "close");
    // Moving: right, down, held down repeats, and nothing past the edges.
    const sel = list => press(st, u, list).ui.sel;
    assert.equal(sel(["Right"]), 1);
    assert.equal(sel(["Left"]), 0);
    assert.equal(sel(["Up"]), 0);
    assert.equal(sel(["Down"]), 3);
    assert.equal(sel(["Down", "Down", "Down"]), 6);
    assert.equal(sel(["Right", "Right", "Right", "Right", "Right", "Right", "Right", "Right", "Right", "Right"]), 8);
    assert.equal(sel(["Down", "Down", "Right", "Down"]), 7);
    assert.equal(T.key(u, st, "Down", true).ui.sel, 3);
    const moved = press(st, u, ["Down", "Right"]);
    assert.equal(T.view(st, moved.ui).chooser.cells.findIndex(c => c.sel), 4);
    // Enter plays the selected genre; a held Enter does not repeat it.
    const r = T.key(moved.ui, st, "Enter", false);
    assert.deepEqual(r.effect, { kind: "send", cmd: { cmd: "genre", id: "jazz" } });
    assert.equal(r.ui.mode, "player");
    assert.equal(T.key(moved.ui, st, "Enter", true).effect.kind, "none");
    // A click on a cell does the same.
    assert.deepEqual(T.pick(u, st, 7).effect.cmd, { cmd: "genre", id: "postrock" });
    assert.equal(T.pick(u, st, 99).effect.kind, "none");
    // Until the service's snapshot names the genre, the chooser stays.
    assert.equal(T.view(st, r.ui).kind, "chooser");
    assert.deepEqual(T.barView(st), { tone: "dim", text: "" });
    assert.equal(T.needsTick(st, u), false);
});

t("the chooser: G from the player, Esc back, Enter on the genre playing", () => {
    const st = load("05-playing-idle", NOW);
    const ambient = load("05-playing-idle", NOW);
    ambient.snap.genre = "classical";
    const g = T.key(ui(ambient, NOW), ambient, "G", false);
    assert.equal(g.ui.mode, "chooser");
    assert.equal(g.ui.sel, 5);
    assert.deepEqual(T.hints(ambient, g.ui), [["←↑↓→", "move"], ["Enter", "play"], ["Esc", "back"]]);
    const back = T.key(g.ui, ambient, "Esc", false);
    assert.equal(back.ui.mode, "player");
    assert.equal(back.effect.kind, "none");
    // Enter on the genre already playing goes back without a command.
    const same = T.key(T.key(ui(st, NOW), st, "G", false).ui, st, "Enter", false);
    assert.equal(same.ui.mode, "player");
    assert.equal(same.effect.kind, "none");
    assert.equal(T.needsTick(st, g.ui), false);
});

t("a genres file with no genres", () => {
    const st = load("04-chooser-first", NOW);
    st.snap = Object.assign({}, st.snap, { genres: [] });
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.chooser.empty, "The genres file lists no genres.");
    assert.deepEqual(v.chooser.cells, []);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Esc", "close"]]);
    assert.equal(T.key(ui(st, NOW), st, "Enter", false).effect.kind, "none");
});

t("playing, two tunes ready, the model idle", () => {
    const v = viewAt("05-playing-idle");
    assert.equal(v.kind, "player");
    const p = v.player;
    assert.equal(p.genre, "Lo-fi");
    assert.equal(p.chip, "instrumental");
    assert.equal(p.strip, null);
    assert.equal(p.name, "Dusty Notebook");
    assert.equal(p.nameTone, "normal");
    assert.equal(p.meta, "Tune 4 · 88 BPM · A major");
    assert.equal(p.left, "1:24");
    assert.equal(p.leftTone, "soft");
    assert.equal(p.right, "2:52");
    assert.equal(p.main, "pause");
    assert.equal(p.mainLit, true);
    assert.equal(p.nextLit, true);
    assert.equal(p.wave.forming, false);
    assert.equal(p.wave.cols.length, 78);
    assert.equal(p.wave.played, Math.floor(84 / 172.4 * 78));
    assert.deepEqual(p.well, {
        name: "ACE-Step 1.5 Turbo", sub: "4B Q8 · Radeon 780M", status: "2 tunes ready", statusTone: "green",
        line: "idle, holding no memory", ram: "19.3 GiB of RAM free"
    });
    assert.deepEqual(hintsOf("05-playing-idle"), [["Space", "pause"], ["N", "next"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    const st = load("05-playing-idle", NOW);
    const u = ui(st, NOW);
    assert.deepEqual(T.key(u, st, "Space", false).effect.cmd, { cmd: "toggle" });
    assert.deepEqual(T.key(u, st, "N", false).effect.cmd, { cmd: "next" });
    assert.deepEqual(T.key(u, st, "U", false).effect.cmd, { cmd: "unload" });
    assert.equal(T.key(u, st, "R", false).effect.kind, "none");
    assert.equal(T.key(u, st, "C", false).effect.kind, "none");
    assert.equal(T.key(u, st, "Enter", false).effect.kind, "none");
    assert.equal(T.key(u, st, "Left", false).effect.kind, "none");
    // A held key acts once.
    for (const k of ["Space", "N", "U", "G", "Esc"])
        assert.equal(T.key(u, st, k, true).effect.kind, "none", k);
    assert.equal(T.key(u, st, "G", true).ui.mode, "player");
    assert.equal(T.key(u, st, "Esc", false).effect.kind, "close");
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Lo-fi" });
    assert.equal(T.needsTick(st, u), true);
});

t("the position between snapshots", () => {
    const st = load("05-playing-idle", NOW);
    assert.equal(T.position(st.snap, NOW), 84);
    assert.equal(T.position(st.snap, NOW + 10.5), 94.5);
    assert.equal(T.position(st.snap, NOW - 5), 84);
    assert.equal(T.position(st.snap, NOW + 1000), 172.4);
    assert.equal(T.view(st, ui(st, NOW + 10.5)).player.left, "1:34");
    assert.equal(T.view(st, ui(st, NOW + 1000)).player.left, "2:52");
    assert.equal(T.view(st, ui(st, NOW + 1000)).player.wave.played, 78);
    const paused = load("11-paused", NOW);
    assert.equal(T.position(paused.snap, NOW + 60), 145);
    assert.equal(T.view(paused, ui(paused, NOW + 60)).player.left, "2:25");
});

t("a click on the waveform seeks", () => {
    const st = load("05-playing-idle", NOW);
    assert.deepEqual(T.seek(st, 0.5), { cmd: "seek", t: 86.2 });
    assert.deepEqual(T.seek(st, 0), { cmd: "seek", t: 0 });
    assert.deepEqual(T.seek(st, 1.4), { cmd: "seek", t: 172.4 });
    assert.deepEqual(T.seek(st, -1), { cmd: "seek", t: 0 });
    assert.equal(T.seek(load("06-composing-first", NOW), 0.5), null);
    assert.equal(T.seek(T.initial(), 0.5), null);
    assert.equal(T.seek(T.linkLost(st, "exited", 3, "", NOW + 2), 0.5), null);
});

t("composing the first tune, nothing to play", () => {
    const p = viewAt("06-composing-first").player;
    assert.equal(p.genre, "Synthwave");
    assert.equal(p.strip, null);
    assert.equal(p.name, "Composing the first tune…");
    assert.equal(p.nameTone, "soft");
    assert.equal(p.meta, "writing the song · 12 s");
    assert.equal(p.wave.forming, true);
    assert.ok(p.wave.cols.every(c => c === 1));
    assert.equal(p.left, "–:––");
    assert.equal(p.right, "–:––");
    assert.equal(p.mainLit, false);
    assert.equal(p.nextLit, false);
    assert.deepEqual(p.well, {
        name: "ACE-Step 1.5 Turbo", sub: "4B Q8 · Radeon 780M", status: "composing", statusTone: "cyan",
        line: "writing the song", ram: "using 5.8 GiB of RAM"
    });
    assert.equal(viewAt("06-composing-first", NOW + 60).player.meta, "writing the song · 1 min 12 s");
    assert.deepEqual(hintsOf("06-composing-first"), [["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    const st = load("06-composing-first", NOW);
    assert.equal(T.key(ui(st, NOW), st, "Space", false).effect.kind, "none");
    assert.equal(T.key(ui(st, NOW), st, "N", false).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "cyan", text: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
    // With kept tunes of the genre it is the next tune, not the first.
    const lofi = load("06-composing-first", NOW);
    lofi.snap.genre = "lofi";
    assert.equal(T.view(lofi, ui(lofi, NOW)).player.name, "Composing the next tune…");
});

t("held for a game", () => {
    const p = viewAt("07-held-game").player;
    assert.deepEqual(p.strip, { tone: "orange", text: "A game is running. Composing is paused so the game keeps the processor and the memory; tunes already made keep playing." });
    assert.equal(p.name, "Paper Lantern");
    assert.equal(p.meta, "Tune 5 · 82 BPM · D minor");
    assert.equal(p.left, "0:22");
    assert.equal(p.right, "2:55");
    assert.equal(p.well.status, "held for a game");
    assert.equal(p.well.statusTone, "orange");
    assert.equal(p.well.line, "server stopped · 1 tune ready");
    assert.equal(p.well.ram, "9.4 GiB of RAM free");
    assert.deepEqual(hintsOf("07-held-game"), [["Space", "pause"], ["N", "next"], ["G", "genres"], ["Esc", "close"]]);
    const st = load("07-held-game", NOW);
    assert.equal(T.key(ui(st, NOW), st, "U", false).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "orange", text: "Lo-fi" });
});

t("failed with nothing to play", () => {
    const p = viewAt("08-failed-nothing").player;
    assert.deepEqual(p.strip, { tone: "red", text: "Composing failed: ggml_vulkan: device lost. Trying again in 30 s." });
    assert.equal(viewAt("08-failed-nothing", NOW + 31).player.strip.text, "Composing failed: ggml_vulkan: device lost. Trying again now.");
    assert.equal(p.name, "Nothing to play");
    assert.equal(p.meta, "2 failures in a row");
    assert.equal(p.wave, null);
    assert.equal(p.right, null);
    assert.equal(p.mainLit, false);
    assert.equal(p.well.status, "failed");
    assert.equal(p.well.statusTone, "red");
    assert.equal(p.well.line, "server stopped");
    assert.equal(p.well.ram, "19.3 GiB of RAM free");
    assert.deepEqual(hintsOf("08-failed-nothing"), [["R", "try now"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    const st = load("08-failed-nothing", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "R", false).effect.cmd, { cmd: "retry" });
    assert.equal(T.key(ui(st, NOW), st, "R", true).effect.kind, "none");
    assert.deepEqual(T.barView(st), { tone: "red", text: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), true);
    // No retry time: R is the way.
    const later = load("08-failed-nothing", NOW);
    later.snap.model = Object.assign({}, later.snap.model, { retryAt: null, detail: null });
    assert.equal(T.view(later, ui(later, NOW)).player.strip.text, "Composing failed. R tries again.");
    assert.equal(T.needsTick(later, ui(later, NOW)), false);
});

t("failed while playing: only the well says so", () => {
    const p = viewAt("17-failed-playing").player;
    assert.equal(p.strip, null);
    assert.equal(p.name, "Dusty Notebook");
    assert.equal(p.well.status, "failed");
    assert.equal(p.well.line, "server stopped · 1 failure in a row, trying again in 3 s");
    assert.equal(p.nextLit, false);
    assert.deepEqual(hintsOf("17-failed-playing"), [["Space", "pause"], ["R", "try now"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    assert.deepEqual(T.barView(load("17-failed-playing", NOW)), { tone: "red", text: "Lo-fi" });
});

t("playing while the next is rendered", () => {
    const p = viewAt("09-playing-rendering").player;
    assert.equal(p.name, "Slow Tram");
    assert.equal(p.meta, "Tune 6 · 90 BPM · F major");
    assert.equal(p.left, "2:02");
    assert.equal(p.right, "2:52");
    assert.deepEqual([p.well.status, p.well.statusTone, p.well.line, p.well.ram], ["composing", "cyan", "rendering the audio · 1 tune ready", "using 3.9 GiB of RAM"]);
    assert.deepEqual(hintsOf("09-playing-rendering"), [["Space", "pause"], ["N", "next"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    assert.deepEqual(T.barView(load("09-playing-rendering", NOW)), { tone: "cyan", text: "Lo-fi" });
});

t("writing again after a silence", () => {
    const p = viewAt("10-writing-again").player;
    assert.equal(p.left, "2:25");
    assert.equal(p.well.line, "writing again: the last plan had 39 s of silence · 1 tune ready");
    assert.equal(p.well.ram, "using 5.8 GiB of RAM");
    // Nothing to play while writing again: the meta line says so too.
    const st = load("10-writing-again", NOW);
    st.snap = Object.assign({}, st.snap, { tune: null, player: "none" });
    assert.equal(T.view(st, ui(st, NOW)).player.meta, "writing again · 30 s");
});

t("paused", () => {
    const p = viewAt("11-paused").player;
    assert.equal(p.name, "Slow Tram");
    assert.equal(p.nameTone, "soft");
    assert.equal(p.meta, "Tune 6 · 90 BPM · F major · paused");
    assert.equal(p.main, "play");
    assert.equal(p.mainLit, true);
    assert.deepEqual([p.well.status, p.well.statusTone, p.well.line], ["2 tunes ready", "green", "idle, holding no memory"]);
    assert.deepEqual(hintsOf("11-paused"), [["Space", "play"], ["N", "next"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    const st = load("11-paused", NOW);
    assert.deepEqual(T.barView(st), { tone: "normal", text: "" });
    assert.equal(T.needsTick(st, ui(st, NOW)), false);
});

t("unloaded, kept tunes playing", () => {
    const p = viewAt("12-unloaded-kept").player;
    assert.equal(p.name, "Paper Lantern");
    assert.equal(p.meta, "Kept tune · 82 BPM · D minor");
    assert.equal(p.left, "0:58");
    assert.equal(p.right, "2:55");
    assert.equal(p.nextLit, true);
    assert.deepEqual([p.well.status, p.well.statusTone, p.well.line, p.well.ram], ["unloaded", "dim", "playing the 31 kept tunes, shuffled", "19.3 GiB of RAM free"]);
    assert.deepEqual(hintsOf("12-unloaded-kept"), [["Space", "pause"], ["N", "next"], ["G", "genres"], ["U", "load"], ["Esc", "close"]]);
    const st = load("12-unloaded-kept", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "U", false).effect.cmd, { cmd: "load" });
    assert.deepEqual(T.barView(st), { tone: "normal", text: "Lo-fi" });
});

t("a kept tune not read yet, the only one: no time, no seek, no next", () => {
    const [ev] = events("12-unloaded-kept", NOW);
    ev.tune = Object.assign(ev.tune, { name: "20260105-100000-70bpm-G-major", bpm: 70, key: "G major", length: null, wave: [] });
    ev.can_next = false;
    const st = T.apply(T.initial(), ev, NOW);
    const p = T.view(st, ui(st, NOW + 5)).player;
    assert.equal(p.name, "20260105-100000-70bpm-G-major");
    assert.deepEqual([p.left, p.right], ["1:03", "–:––"]);
    assert.deepEqual([p.wave.played, p.wave.forming], [0, false]);
    assert.ok(p.wave.cols.length === T.COLS && p.wave.cols.every(c => c === 1));
    assert.equal(p.nextLit, false);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["G", "genres"], ["U", "load"], ["Esc", "close"]]);
    assert.equal(T.key(ui(st, NOW), st, "N", false).effect.kind, "none");
    assert.equal(T.seek(st, 0.5), null);
});

t("unloaded with nothing to play", () => {
    const p = viewAt("15-unloaded-nothing").player;
    assert.equal(p.name, "Nothing to play. U loads the model.");
    assert.equal(p.meta, "");
    assert.equal(p.wave, null);
    assert.equal(p.well.line, "server stopped");
    assert.deepEqual(hintsOf("15-unloaded-nothing"), [["G", "genres"], ["U", "load"], ["Esc", "close"]]);
    assert.deepEqual(T.barView(load("15-unloaded-nothing", NOW)), { tone: "dim", text: "" });
});

t("held for memory", () => {
    const p = viewAt("13-held-memory").player;
    assert.deepEqual(p.strip, { tone: "orange", text: "Not enough free memory to compose: a tune needs 6 GiB and 3.1 GiB is free. Composing resumes by itself when there is room." });
    assert.deepEqual([p.well.status, p.well.line, p.well.ram], ["held for memory", "server stopped · 1 tune ready", "3.1 GiB of RAM free"]);
    assert.deepEqual(hintsOf("13-held-memory"), [["Space", "pause"], ["N", "next"], ["G", "genres"], ["Esc", "close"]]);
    assert.deepEqual(T.barView(load("13-held-memory", NOW)), { tone: "orange", text: "Lo-fi" });
});

t("no device", () => {
    const v = viewAt("14-no-device");
    assert.equal(v.kind, "device");
    assert.equal(v.setup.title, "No graphics device to compose on");
    assert.equal(v.setup.detail, "The model server did not find the Radeon 780M among the Vulkan devices. Kept tunes still play.");
    assert.deepEqual(v.setup.rows, [["found", "1 device, not this one"]]);
    assert.deepEqual(hintsOf("14-no-device"), [["R", "try now"], ["G", "genres"], ["Esc", "close"]]);
    const st = load("14-no-device", NOW);
    assert.deepEqual(T.key(ui(st, NOW), st, "R", false).effect.cmd, { cmd: "retry" });
    const g = T.key(ui(st, NOW), st, "G", false).ui;
    assert.equal(T.view(st, g).kind, "chooser");
    assert.deepEqual(T.hints(st, g), [["←↑↓→", "move"], ["Enter", "play"], ["Esc", "back"]]);
    assert.equal(T.view(st, T.key(g, st, "Esc", false).ui).kind, "device");
    assert.deepEqual(T.barView(st), { tone: "red", text: "" });
});

t("stopped with tunes to play: Space and the playing genre's pick start one", () => {
    const st = load("21-stopped", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.equal(p.name, "Stopped. Space plays.");
    assert.equal(p.mainLit, true);
    assert.equal(p.main, "play");
    assert.deepEqual(p.strip, { tone: "orange", text: "mpv could not play the tune: audio output initialization failed" });
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "play"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    assert.deepEqual(T.key(ui(st, NOW), st, "Space", false).effect, { kind: "send", cmd: { cmd: "toggle" } });
    const r = T.pick(ui(st, NOW, { mode: "chooser" }), st, 0);
    assert.deepEqual([r.ui.mode, r.effect], ["player", { kind: "send", cmd: { cmd: "toggle" } }]);
    assert.deepEqual(T.pick(ui(st, NOW, { mode: "chooser" }), st, 1).effect, { kind: "send", cmd: { cmd: "genre", id: "ambient" } });
    // Kept tunes alone are enough; nothing ready and none kept is not.
    const kept = { link: "up", snap: Object.assign({}, st.snap, { ready: 0 }) };
    assert.equal(T.hints(kept, ui(kept, NOW))[0][0], "Space");
    const none = { link: "up", snap: Object.assign({}, st.snap, { ready: 0, genres: [{ id: "lofi", name: "Lo-fi", kept: 0 }] }) };
    assert.notEqual(T.hints(none, ui(none, NOW))[0][0], "Space");
    assert.equal(T.key(ui(none, NOW), none, "Space", false).effect.kind, "none");
});

t("a broken genres file", () => {
    const p = viewAt("16-genres-error").player;
    assert.deepEqual(p.strip, { tone: "orange", text: "genres file: line 4: expected a comma" });
    const st = load("16-genres-error", NOW);
    const c = T.view(st, T.key(ui(st, NOW), st, "G", false).ui);
    assert.deepEqual(c.chooser.strip, { tone: "orange", text: "genres file: line 4: expected a comma" });
});

t("outside text passes through unchanged, for the QML to draw as plain text", () => {
    const st = load("19-outside-text", NOW);
    const p = T.view(st, ui(st, NOW)).player;
    assert.equal(p.genre, "<b>Bold</b> & co");
    assert.equal(p.name, "<i>Name</i> & <font color=red>tag</font>");
    assert.equal(p.meta, "Tune 4 · 88 BPM · B♭ minor");
    assert.equal(p.well.line, "server stopped · 1 failure in a row, trying again in 30 s · 2 tunes ready");
    assert.deepEqual(T.barView(st), { tone: "red", text: "<b>Bold</b> & co" });
    // A detail that ends in a full stop gets no second one.
    st.snap = Object.assign({}, st.snap, { player: "none", tune: null });
    assert.equal(T.view(st, ui(st, NOW)).player.strip.text, "Composing failed: <u>server</u> said: oops. Trying again in 30 s.");
});

t("a session: chooser, starting, then the first tune", () => {
    const lines = events("20-session", NOW);
    let st = T.initial();
    const kinds = [];
    for (const ev of lines) {
        st = T.apply(st, ev, NOW);
        kinds.push(T.view(st, ui(st, NOW)).kind);
    }
    assert.deepEqual(kinds, ["chooser", "chooser", "player", "player"]);
    const starting = lines.slice(0, 3).reduce((s, ev) => T.apply(s, ev, NOW), T.initial());
    const p0 = T.view(starting, ui(starting, NOW)).player;
    assert.equal(p0.name, "Composing the first tune…");
    assert.equal(p0.meta, "starting the model server · 2 s");
    assert.deepEqual([p0.well.status, p0.well.line], ["starting", "starting the model server"]);
    assert.deepEqual(T.barView(starting), { tone: "cyan", text: "" });
    const p = T.view(st, ui(st, NOW)).player;
    assert.equal(p.genre, "Jazz");
    assert.equal(p.meta, "Tune 1 · 132 BPM · E flat major");
    assert.equal(p.nextLit, false);
    assert.deepEqual(T.hints(st, ui(st, NOW)), [["Space", "pause"], ["G", "genres"], ["U", "unload"], ["Esc", "close"]]);
    assert.deepEqual(T.barView(st), { tone: "cyan", text: "Jazz" });
});

t("unknown values fall back to the empty ones", () => {
    const st = T.apply(T.initial(), { event: "state", v: 1, setup: "weird", player: 3, model: { state: "dancing" }, genres: [{ name: "no id" }, 5, { id: "a" }] }, NOW);
    assert.equal(st.snap.setup, "missing");
    assert.equal(st.snap.player, "none");
    assert.equal(st.snap.model.state, "unloaded");
    assert.deepEqual(st.snap.genres, [{ id: "a", name: "a", kept: 0 }]);
    const v = T.view(st, ui(st, NOW));
    assert.equal(v.kind, "setup");
    assert.equal(v.setup.detail, "The music model composes on this computer. Nothing is sent anywhere after the download.");
    assert.deepEqual(v.setup.rows, []);
    // Every key name is known to the table builder without throwing, in
    // every fixture.
    for (const f of fs.readdirSync(path.join(__dirname, "fixtures"))) {
        const s = load(f.replace(/\.jsonl$/, ""), NOW);
        for (const mode of ["player", "chooser"])
            for (const k of T.KEY_NAMES)
                T.key(ui(s, NOW, { mode }), s, k, false);
    }
});

console.log(`ok: ${n} tunes-panel tests`);
