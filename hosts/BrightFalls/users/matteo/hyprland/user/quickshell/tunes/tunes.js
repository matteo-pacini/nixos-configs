// The tunes panel's decisions: the state held from desk-tunes' snapshots and
// the attach link, which card shows, every text and tone the cards, the three
// sections of the player (now playing, up next, composer), the waveform and
// the bar item show, what each key and click does, the footer and its undo
// line, the global scrap, and the position between snapshots. The QML draws
// what these functions return and performs the effects; it decides nothing.
// Plain JavaScript so node can run it too.
//
// Times are Unix seconds (Date.now() / 1000), as the service's pos_at,
// since, retry_at, job.started and undo.until are. Tones are names:
// "normal", "soft", "dim", "cyan", "green", "orange", "red", "purple"; QML
// maps them to Theme. Every text is plain text, outside names included; the
// QML escapes what it places in styled text (the footer's hints).
//
// Playing and composing are separate. The snapshot's "composing" is the
// composer's switch, off after every genre pick; with it off the model is
// unloaded and only kept tunes play. can_next is true when "next" would play
// another tune; N is offered only then. "stopped" means the user stopped the
// player, so nothing starts by itself until Space.
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
//   st, index); on the waveform, seek(st, fraction across). The global
//   scrap (IPC, panel open or not): r = globalScrap(st, now); when not null,
//   st = r.st, send r.cmd, notify with r.summary and r.body, and when
//   r.flash, flash the bar's note for FLASH_MS.
//
// view(st, ui) -> { kind, setup, chooser, player }, one of the last three
//   set and the others null:
//   kind: "connecting" | "missing" | "down" | "lost" | "old" (the link) |
//     "setup" | "failed" (the download stopped) | "download" | "chooser" |
//     "player".
//   setup: { title, detail, rows: [[label, value]], bar: null | 0..1 } for
//     every kind before "chooser".
//   chooser: { title, chip, cells: [{ name, sub, sel, cur }], empty ("" |
//     the line in place of the cells), strip }. cur is the genre selected.
//   player: { strip, now, next, composer }.
//   now: { head (right of NOW PLAYING), name, nameTone, meta, wave: null |
//     { cols: COLS dot counts (odd, 1..ROWS), played (columns lit) }, time:
//     null | { left, leftTone, right }, main ("play" | "pause"), mainLit,
//     nextLit }.
//   next: { head (right of UP NEXT), rows: [{ kind ("tune" | "job" |
//     "placeholder"), n, nTone, name, nameTone, sub, right, rightTone, bar
//     (null | 0..1), sel }] }.
//   composer: { on, label, labelTone, lines: [{ pre, em (drawn bold), post,
//     tone, right, rightTone }] }.
//   strip: null | { tone, text }.
// hints(st, ui) -> [[key, label]], the keys key() handles now that the
//   footer names.
// undoLine(st, ui) -> "" or the footer's text in place of the hints.
// barView(st, flashing) -> { tone (the note), text ("" or the genre's name),
//   dot ("" or the composer dot's tone) }; flashing: the note's flash after
//   a global scrap is on.
// key effect: { kind: "none" | "close" | "send" | "reattach", cmd (null
//   unless send) }.

const COLS = 78;
const ROWS = 9;
// The chooser's grid.
const GRID = 3;
const KEY_NAMES = ["Space", "N", "G", "C", "X", "Z", "R", "Enter", "Esc", "Left", "Right", "Up", "Down"];
const MOVING_KEYS = ["Left", "Right", "Up", "Down"];

const SETUP = ["missing", "downloading", "ready", "failed"];
const PLAYER = ["none", "playing", "paused"];
const MODEL = ["unloaded", "starting", "idle", "writing", "rendering", "held_game", "held_memory", "failed", "no_device"];
const STAGES = ["writing", "rendering"];
const WORKING = ["starting", "writing", "rendering"];
const HELD = ["held_game", "held_memory"];

const DASH = "–";
// How long the bar's note flashes orange after a global scrap, in ms.
const FLASH_MS = 600;
// How long a global scrap sent counts as unanswered: a scrap the service
// ignores sends no snapshot to clear it.
const PENDING_S = 2;
const GIB = 1073741824;

function copy(o, changes) {
    return Object.assign({}, o, changes);
}

function num(v) {
    return typeof v === "number" && isFinite(v) ? v : null;
}

