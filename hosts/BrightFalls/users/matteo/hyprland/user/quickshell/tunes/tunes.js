// The tunes panel's decisions: the state held from desk-tunes' snapshots and
// the attach link, which card shows, every text and tone the cards, the model
// well, the waveform and the bar item show, what each key and click does,
// the footer, and the position between snapshots. The QML draws what these
// functions return and performs the effects; it decides nothing.
// Plain JavaScript so node can run it too.
//
// Times are Unix seconds (Date.now() / 1000), as the service's pos_at,
// since and retry_at are. Tones are names: "normal", "soft", "dim", "cyan",
// "green", "orange", "red", "purple"; QML maps them to Theme.
//
// The snapshot's can_next is true when "next" would play another tune; N is
// offered only then.
//
// The QML's part:
//   st = initial(); each stdout line of `desk-tunes attach`: st = apply(st,
//   JSON.parse(line), now), and the restart back-off resets when
//   healthy(event); the attach process running again: st = linkLost(st,
//   "back"); exiting: st = linkLost(st, "exited", code, its last stderr
//   line, the time of the next start); never starting: linkLost(st,
//   "missing", null, "", the time of the next start).
//   On every open: ui = initialUi(st, now) and send {"cmd":"refresh"}; while
//   open, ui.now kept current at least once a second whenever needsTick(st,
//   ui). A key: r = key(ui, st, name, isAutoRepeat); ui = r.ui; run r.effect.
//   A click: on a button, the key it stands for; on a genre cell, pick(ui,
//   st, index); on the waveform, seek(st, fraction across, now).
//
// view(st, ui) -> { kind, setup, chooser, player }, one of the last three
//   set and the others null:
//   kind: "connecting" | "missing" | "down" | "lost" | "old" (the link) |
//     "setup" | "failed" (the download stopped) | "download" | "device" |
//     "chooser" | "player".
//   setup: { title, detail, rows: [[label, value]], bar: null | 0..1 } for
//     every kind before "chooser".
//   chooser: { title, cells: [{ name, sub, sel }], empty ("" | the line in
//     place of the cells), strip }.
//   player: { genre, chip, strip, name, nameTone, meta, wave: null | {
//     cols: COLS dot counts (odd, 1..ROWS), played (columns lit),
//     forming (cyan, nothing rendered yet) }, left, leftTone, right (null
//     when there is no time row), main ("play" | "pause"), mainLit, nextLit,
//     well }.
//   strip: null | { tone, text }.
//   well: { name, sub, status, statusTone, line, ram }.
// hints(st, ui) -> [[key, label]], the keys key() handles now.
// barView(st) -> { tone (the glyph), text ("" or the genre's name) }.
// key effect: { kind: "none" | "close" | "send" | "reattach", cmd (null
//   unless send) }.

const COLS = 78;
const ROWS = 13;
// The chooser's grid.
const GRID = 3;
const KEY_NAMES = ["Space", "N", "G", "U", "R", "C", "Enter", "Esc", "Left", "Right", "Up", "Down"];
const MOVING_KEYS = ["Left", "Right", "Up", "Down"];

const SETUP = ["missing", "downloading", "ready", "failed"];
const PLAYER = ["none", "playing", "paused"];
const MODEL = ["unloaded", "starting", "idle", "writing", "rendering", "held_game", "held_memory", "failed", "no_device"];
const COMPOSING = ["starting", "writing", "rendering"];
const HELD = ["held_game", "held_memory"];

const DASH = "–";
const GIB = 1073741824;

function copy(o, changes) {
    return Object.assign({}, o, changes);
}

function num(v) {
    return typeof v === "number" && isFinite(v) ? v : null;
}

function str(v) {
    return typeof v === "string" ? v : null;
}

function obj(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v) ? v : null;
}

function oneOf(v, list, fallback) {
    return list.indexOf(v) >= 0 ? v : fallback;
}

function count(v) {
    const n = num(v);
    return n === null ? 0 : Math.max(0, Math.floor(n));
}

function plural(n, one, many) {
    return `${n} ${n === 1 ? one : many}`;
}

// "1:24", "12:05"; "–:––" for none.
function clock(seconds) {
    const s = num(seconds);
    if (s === null || s < 0)
        return `${DASH}:${DASH}${DASH}`;
    const whole = Math.floor(s);
    const m = Math.floor(whole / 60);
    const r = whole % 60;
    return `${m}:${r < 10 ? "0" : ""}${r}`;
}

// Bytes in GiB: "19.3 GiB", "6 GiB" (a whole number loses its ".0"), "226
// GiB" from 100 up; `decimals` 1 unless given.
function gib(bytes, decimals) {
    const b = num(bytes);
    if (b === null)
        return "";
    const g = b / GIB;
    const d = g >= 100 ? 0 : decimals === undefined ? 1 : decimals;
    return `${Number(g.toFixed(d))} GiB`;
}

// Bytes a second: "28 MB/s", "640 kB/s".
function rate(bps) {
    const b = num(bps);
    if (b === null)
        return "";
    if (b >= 1e6)
        return `${Math.round(b / 1e6)} MB/s`;
    return `${Math.round(b / 1e3)} kB/s`;
}

// "12 s", "1 min 5 s", "3 min".
function elapsed(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    if (s < 60)
        return `${s} s`;
    const m = Math.floor(s / 60);
    return s % 60 ? `${m} min ${s % 60} s` : `${m} min`;
}

// The snapshot's fields, each of its type or its empty value.
function snapshot(ev) {
    const d = obj(ev.download);
    const need = obj(ev.need) || {};
    const m = obj(ev.model) || {};
    const t = obj(ev.tune);
    return {
        setup: oneOf(ev.setup, SETUP, "missing"),
        download: d ? {
            file: count(d.file),
            files: count(d.files),
            name: str(d.name) || "",
            done: num(d.done),
            total: num(d.total),
            rate: num(d.rate),
            error: str(d.error)
        } : null,
        need: {
            download: num(need.download_bytes),
            free: num(need.disk_free_bytes),
            ram: num(need.ram_bytes)
        },
        genres: (Array.isArray(ev.genres) ? ev.genres : []).filter(g => obj(g) && typeof g.id === "string").map(g => ({
            id: g.id,
            name: str(g.name) || g.id,
            kept: count(g.kept)
        })),
        genre: str(ev.genre),
        player: oneOf(ev.player, PLAYER, "none"),
        tune: t ? {
            n: num(t.n),
            name: str(t.name) || "",
            bpm: num(t.bpm),
            key: str(t.key) || "",
            length: num(t.length),
            kept: t.kept === true,
            wave: (Array.isArray(t.wave) ? t.wave : []).map(v => Math.max(0, Math.min(1, num(v) || 0)))
        } : null,
        pos: num(ev.pos) || 0,
        posAt: num(ev.pos_at),
        ready: count(ev.ready),
        keptPlaying: ev.kept_playing === true,
        canNext: ev.can_next === true,
        model: {
            name: str(m.name) || "",
            variant: str(m.variant) || "",
            device: str(m.device) || "",
            state: oneOf(m.state, MODEL, "unloaded"),
            since: num(m.since),
            silence: num(m.silence_s),
            detail: str(m.detail),
            failures: count(m.failures),
            retryAt: num(m.retry_at),
            ramUsed: num(m.ram_used_bytes),
            ramFree: num(m.ram_free_bytes)
        },
        error: str(ev.error)
    };
}

// Before the attach link has said anything. link: "connecting" | "up" |
// "missing" (desk-tunes not on PATH) | "down" (no socket: exit code 3) |
// "lost" (any other exit) | "old" (a protocol version other than 1); code
// and said (the last stderr line) of the last exit; retryAt the next start;
// v the version an "old" snapshot gave; snap the last snapshot.
function initial() {
    return { link: "connecting", code: null, said: "", retryAt: null, v: null, snap: null };
}

// The state after one line from the service, already parsed. Lines other
// than a snapshot change nothing.
function apply(st, ev, now) {
    if (!obj(ev) || ev.event !== "state")
        return st;
    if (ev.v !== 1)
        return copy(st, { link: "old", v: ev.v });
    return copy(st, { link: "up", code: null, said: "", retryAt: null, snap: snapshot(ev) });
}

// Whether a line shows the service answering, so the restart back-off
// resets: a snapshot it can read, or its reply to a line it could not.
function healthy(ev) {
    return obj(ev) !== null && ((ev.event === "state" && ev.v === 1) || ev.event === "error");
}

// The shell's report on the attach process: "back" (running again),
// "exited" with its exit code and last stderr line, or "missing" (it could
// not be run); retryAt is when it starts again.
function linkLost(st, why, code, said, retryAt) {
    if (why === "back")
        return copy(st, { link: "connecting", retryAt: null });
    if (why === "missing")
        return copy(st, { link: "missing", code: null, said: "", retryAt: num(retryAt) });
    return copy(st, { link: code === 3 ? "down" : "lost", code: num(code), said: str(said) || "", retryAt: num(retryAt) });
}