// A duration: a number above zero, else null.
function positive(v) {
    const n = num(v);
    return n !== null && n > 0 ? n : null;
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

// A tune's or a queue entry's fields; name may be a file name and the rest
// null until the service has read the file.
function tuneOf(t) {
    return {
        name: str(t.name) || "",
        file: str(t.file) || "",
        bpm: num(t.bpm),
        key: str(t.key) || "",
        length: num(t.length),
        kept: t.kept === true
    };
}

// The snapshot's fields, each of its type or its empty value.
function snapshot(ev) {
    const d = obj(ev.download);
    const need = obj(ev.need) || {};
    const m = obj(ev.model) || {};
    const t = obj(ev.tune);
    const j = obj(ev.job);
    const u = obj(ev.undo);
    const e = obj(ev.expect);
    const ahead = num(ev.ahead);
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
        stopped: ev.stopped === true,
        tune: t ? copy(tuneOf(t), {
            wave: (Array.isArray(t.wave) ? t.wave : []).map(v => Math.max(0, Math.min(1, num(v) || 0)))
        }) : null,
        pos: num(ev.pos) || 0,
        posAt: num(ev.pos_at),
        ready: count(ev.ready),
        queue: (Array.isArray(ev.queue) ? ev.queue : []).filter(q => obj(q)).map(tuneOf),
        keptTotal: count(ev.kept_total),
        keptPlaying: ev.kept_playing === true,
        canNext: ev.can_next === true,
        composing: ev.composing === true,
        // The config's 2 when a snapshot lacks it.
        ahead: ahead === null ? 2 : count(ahead),
        expect: e && positive(e.writing_s) !== null && positive(e.rendering_s) !== null ? { writing: positive(e.writing_s), rendering: positive(e.rendering_s) } : null,
        job: j ? {
            stage: oneOf(j.stage, STAGES, "writing"),
            started: num(j.started),
            expect: positive(j.expect_s),
            written: positive(j.written_s)
        } : null,
        undo: u && str(u.name) !== null ? { name: u.name, until: num(u.until), genre: str(u.genre) } : null,
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
// v the version an "old" snapshot gave; snap the last snapshot; pending
// null or { name, at }: a global scrap sent that no snapshot has answered.
function initial() {
    return { link: "connecting", code: null, said: "", retryAt: null, v: null, snap: null, pending: null };
}

// The state after one line from the service, already parsed. Lines other
// than a snapshot change nothing.
function apply(st, ev, now) {
    if (!obj(ev) || ev.event !== "state")
        return st;
    if (ev.v !== 1)
        return copy(st, { link: "old", v: ev.v });
    return copy(st, { link: "up", code: null, said: "", retryAt: null, snap: snapshot(ev), pending: null });
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

function keptOf(s) {
    const g = genreOf(s, s.genre);
    return Math.max(s.keptTotal, g ? g.kept : 0);
}

// Whether "toggle" would start a tune when none is playing.
function canPlay(s) {
    return s.player === "none" && s.genre !== null && (s.ready > 0 || s.queue.length > 0 || keptOf(s) > 0);
}

function undoActive(s, now) {
    return s.undo !== null && s.undo.until !== null && s.undo.until > now;
}

// The job drawn as a queue row: only while the switch is on.
function jobShown(s) {
    return s.composing && s.job !== null;
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
            title: "Genre",
            chip: "Enter plays what is kept",
            cells: s.genres.map((g, i) => {
                const cur = g.id === s.genre;
                const sub = cur ? { playing: "playing now", paused: "paused" }[s.player] || "selected" : g.kept ? `${g.kept} kept` : "none yet";
                return { name: g.name, sub, sel: i === sel, cur };
            }),
            empty: s.genres.length ? "" : "The genres file lists no genres.",
            strip: errorStrip(s)
        },
        player: null
    };
}

function metaOf(t) {
    return [t.bpm !== null ? `${Math.round(t.bpm)} BPM` : "", t.key].filter(x => x).join(" · ");
}

function nowView(s, now) {
    const t = s.tune;
    const name = genreName(s);
    const p = {
        head: t && t.kept ? `${name} · kept tunes` : name,
        name: "",
        nameTone: "soft",
        meta: "",
        wave: null,
        time: null,
        main: s.player === "playing" ? "pause" : "play",
        mainLit: t !== null || canPlay(s),
        nextLit: s.canNext
    };
    if (t) {
        p.name = t.name;
        p.nameTone = s.player === "paused" ? "soft" : "normal";
        p.meta = [metaOf(t), s.player === "paused" ? "paused" : ""].filter(x => x).join(" · ");
        const pos = position(s, now);
        const played = t.length ? Math.max(0, Math.min(COLS, Math.floor(pos / t.length * COLS))) : 0;
        p.wave = { cols: waveColumns(t.wave), played };
        p.time = { left: clock(pos), leftTone: "soft", right: clock(t.length) };
    } else if (canPlay(s)) {
        // Only the user's stop is worded as one: a genre just picked starts
        // clean.
        p.name = s.stopped ? "Stopped. Space plays." : "Nothing playing. Space plays.";
    } else if (s.composing) {
        p.name = "Nothing yet";
        if (s.stopped)
            p.meta = "The player is stopped: Space starts it once a tune is ready.";
        else if (WORKING.indexOf(s.model.state) >= 0 || s.model.state === "idle")
            p.meta = "The first tune starts by itself when it is ready.";
    } else if (keptOf(s) === 0) {
        p.name = `No ${name} tunes yet`;
        p.meta = "Turn the composer on to make some.";
    } else {
        p.name = "Nothing to play";
    }
    return p;
}

// Which row of UP NEXT is selected, as an index into the queue followed by
// the job, or -1. The selection follows its tune by name, or by file (a
// kept tune is named by its file until the service has read it) as the
// queue moves.
function rowIndex(ui, s) {
    const r = ui.row;
    if (!r)
        return -1;
    if (r.kind === "job")
        return jobShown(s) ? s.queue.length : -1;
    const same = q => q.name === r.name || (r.file && q.file === r.file);
    if (r.i < s.queue.length && same(s.queue[r.i]))
        return r.i;
    return s.queue.findIndex(same);
}

function rowCount(s) {
    return s.queue.length + (jobShown(s) ? 1 : 0);
}

function rowAt(s, k) {
    return k < s.queue.length ? { kind: "queue", i: k, name: s.queue[k].name, file: s.queue[k].file } : { kind: "job" };
}

// "about 1:10 left" to the nearest 10 s, at least 0:10; "any moment now"
// once the estimate has run out.
function leftWords(expect, spent) {
    const left = expect - spent;
    if (left <= 0)
        return "any moment now";
    return `about ${clock(Math.max(10, Math.round(left / 10) * 10))} left`;
}

function jobRow(s, n, sel, now) {
    const j = s.job;
    const spent = j.started !== null ? Math.max(0, now - j.started) : null;
    const parts = [];
    let bar = null;
    if (j.expect !== null && spent !== null) {
        parts.push(leftWords(j.expect, spent));
        bar = Math.min(1, spent / j.expect);
    } else if (spent !== null) {
        parts.push(`${clock(spent)} so far`);
    }
    if (j.stage === "rendering" && j.written !== null)
        parts.push(`written in ${clock(j.written)}`);
    return {
        kind: "job",
        n,
        nTone: "cyan",
        name: j.stage === "rendering" ? "Being rendered" : "Being written",
        nameTone: "soft",
        sub: parts.join(" · "),
        right: "composing",
        rightTone: "cyan",
        bar,
        sel
    };
}

function nextView(s, ui) {
    const sel = rowIndex(ui, s);
    const rows = s.queue.map((q, i) => ({
        kind: "tune",
        n: i + 1,
        nTone: "dim",
        name: q.name,
        nameTone: "normal",
        sub: metaOf(q),
        right: q.length !== null ? clock(q.length) : "",
        rightTone: "dim",
        bar: null,
        sel: i === sel
    }));
    if (jobShown(s))
        rows.push(jobRow(s, rows.length + 1, sel === s.queue.length, ui.now));
    if (s.composing) {
        const missing = s.ahead - s.ready - (s.job !== null ? 1 : 0);
        for (let i = 0; i < missing; i++)
            rows.push({
                kind: "placeholder",
                n: rows.length + 1,
                nTone: "dim",
                name: "Not started",
                nameTone: "dim",
                sub: s.job !== null ? "after the one above" : "",
                right: "",
                rightTone: "dim",
                bar: null,
                sel: false
            });
    }
    let head;
    if (s.keptPlaying && (s.queue.length === 0 || s.queue[0].kept))
        head = `from ${keptOf(s)} kept, shuffled`;
    else if (s.composing || s.queue.length)
        head = `${s.ready} ready`;
    else
        head = "nothing";
    return { head, rows };
}

function line(pre, em, post, tone, right, rightTone) {
    return { pre, em: em || "", post: post || "", tone: tone || "dim", right: right || "", rightTone: rightTone || "dim" };
}

function composerView(s, now) {
    const m = s.model;
    const name = genreName(s);
    if (!s.composing) {
        const kept = keptOf(s) > 0;
        const lines = [line(kept ? "On, it makes new " : "On, it makes ", name, ` and keeps ${s.ahead} ahead.`)];
        if (!kept && s.need.ram !== null) {
            const ram = gib(s.need.ram);
            lines.push(line(s.expect
                ? `A tune takes about ${Math.max(1, Math.round((s.expect.writing + s.expect.rendering) / 60))} min and ${ram} of RAM while it is made.`
                : `A tune takes about ${ram} of RAM while it is made.`));
        }
        return { on: false, label: "off", labelTone: "soft", lines };
    }
    const st = m.state;
    let right = "";
    let rightTone = "dim";
    if (st === "idle") {
        right = "resting, queue is full";
        rightTone = "green";
    } else if (st === "starting") {
        right = "starting the model";
        rightTone = "cyan";
    } else if ((st === "writing" || st === "rendering") && m.ramUsed !== null) {
        right = `using ${gib(m.ramUsed)} of RAM`;
    }
    const lines = [line("Makes ", name, `, keeps ${s.ahead} ahead`, "dim", right, rightTone)];
    if (st === "writing" && m.silence !== null)
        lines.push(line(`Writing again: the last plan had ${Math.round(m.silence)} s of silence.`));
    if (st === "held_game")
        lines.push(line("A game is running. Composing waits and carries on by itself when the game closes; tunes already made keep playing.", "", "", "orange"));
    else if (st === "held_memory")
        lines.push(line(`Not enough free memory: a tune needs ${gib(s.need.ram) || "more"}${m.ramFree !== null ? ` and ${gib(m.ramFree)} is free` : ""}. Composing carries on by itself when there is room.`, "", "", "orange"));
    else if (st === "failed")
        lines.push(line(`${stop(`Failed${m.detail ? `: ${m.detail}` : ""}`)} ${plural(m.failures, "failure", "failures")} in a row. ${sentence(retryWords(m.retryAt, now)) || "R tries again."}`, "", "", "red"));
    else if (st === "no_device")
        lines.push(line(`The model server did not find the ${m.device || "configured graphics device"} among the Vulkan devices${m.detail ? `: ${stop(m.detail)}` : "."} R tries again, C turns the composer off.`, "", "", "red"));
    if ((WORKING.indexOf(st) >= 0 || st === "failed") && m.name)
        lines.push(line([m.name, m.variant, m.device].filter(x => x).join(" · ")));
    let label = "on";
    let labelTone = "soft";
    if (st === "held_game" || st === "held_memory") {
        label = st === "held_game" ? "held for a game" : "held for memory";
        labelTone = "orange";
    } else if (st === "failed" || st === "no_device") {
        label = st === "failed" ? "failed" : "no device";
        labelTone = "red";
    }
    return { on: true, label, labelTone, lines };
}

function playerView(s, ui) {
    return {
        kind: "player",
        setup: null,
        chooser: null,
        player: { strip: errorStrip(s), now: nowView(s, ui.now), next: nextView(s, ui), composer: composerView(s, ui.now) }
    };
}

function view(st, ui) {
    const now = ui.now;
    if (st.link !== "up" || !st.snap)
        return linkView(st, now);
    const s = st.snap;
    if (s.setup !== "ready")
        return setupView(s);
    if (ui.mode === "chooser")
        return chooserView(s, ui);
    if (s.genre === null)
        return chooserView(s, ui);
    return playerView(s, ui);
}

// The ui of a panel just opened: the player, the chooser's cursor on the
// selected genre, no queue row selected.
function initialUi(st, now) {
    const s = st.snap;
    const i = s ? s.genres.findIndex(g => g.id === s.genre) : -1;
    return { now, mode: "player", sel: Math.max(0, i), row: null };
}

function effect(kind, cmd) {
    return { kind, cmd: cmd || null };
}

function send(cmd) {
    return u => ({ ui: u, effect: effect("send", cmd) });
}

function sendClearing(cmd) {
    return u => ({ ui: copy(u, { row: null }), effect: effect("send", cmd) });
}

// The key table for the state and ui as they are: [{ keys, hint, run }] in
// footer order. Only what is listed is handled; an entry whose hint is null
// is handled but not named in the footer.
function table(ui, st) {
    const close = { keys: ["Esc"], hint: ["Esc", "close"], run: u => ({ ui: u, effect: effect("close") }) };
    const kind = view(st, ui).kind;
    if (kind === "connecting" || kind === "old")
        return [close];
    if (kind === "missing" || kind === "down" || kind === "lost")
        return [{ keys: ["R"], hint: ["R", "try now"], run: u => ({ ui: u, effect: effect("reattach") }) }, close];
    const s = st.snap;
    const genres = { keys: ["G"], hint: ["G", "genre"], run: u => ({ ui: copy(u, { mode: "chooser", sel: Math.max(0, s.genres.findIndex(g => g.id === s.genre)) }), effect: effect("none") }) };
    const retry = { keys: ["R"], hint: ["R", "try now"], run: send({ cmd: "retry" }) };
    const composer = { keys: ["C"], hint: ["C", s.composing ? "composer off" : "composer on"], run: send({ cmd: "compose", on: !s.composing }) };
    if (kind === "setup" || kind === "failed")
        return [{ keys: ["Enter"], hint: ["Enter", kind === "failed" ? "resume" : "download"], run: send({ cmd: "download" }) }, close];
    if (kind === "download")
        return [{ keys: ["C"], hint: ["C", "cancel"], run: send({ cmd: "cancel_download" }) }, close];
    if (kind === "chooser") {
        const back = s.genre !== null
            ? { keys: ["Esc"], hint: ["Esc", "back"], run: u => ({ ui: copy(u, { mode: "player" }), effect: effect("none") }) }
            : close;
        if (!s.genres.length)
            return [back];
        const last = s.genres.length - 1;
        const at = s.genres[selected(ui, s)];
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
            { keys: ["Enter"], hint: ["Enter", at.id === s.genre ? `back to ${at.name}` : `play ${at.name}`], run: u => pick(u, st, selected(u, s)) },
            back
        ];
    }
    const sel = rowIndex(ui, s);
    const rows = rowCount(s);
    const t = [];
    const move = {
        keys: ["Up", "Down"],
        hint: sel >= 0 ? ["↑↓", "select"] : null,
        run: (u, k) => {
            const i = rowIndex(u, s);
            let j;
            if (k === "Down")
                j = Math.min(i + 1, rows - 1);
            else
                j = i - 1;
            return { ui: copy(u, { row: j >= 0 ? rowAt(s, j) : null }), effect: effect("none") };
        }
    };
    if (rows > 0)
        t.push(move);
    const space = s.tune || canPlay(s) ? { keys: ["Space"], hint: ["Space", s.player === "playing" ? "pause" : "play"], run: send({ cmd: "toggle" }) } : null;
    let scrap = null;
    if (sel >= 0 && sel < s.queue.length)
        scrap = { keys: ["X"], hint: ["X", `scrap ${s.queue[sel].name}`], run: sendClearing({ cmd: "scrap", i: sel, name: s.queue[sel].name }) };
    else if (sel >= 0)
        scrap = { keys: ["X"], hint: ["X", `scrap the tune being ${s.job.stage === "rendering" ? "rendered" : "written"}`], run: sendClearing({ cmd: "scrap", job: true }) };
    else if (s.tune)
        scrap = { keys: ["X"], hint: ["X", `scrap ${s.tune.name}`], run: send({ cmd: "scrap", name: s.tune.name }) };
    const next = s.canNext ? { keys: ["N"], hint: ["N", "next"], run: send({ cmd: "next" }) } : null;
    const undo = undoActive(s, ui.now) ? { keys: ["Z"], hint: ["Z", "undo"], run: send({ cmd: "undo" }) } : null;
    const canRetry = s.composing && (s.model.state === "failed" || s.model.state === "no_device");
    const quiet = e => e ? copy(e, { hint: null }) : null;
    if (sel >= 0) {
        if (sel < s.queue.length)
            t.push({ keys: ["Enter"], hint: ["Enter", "play it now"], run: sendClearing({ cmd: "play", i: sel, name: s.queue[sel].name }) });
        t.push(scrap, space, quiet(next), quiet(undo), quiet(canRetry ? retry : null), quiet(composer), quiet(genres), close);
    } else {
        t.push(space, next, scrap, undo, canRetry ? retry : null, composer, genres, close);
    }
    return t.filter(e => e);
}