function genreOf(s, id) {
    return s.genres.find(g => g.id === id) || null;
}

function genreName(s) {
    const g = genreOf(s, s.genre);
    return g ? g.name : s.genre || "";
}

// The playing tune's position now: the snapshot's, moved on by the time
// since it was true while playing, never past the tune's end.
function position(s, now) {
    if (!s.tune)
        return 0;
    let p = s.pos;
    if (s.player === "playing" && s.posAt !== null)
        p += Math.max(0, now - s.posAt);
    return s.tune.length !== null ? Math.min(p, s.tune.length) : p;
}

// The dots in each waveform column: the bar's level times ROWS, rounded,
// odd so the column centres on the middle row, at least one. A wave with a
// length other than COLS is resampled to COLS.
function waveColumns(wave) {
    const out = [];
    for (let i = 0; i < COLS; i++) {
        const a = wave.length ? wave[Math.min(wave.length - 1, Math.floor(i * wave.length / COLS))] : 0;
        let n = Math.max(1, Math.round(a * ROWS));
        if (n % 2 === 0)
            n -= 1;
        out.push(n);
    }
    return out;
}

function retryWords(at, now) {
    if (at === null)
        return "";
    const s = Math.ceil(at - now);
    return s > 0 ? `trying again in ${s} s` : "trying again now";
}

function sentence(words) {
    return words ? words[0].toUpperCase() + words.slice(1) + "." : "";
}

// Outside text as a sentence: a full stop added unless it ends in one.
function stop(text) {
    return /[.!?…]$/.test(text) ? text : text + ".";
}

function linkView(st, now) {
    const again = sentence(retryWords(st.retryAt, now));
    const card = (title, detail, rows) => ({ kind: st.link, setup: { title, detail, rows: rows || [], bar: null }, chooser: null, player: null });
    if (st.link === "connecting")
        return card("Connecting to the tunes service…", "");
    if (st.link === "old")
        return card("The tunes service is newer than this panel", `It speaks version ${st.v} of the protocol; this panel reads version 1.`);
    if (st.link === "missing")
        return card("The tunes service is not installed", `desk-tunes is not on PATH. ${again}`.trim());
    const rows = [["unit", "desk-tunes.service"]];
    const last = st.said || (st.link === "lost" && st.code !== null ? `exited, status ${st.code}` : "");
    if (last)
        rows.push(["last line", last]);
    return card(st.link === "down" ? "The tunes service is not running" : "The link to the tunes service closed", again, rows);
}

function setupView(s) {
    const d = s.download;
    if (s.setup === "downloading") {
        const what = d && d.files ? `File ${d.file} of ${d.files}${d.name ? `: the ${d.name}` : ""}.` : "";
        const rows = [];
        if (d && d.done !== null && d.total !== null)
            rows.push(["downloaded", `${gib(d.done, 1).replace(" GiB", "")} of ${gib(d.total, 2)}`]);
        if (d && d.rate !== null)
            rows.push(["speed", rate(d.rate)]);
        const bar = d && d.done !== null && d.total ? Math.max(0, Math.min(1, d.done / d.total)) : 0;
        return { kind: "download", setup: { title: "Downloading the music model", detail: what, rows, bar }, chooser: null, player: null };
    }
    if (s.setup === "failed") {
        const rows = d && d.done !== null && d.total !== null ? [["downloaded", `${gib(d.done, 1).replace(" GiB", "")} of ${gib(d.total, 2)}`]] : [];
        const why = (d && d.error) || s.error || "The download did not finish.";
        return { kind: "failed", setup: { title: "The download stopped", detail: `${stop(why)} Finished files are kept.`, rows, bar: null }, chooser: null, player: null };
    }
    const rows = [];
    if (s.need.download !== null)
        rows.push(["download", gib(s.need.download, 2)]);
    if (s.need.free !== null)
        rows.push(["free on disk", gib(s.need.free)]);
    if (s.need.ram !== null)
        rows.push(["memory while composing", `about ${gib(s.need.ram)} of RAM`]);
    return {
        kind: "setup",
        setup: {
            title: "Tunes needs a music model",
            detail: `${s.model.name || "The music model"} composes on this computer. Nothing is sent anywhere after the download.`,
            rows,
            bar: null
        },
        chooser: null,
        player: null
    };
}

function deviceView(s) {
    const device = s.model.device || "configured graphics device";
    return {
        kind: "device",
        setup: {
            title: "No graphics device to compose on",
            detail: `The model server did not find the ${device} among the Vulkan devices. Kept tunes still play.`,
            rows: s.model.detail ? [["found", s.model.detail]] : [],
            bar: null
        },
        chooser: null,
        player: null
    };
}

function errorStrip(s) {
    return s.error ? { tone: "orange", text: s.error } : null;
}

function selected(ui, s) {
    return Math.max(0, Math.min(s.genres.length - 1, ui.sel));
}

function chooserView(s, ui) {
    const sel = selected(ui, s);
    return {
        kind: "chooser",
        setup: null,
        chooser: {
            title: "What do you want to hear?",
            cells: s.genres.map((g, i) => ({ name: g.name, sub: g.kept ? `${g.kept} kept` : "none yet", sel: i === sel })),
            empty: s.genres.length ? "" : "The genres file lists no genres.",
            strip: errorStrip(s)
        },
        player: null
    };
}

function wellView(s, stripShown, now) {
    const m = s.model;
    const st = m.state;
    const ready = s.ready ? plural(s.ready, "tune ready", "tunes ready") : "";
    let status;
    let tone;
    if (COMPOSING.indexOf(st) >= 0) {
        status = st === "starting" ? "starting" : "composing";
        tone = "cyan";
    } else if (st === "idle") {
        status = ready || "idle";
        tone = ready ? "green" : "soft";
    } else if (st === "held_game") {
        status = "held for a game";
        tone = "orange";
    } else if (st === "held_memory") {
        status = "held for memory";
        tone = "orange";
    } else if (st === "failed") {
        status = "failed";
        tone = "red";
    } else {
        status = "unloaded";
        tone = "dim";
    }
    let base;
    if (st === "idle")
        base = "idle, holding no memory";
    else if (st === "starting")
        base = "starting the model server";
    else if (st === "writing")
        base = m.silence !== null ? `writing again: the last plan had ${Math.round(m.silence)} s of silence` : "writing the song";
    else if (st === "rendering")
        base = "rendering the audio";
    else
        base = "server stopped";
    const parts = [base];
    if (st === "failed" && !stripShown) {
        const again = retryWords(m.retryAt, now);
        parts.push(again ? `${plural(m.failures, "failure", "failures")} in a row, ${again}` : plural(m.failures, "failure", "failures") + " in a row");
    }
    const g = genreOf(s, s.genre);
    if (s.keptPlaying) {
        const kept = `playing the ${g && g.kept ? `${g.kept} ` : ""}kept tunes, shuffled`;
        if (st === "unloaded")
            parts[0] = kept;
        else
            parts.push(kept);
    } else if (ready && st !== "idle") {
        parts.push(ready);
    }
    let ram = "";
    if (COMPOSING.indexOf(st) >= 0 && m.ramUsed !== null)
        ram = `using ${gib(m.ramUsed)} of RAM`;
    else if (m.ramFree !== null)
        ram = `${gib(m.ramFree)} of RAM free`;
    return {
        name: m.name || "Music model",
        sub: [m.variant, m.device].filter(x => x).join(" · "),
        status,
        statusTone: tone,
        line: parts.join(" · "),
        ram
    };
}