// A key pressed in the open panel: one of KEY_NAMES. A held key's
// auto-repeat acts only for the arrows. Returns { ui, effect }.
function key(ui, st, name, isAutoRepeat) {
    const entry = table(ui, st).find(e => e.keys.indexOf(name) >= 0);
    if (!entry || (isAutoRepeat && MOVING_KEYS.indexOf(name) < 0))
        return { ui, effect: effect("none") };
    return entry.run(ui, name);
}

// The chooser's genre `index` chosen (Enter or a click): back to the player,
// and the genre asked for; the one already selected only closes the
// chooser.
function pick(ui, st, index) {
    const s = st.snap;
    const g = s ? s.genres[index] : undefined;
    if (!g)
        return { ui, effect: effect("none") };
    const u = copy(ui, { mode: "player", sel: index, row: null });
    if (g.id === s.genre)
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

// The footer's hints.
function hints(st, ui) {
    return table(ui, st).filter(e => e.hint !== null).map(e => e.hint);
}

// The footer's line in place of the hints while a scrap can be undone, in
// the player.
function undoLine(st, ui) {
    if (view(st, ui).kind !== "player")
        return "";
    const s = st.snap;
    if (!undoActive(s, ui.now))
        return "";
    return `Scrapped ${s.undo.name}. Z brings it back for ${Math.ceil(s.undo.until - ui.now)} s.`;
}

// The global scrap (Super+Shift+M, the panel open or not): an undo while
// one is offered or a scrap sent is unanswered (so a quick second press is
// an undo, never a second scrap), else a scrap of the playing tune; null
// with no link or nothing to act on. { st (with the scrap pending), cmd,
// summary, body (for the one notification), flash (the bar's note) }.
function globalScrap(st, now) {
    if (st.link !== "up" || !st.snap)
        return null;
    const s = st.snap;
    const pending = st.pending && now - st.pending.at < PENDING_S ? st.pending : null;
    if (pending || undoActive(s, now)) {
        const g = pending ? s.genre : s.undo.genre;
        let body = "It plays next.";
        if (g !== s.genre)
            body = g !== null && genreOf(s, g) ? `It is back with the kept ${genreOf(s, g).name} tunes.` : "It is back in its folder.";
        return { st: copy(st, { pending: null }), cmd: { cmd: "undo" }, summary: `Brought back ${pending ? pending.name : s.undo.name}`, body, flash: false };
    }
    if (!s.tune)
        return null;
    return {
        st: copy(st, { pending: { name: s.tune.name, at: now } }),
        cmd: { cmd: "scrap", name: s.tune.name },
        summary: `Scrapped ${s.tune.name}`,
        body: "Super+Shift+M again within 10 s brings it back.",
        flash: true
    };
}

// Whether the open panel shows something that changes with the clock alone:
// the position while playing, the job's time, the undo countdown, a retry
// countdown.
function needsTick(st, ui) {
    if (st.link === "missing" || st.link === "down" || st.link === "lost")
        return st.retryAt !== null;
    if (st.link !== "up" || !st.snap)
        return false;
    const s = st.snap;
    if (view(st, ui).kind !== "player")
        return false;
    if (s.player === "playing" || undoActive(s, ui.now))
        return true;
    if (jobShown(s) && s.job.started !== null)
        return true;
    return s.composing && s.model.state === "failed" && s.model.retryAt !== null;
}

// The bar item: the note is playback (dim while nothing plays, orange while
// it flashes, the genre's name only while playing), the dot the composer (cyan while it works or
// the model downloads, orange while held, red after a failure or with no
// device; none while off or resting).
function barView(st, flashing) {
    if (st.link !== "up" || !st.snap)
        return { tone: "dim", text: "", dot: "" };
    const s = st.snap;
    const m = s.model.state;
    let dot = "";
    if (s.setup === "downloading" || (s.composing && WORKING.indexOf(m) >= 0))
        dot = "cyan";
    else if (s.composing && HELD.indexOf(m) >= 0)
        dot = "orange";
    else if (s.composing && (m === "failed" || m === "no_device"))
        dot = "red";
    if (s.setup !== "ready" || s.genre === null)
        return { tone: "dim", text: "", dot };
    return { tone: flashing ? "orange" : s.player === "none" ? "dim" : "normal", text: s.player === "playing" ? genreName(s) : "", dot };
}

if (typeof module !== "undefined")
    module.exports = {
        COLS, ROWS, GRID, KEY_NAMES, FLASH_MS,
        initial, apply, healthy, linkLost, view, initialUi, key, pick, seek, hints, undoLine, globalScrap, needsTick, barView,
        position, waveColumns, clock, gib, rate, elapsed
    };