function playerView(s, ui) {
    const m = s.model;
    const t = s.tune;
    const composing = COMPOSING.indexOf(m.state) >= 0;
    let strip = null;
    if (m.state === "held_game")
        strip = { tone: "orange", text: "A game is running. Composing is paused so the game keeps the processor and the memory; tunes already made keep playing." };
    else if (m.state === "held_memory")
        strip = {
            tone: "orange",
            text: `Not enough free memory to compose: a tune needs ${gib(s.need.ram) || "more"}${m.ramFree !== null ? ` and ${gib(m.ramFree)} is free` : ""}. Composing resumes by itself when there is room.`
        };
    else if (m.state === "failed" && s.player === "none")
        strip = { tone: "red", text: `${stop(`Composing failed${m.detail ? `: ${m.detail}` : ""}`)} ${sentence(retryWords(m.retryAt, ui.now)) || "R tries again."}` };
    else
        strip = errorStrip(s);
    const g = genreOf(s, s.genre);
    const p = {
        genre: genreName(s),
        chip: "instrumental",
        strip,
        name: "",
        nameTone: "normal",
        meta: "",
        wave: null,
        left: "",
        leftTone: "dim",
        right: null,
        main: s.player === "playing" ? "pause" : "play",
        mainLit: t !== null,
        nextLit: s.canNext,
        well: wellView(s, strip !== null && m.state === "failed", ui.now)
    };
    if (t) {
        p.name = t.name;
        p.nameTone = s.player === "paused" ? "soft" : "normal";
        p.meta = [t.kept ? "Kept tune" : t.n !== null ? `Tune ${t.n}` : "", t.bpm !== null ? `${Math.round(t.bpm)} BPM` : "", t.key, s.player === "paused" ? "paused" : ""].filter(x => x).join(" · ");
        const pos = position(s, ui.now);
        const played = t.length ? Math.max(0, Math.min(COLS, Math.floor(pos / t.length * COLS))) : 0;
        p.wave = { cols: waveColumns(t.wave), played, forming: false };
        p.left = clock(pos);
        p.leftTone = "soft";
        p.right = clock(t.length);
    } else if (composing) {
        p.name = g && g.kept ? "Composing the next tune…" : "Composing the first tune…";
        p.nameTone = "soft";
        const stage = m.state === "starting" ? "starting the model server" : m.state === "rendering" ? "rendering the audio" : m.silence !== null ? "writing again" : "writing the song";
        p.meta = m.since !== null ? `${stage} · ${elapsed(ui.now - m.since)}` : stage;
        p.wave = { cols: waveColumns([]), played: 0, forming: true };
        p.left = clock(null);
        p.right = clock(null);
    } else if (m.state === "unloaded") {
        p.name = "Nothing to play. U loads the model.";
        p.nameTone = "soft";
    } else {
        p.name = "Nothing to play";
        p.nameTone = "soft";
        if (m.state === "failed")
            p.meta = plural(m.failures, "failure", "failures") + " in a row";
    }
    return { kind: "player", setup: null, chooser: null, player: p };
}

function view(st, ui) {
    const now = ui.now;
    if (st.link !== "up" || !st.snap)
        return linkView(st, now);
    const s = st.snap;
    if (s.setup !== "ready")
        return setupView(s);
    if (s.model.state === "no_device")
        return deviceView(s);
    if (ui.mode === "chooser" || s.genre === null)
        return chooserView(s, ui);
    return playerView(s, ui);
}

// The ui of a panel just opened: the player, the chooser's selection on the
// genre playing.
function initialUi(st, now) {
    const s = st.snap;
    const i = s ? s.genres.findIndex(g => g.id === s.genre) : -1;
    return { now, mode: "player", sel: Math.max(0, i) };
}

function effect(kind, cmd) {
    return { kind, cmd: cmd || null };
}

function send(cmd) {
    return u => ({ ui: u, effect: effect("send", cmd) });
}

// The key table for the state and ui as they are: [{ keys, hint, run }] in
// footer order. Only what is listed is handled and hinted.
function table(ui, st) {
    const close = { keys: ["Esc"], hint: ["Esc", "close"], run: u => ({ ui: u, effect: effect("close") }) };
    const kind = view(st, ui).kind;
    if (kind === "connecting" || kind === "old")
        return [close];
    if (kind === "missing" || kind === "down" || kind === "lost")
        return [{ keys: ["R"], hint: ["R", "try now"], run: u => ({ ui: u, effect: effect("reattach") }) }, close];
    const s = st.snap;
    const genres = { keys: ["G"], hint: ["G", "genres"], run: u => ({ ui: copy(u, { mode: "chooser", sel: Math.max(0, s.genres.findIndex(g => g.id === s.genre)) }), effect: effect("none") }) };
    const retry = { keys: ["R"], hint: ["R", "try now"], run: send({ cmd: "retry" }) };
    if (kind === "setup" || kind === "failed")
        return [{ keys: ["Enter"], hint: ["Enter", kind === "failed" ? "resume" : "download"], run: send({ cmd: "download" }) }, close];
    if (kind === "download")
        return [{ keys: ["C"], hint: ["C", "cancel"], run: send({ cmd: "cancel_download" }) }, close];
    if (kind === "device")
        return [retry, genres, close];
    if (kind === "chooser") {
        const back = s.genre !== null
            ? { keys: ["Esc"], hint: ["Esc", "back"], run: u => ({ ui: copy(u, { mode: "player" }), effect: effect("none") }) }
            : close;
        if (!s.genres.length)
            return [back];
        const last = s.genres.length - 1;
        return [
            {
                keys: MOVING_KEYS,
                hint: ["←↑↓→", "move"],
                run: (u, k) => {
                    const step = { Left: -1, Right: 1, Up: -GRID, Down: GRID }[k];
                    const i = selected(u, s);
                    const j = i + step;
                    return { ui: copy(u, { sel: j < 0 || j > last ? i : j }), effect: effect("none") };
                }
            },
            { keys: ["Enter"], hint: ["Enter", "play"], run: u => pick(u, st, selected(u, s)) },
            back
        ];
    }
    const m = s.model.state;
    const t = [];
    if (s.tune)
        t.push({ keys: ["Space"], hint: ["Space", s.player === "playing" ? "pause" : "play"], run: send({ cmd: "toggle" }) });
    if (s.canNext)
        t.push({ keys: ["N"], hint: ["N", "next"], run: send({ cmd: "next" }) });
    if (m === "failed")
        t.push(retry);
    t.push(genres);
    if (m === "unloaded")
        t.push({ keys: ["U"], hint: ["U", "load"], run: send({ cmd: "load" }) });
    else if (HELD.indexOf(m) < 0)
        t.push({ keys: ["U"], hint: ["U", "unload"], run: send({ cmd: "unload" }) });
    t.push(close);
    return t;
}

// A key pressed in the open panel: one of KEY_NAMES. A held key's
// auto-repeat acts only for the chooser's arrows. Returns { ui, effect }.
function key(ui, st, name, isAutoRepeat) {
    const entry = table(ui, st).find(e => e.keys.indexOf(name) >= 0);
    if (!entry || (isAutoRepeat && MOVING_KEYS.indexOf(name) < 0))
        return { ui, effect: effect("none") };
    return entry.run(ui, name);
}

// The chooser's genre `index` chosen (Enter or a click): back to the player,
// and the genre asked for unless it is the one already playing.
function pick(ui, st, index) {
    const s = st.snap;
    const g = s ? s.genres[index] : undefined;
    if (!g)
        return { ui, effect: effect("none") };
    const u = copy(ui, { mode: "player", sel: index });
    if (g.id === s.genre && s.player !== "none")
        return { ui: u, effect: effect("none") };
    return { ui: u, effect: effect("send", { cmd: "genre", id: g.id }) };
}

// A click on the waveform `fraction` (0..1) of the way across: the seek
// command, or null when there is no tune with a length to seek in.
function seek(st, fraction) {
    const s = st.link === "up" ? st.snap : null;
    if (!s || !s.tune || !s.tune.length)
        return null;
    const f = Math.max(0, Math.min(1, num(fraction) || 0));
    return { cmd: "seek", t: Math.round(f * s.tune.length * 10) / 10 };
}

// The footer.
function hints(st, ui) {
    return table(ui, st).map(e => e.hint);
}

// Whether the open panel shows something that changes with the clock alone:
// the position while playing, a countdown, the time spent composing.
function needsTick(st, ui) {
    if (st.link === "missing" || st.link === "down" || st.link === "lost")
        return st.retryAt !== null;
    if (st.link !== "up" || !st.snap)
        return false;
    const s = st.snap;
    if (s.setup !== "ready" || s.model.state === "no_device" || ui.mode === "chooser" || s.genre === null)
        return false;
    if (s.player === "playing")
        return true;
    if (s.model.state === "failed")
        return s.model.retryAt !== null;
    return s.tune === null && COMPOSING.indexOf(s.model.state) >= 0 && s.model.since !== null;
}

// The bar item. Dim with no link, no model or no genre, and while nothing
// plays, composes or waits; orange while held, red after a failure, cyan
// while composing or downloading; the genre's name only while playing.
function barView(st) {
    if (st.link !== "up" || !st.snap)
        return { tone: "dim", text: "" };
    const s = st.snap;
    if (s.setup === "downloading")
        return { tone: "cyan", text: "" };
    if (s.setup !== "ready" || s.genre === null)
        return { tone: "dim", text: "" };
    const m = s.model.state;
    const text = s.player === "playing" ? genreName(s) : "";
    let tone = "dim";
    if (HELD.indexOf(m) >= 0)
        tone = "orange";
    else if (m === "failed" || m === "no_device")
        tone = "red";
    else if (COMPOSING.indexOf(m) >= 0)
        tone = "cyan";
    else if (s.player !== "none")
        tone = "normal";
    return { tone, text };
}

if (typeof module !== "undefined")
    module.exports = {
        COLS, ROWS, GRID, KEY_NAMES,
        initial, apply, healthy, linkLost, view, initialUi, key, pick, seek, hints, needsTick, barView,
        position, waveColumns, clock, gib, rate, elapsed
    };
