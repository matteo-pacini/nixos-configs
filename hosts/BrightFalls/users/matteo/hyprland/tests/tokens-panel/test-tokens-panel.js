// The token panel's library (quickshell/tokens/tokens.js) against invented
// desk-tokens answers in fixtures/ (written by hand from the helper's
// contract) and progress events and limits files built here.
// Run under TZ=America/New_York: the fixtures' times are that zone's, with
// the daylight-saving change of 1 Nov 2026 inside the DST cases.
// Run: node test-tokens-panel.js <directory holding tokens.js>
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const T = require(path.join(path.resolve(process.argv[2]), "tokens.js"));
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

// Tue 17 Nov 2026 09:15 in New York (EST, UTC-5).
const NOW = 1794924900;
const TODAY = 1794891600;
// Mon 2 Nov 2026 12:00 EST, the day after the change from EDT.
const DST_NOW = 1793638800;

const fx = name => JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"));
const fxText = name => fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8");
const sends = r => r.effects.filter(e => e.do === "send").map(e => e.req);
// The fixture as the answer to the state's last request for `page`.
const answer = (st, file, page, changes) => T.event(st, JSON.stringify(Object.assign(fx(file), { id: st.asked[page] }, changes || {})));
const R = (today, d7, d14, d30, all) => ({ today, "7d": d7, "14d": d14, "30d": d30, all });
const progress = (read, total, ready, extra) => JSON.stringify(Object.assign({
    event: "progress", now: NOW, state: "reading", files_read: read, files_total: total,
    bytes_read: 1702000000, bytes_total: 2690000000, ready,
    skipped: { bad_lines: 0, no_id: 0, synthetic: 0 }, unreadable: 0
}, extra || {}));
const DONE = (total, extra) => progress(total, total, R(true, true, true, true, true), Object.assign({ state: "done" }, extra || {}));
// Runs keys; returns the last result.
const keys = (st, list) => {
    let r = { state: st, effects: [], handled: true };
    for (const k of list)
        r = T.key(r.state, k);
    return r;
};
const LIM = T.limits(fxText("limits-normal.json"), NOW);

// The panel open on the overview with the full answer.
function overview() {
    return answer(T.opened().state, "overview-full.json", "overview").state;
}
// The projects page, 7 days, with the 14-row answer.
function projects() {
    return answer(T.key(overview(), "P").state, "projects-7d.json", "projects").state;
}
// A projects answer with `count` rows for `period`, row i with id 100 + i.
function rowsAnswer(count, period, first) {
    const rows = [];
    for (let i = 0; i < count; i++)
        rows.push({ id: (first || 100) + i, name: `p${i}`, output: 1000 * (count - i), subagent_output: 0, models: [{ model: "claude-opus-5-5", output: 1000 * (count - i) }], sessions: 1, last_reply: NOW - 30 });
    return Object.assign(fx("projects-7d.json"), { period, projects: rows, output: rows.reduce((a, r) => a + r.output, 0) });
}
const feed = (st, obj, page) => T.event(st, JSON.stringify(Object.assign({}, obj, { id: st.asked[page] })));

// ---- environment ---------------------------------------------------------

t("the check runs in New York time, with the DST change", () => {
    assert.equal(process.env.TZ, "America/New_York");
    assert.equal(new Date(NOW * 1000).getTimezoneOffset(), 300);
    assert.equal(new Date((DST_NOW - 3 * 86400) * 1000).getTimezoneOffset(), 240);
});

// ---- formatting ----------------------------------------------------------

t("tokens: every form and the unit edges", () => {
    const want = [
        [0, "0"], [999, "999"], [1000, "1.0 k"], [3900, "3.9 k"], [9999, "10.0 k"], [59400, "59.4 k"],
        [99960, "100 k"], [463000, "463 k"], [999499, "999 k"], [999500, "1.00 M"], [999950, "1.00 M"],
        [8830000, "8.83 M"], [9999000, "10.0 M"], [18700000, "18.7 M"], [96800000, "96.8 M"],
        [99960000, "100 M"], [999999999, "1.00 B"], [9240000000, "9.24 B"], [2500000000000, "2500 B"]
    ];
    for (const [v, s] of want)
        assert.equal(T.tokens(v), s, String(v));
});

t("counts, money, percentages", () => {
    assert.equal(T.count(0), "0");
    assert.equal(T.count(999), "999");
    assert.equal(T.count(1000), "1,000");
    assert.equal(T.count(1461), "1,461");
    assert.equal(T.count(1234567), "1,234,567");
    assert.equal(T.money(3571.42), "≈ $3,571");
    assert.equal(T.money(3571.5), "≈ $3,572");
    assert.equal(T.money(0), "≈ $0");
    assert.equal(T.percent(0.472), "47%");
    assert.equal(T.percent(1), "100%");
    assert.equal(T.percent(0), "0%");
    assert.equal(T.percent(0.004), "<1%");
    assert.equal(T.percent(0.006), "1%");
    assert.equal(T.percent(null), "–");
    assert.equal(T.percent(undefined), "–");
    assert.equal(T.percent1(0.9843), "98.4%");
    assert.equal(T.percent1(0.902), "90.2%");
    assert.equal(T.percent1(1), "100.0%");
    assert.equal(T.percent1(0), "0.0%");
    assert.equal(T.percent1(0.0004), "<0.1%");
    assert.equal(T.percent1(null), "–");
});

t("bytes", () => {
    assert.equal(T.bytes(2690000000), "2.7 GB");
    assert.equal(T.bytes(186000), "186 kB");
    assert.equal(T.bytes(512), "512 B");
    assert.equal(T.bytes(99960000), "100 MB");
    assert.equal(T.bytes(999960000), "1.0 GB");
    assert.equal(T.bytes(1000), "1.0 kB");
});

t("relative times and active time", () => {
    assert.equal(T.ago(NOW, NOW + 5), "now");
    assert.equal(T.ago(NOW, NOW - 59), "now");
    assert.equal(T.ago(NOW, NOW - 60), "1 min ago");
    assert.equal(T.ago(NOW, NOW - 3599), "59 min ago");
    assert.equal(T.ago(NOW, NOW - 3600), "1 h ago");
    assert.equal(T.ago(NOW, NOW - 86399), "23 h ago");
    assert.equal(T.ago(NOW, NOW - 86400), "1 d ago");
    assert.equal(T.ago(NOW, NOW - 24 * 86400 - 10), "24 d ago");
    assert.equal(T.activeTime(0), "<1 min");
    assert.equal(T.activeTime(59), "<1 min");
    assert.equal(T.activeTime(60), "1 min");
    assert.equal(T.activeTime(600), "10 min");
    assert.equal(T.activeTime(3599), "59 min");
    assert.equal(T.activeTime(3600), "1 h 00");
    assert.equal(T.activeTime(61380), "17 h 03");
});

t("dates in the local zone, across the DST change", () => {
    assert.equal(T.started(TODAY + 33240, NOW), "09:14");
    assert.equal(T.started(TODAY, NOW), "00:00");
    // 20:00 on Monday in New York is already Tuesday in UTC.
    assert.equal(T.started(1794877200, NOW), "Mon 20:00");
    assert.equal(T.started(1794698940, NOW), "Sat 18:29");
    assert.equal(T.started(1794373200 + 36000, NOW), "Wed 10:00");
    assert.equal(T.started(1794286800 + 36000, NOW), "10 Nov");
    assert.equal(T.started(1793768400, NOW), "04 Nov");
    // Around Sun 1 Nov, a 25-hour day; 01:30 happens twice.
    assert.equal(T.started(1793485740, DST_NOW), "Sat 18:29");
    assert.equal(T.started(1793511000, DST_NOW), "Sun 01:30");
    assert.equal(T.started(1793514600, DST_NOW), "Sun 01:30");
    assert.equal(T.started(1793109600, DST_NOW), "Tue 10:00");
    assert.equal(T.started(1793023200, DST_NOW), "26 Oct");
    assert.equal(T.resets(1795096800), "resets Thu 09:00");
    assert.equal(T.dayShort(1793768400), "04 Nov");
    assert.equal(T.dayName(TODAY), "Tue 17");
    assert.equal(T.dayName(1793505600), "Sun 01");
    assert.equal(T.dayName(1793595600), "Mon 02");
});

t("model families, merged splits, sentences", () => {
    assert.deepEqual(T.family("claude-opus-5-5"), { name: "Opus", colour: "purple" });
    assert.deepEqual(T.family("claude-fable-5-2"), { name: "Fable", colour: "pink" });
    assert.deepEqual(T.family("claude-haiku-5-5"), { name: "Haiku", colour: "cyan" });
    assert.deepEqual(T.family("claude-sonnet-5-5"), { name: "Sonnet", colour: "green" });
    assert.deepEqual(T.family("unknown"), { name: "unknown", colour: "green" });
    assert.deepEqual(T.family("claude-opus"), { name: "claude-opus", colour: "green" });
    const s = T.split([{ model: "claude-haiku-5-5", output: 10 }, { model: "claude-opus-4-1", output: 30 }, { model: "claude-opus-5-5", output: 50 }, { model: "unknown", output: 10 }, { model: "claude-fable-5-2", output: 0 }], "output");
    assert.deepEqual(s.map(x => [x.name, x.value, x.colour]), [["Opus", 80, "purple"], ["Haiku", 10, "cyan"], ["unknown", 10, "green"]]);
    assert.equal(T.sentence(s, false), "Opus 80%, Haiku 10%, unknown 10%");
    const tiny = T.split([{ model: "claude-opus-5-5", tokens: 9996 }, { model: "claude-sonnet-5-5", tokens: 4 }], "tokens");
    assert.equal(T.sentence(tiny, true), "Opus 100.0%");
    assert.equal(T.sentence(tiny, false), "Opus 100%, Sonnet <1%");
});

// ---- limits --------------------------------------------------------------

const lim = (obj, now) => T.limits(typeof obj === "string" ? obj : JSON.stringify(obj), now === undefined ? NOW : now);
const file = (pct, changes) => Object.assign({ written_at: NOW - 60, seven_day: { used_percentage: pct, resets_at: 1795096800 }, five_hour: null }, changes || {});
const NONE_BAR = { text: "–", glyph: "none", colour: "fg", dim: true };

t("limits: normal, as drawn", () => {
    const l = T.limits(fxText("limits-normal.json"), NOW);
    assert.deepEqual(l.bar, { text: "34%", glyph: "low", colour: "fg", dim: false });
    assert.deepEqual(l.panel, {
        known: true, chip: true, line: "",
        main: { label: "Weekly · all models", value: "34% · resets Thu 09:00", note: "", colour: "fg" },
        meter: { frac: 0.34, colour: "purple" },
        model: { label: "Weekly · Fable", value: "per-model cap not reported", note: "", colour: "muted" },
        fiveHour: { label: "5-hour", value: "none on this plan", note: "", colour: "muted" },
        foot: ""
    });
});

t("limits: from 80 orange, as drawn", () => {
    const l = lim(file(86));
    assert.deepEqual(l.bar, { text: "86%", glyph: "high", colour: "orange", dim: false });
    assert.equal(l.panel.main.value, "86% · resets Thu 09:00");
    assert.equal(l.panel.main.colour, "orange");
    assert.deepEqual(l.panel.meter, { frac: 0.86, colour: "orange" });
    assert.ok(l.panel.model);
    assert.equal(l.panel.fiveHour, null);
    assert.equal(l.panel.foot, "");
    assert.equal(lim(file(80)).bar.colour, "orange");
    assert.equal(lim(file(79.99)).bar.colour, "fg");
    assert.equal(lim(file(79.99)).bar.text, "79%");
});

t("limits: 100 red, as drawn; 99.9 is not; over 100 shown as reported", () => {
    const l = lim(file(100));
    assert.deepEqual(l.bar, { text: "100%", glyph: "full", colour: "red", dim: false });
    assert.equal(l.panel.main.value, "100% · resets Thu 09:00");
    assert.equal(l.panel.main.colour, "red");
    assert.deepEqual(l.panel.meter, { frac: 1, colour: "red" });
    assert.equal(l.panel.model, null);
    assert.equal(l.panel.fiveHour, null);
    assert.equal(l.panel.foot, "Used up: further use draws on usage credits, if enabled, until the reset.");
    assert.deepEqual(lim(file(99.9)).bar, { text: "99%", glyph: "high", colour: "orange", dim: false });
    const over = lim(file(104.6));
    assert.deepEqual(over.bar, { text: "104%", glyph: "full", colour: "red", dim: false });
    assert.equal(over.panel.meter.frac, 1);
    assert.equal(lim(file(33.7)).bar.text, "33%");
});

t("limits: stale from exactly 3,600 s, as drawn", () => {
    assert.equal(lim(file(34, { written_at: NOW - 3599 })).bar.dim, false);
    const l = lim(file(34, { written_at: NOW - 3600 }));
    assert.deepEqual(l.bar, { text: "34%", glyph: "low", colour: "fg", dim: true });
    const drawn = lim(file(34, { written_at: NOW - 3 * 3600 }));
    assert.deepEqual(drawn.panel, {
        known: true, chip: false, line: "",
        main: { label: "Weekly · all models", value: "34%", note: "as of 3 h ago", colour: "fg" },
        meter: { frac: 0.34, colour: "grey" },
        model: null,
        fiveHour: null,
        foot: "Claude Code reports the limits only while a session is running."
    });
    assert.deepEqual(lim(file(86, { written_at: NOW - 4000 })).bar, { text: "86%", glyph: "high", colour: "orange", dim: true });
});

t("limits: no reading, as drawn", () => {
    const unknown = { known: false, chip: false, line: "Not known yet: Claude Code reports them after its first reply since the last reset. Usage below is counted here.", main: null, meter: null, model: null, fiveHour: null, foot: "" };
    for (const text of [null, undefined, "", "garbage", "[1]", "null", "{\"written_at\":1}", JSON.stringify(file(34, { seven_day: null })),
        JSON.stringify(file(34, { seven_day: { used_percentage: "34", resets_at: 1795096800 } })),
        JSON.stringify(file(34, { written_at: "x" }))]) {
        const l = T.limits(text, NOW);
        assert.equal(l.reading, null, String(text));
        assert.deepEqual(l.bar, NONE_BAR);
        assert.deepEqual(l.panel, unknown);
    }
    // The week's reset has passed: that value is not this week's.
    assert.equal(lim(file(34, { seven_day: { used_percentage: 34, resets_at: NOW } })).reading, null);
    assert.ok(lim(file(34, { seven_day: { used_percentage: 34, resets_at: NOW + 1 } })).reading);
});

t("limits: a five_hour reading shows in every state that has a reading", () => {
    const l = T.limits(fxText("limits-five-hour.json"), NOW);
    assert.deepEqual(l.panel.fiveHour, { label: "5-hour", value: "12% · resets Tue 12:00", note: "", colour: "fg" });
    const five = { used_percentage: 85, resets_at: NOW + 600 };
    assert.equal(lim(file(86, { five_hour: five })).panel.fiveHour.value, "85% · resets Tue 09:25");
    assert.equal(lim(file(86, { five_hour: five })).panel.fiveHour.colour, "orange");
    assert.ok(lim(file(100, { five_hour: five })).panel.fiveHour);
    const stale = lim(file(34, { written_at: NOW - 3600, five_hour: five })).panel.fiveHour;
    assert.deepEqual(stale, { label: "5-hour", value: "85%", note: "as of 1 h ago", colour: "orange" });
    // Its reset passed: back to the drawn text.
    assert.equal(lim(file(34, { five_hour: { used_percentage: 85, resets_at: NOW } })).panel.fiveHour.value, "none on this plan");
});

// ---- overview ------------------------------------------------------------

t("opened: overview, asks the overview", () => {
    const r = T.opened();
    assert.equal(r.state.page, "overview");
    assert.equal(r.state.period, "7d");
    assert.deepEqual(r.effects, [{ do: "send", req: { req: "overview", id: 1 } }]);
    const v = T.view(r.state, LIM);
    assert.equal(v.overview.loading, true);
    assert.equal(v.overview.meta, "Ultra · this host");
    assert.equal(v.overview.today, null);
    assert.equal(v.overview.older, null);
});

t("overview: normal, as drawn", () => {
    const v = T.view(overview(), LIM);
    const o = v.overview;
    assert.equal(v.single, "");
    assert.equal(o.title, "Claude usage");
    assert.equal(o.meta, "Ultra · this host");
    assert.equal(o.limits, LIM.panel);
    assert.equal(o.loading, false);
    assert.deepEqual(o.today, { output: "463 k tokens · 14 sessions", cache: "96.8 M" });
    assert.equal(o.last14.bars.length, 14);
    assert.deepEqual(o.last14.bars[11], { frac: 1, colour: "grey" });
    assert.deepEqual(o.last14.bars[13], { frac: 463000 / 3750000, colour: "purple" });
    assert.equal(o.last14.bars[0].frac, 543000 / 3750000);
    assert.equal(o.last14.left, "04 Nov");
    assert.equal(o.last14.middle, "peak 3.75 M (15 Nov)");
    assert.equal(o.last14.right, "today");
    assert.deepEqual(o.last30.split.map(s => s.colour), ["purple", "pink", "cyan", "green"]);
    assert.equal(o.last30.split[0].frac, 9020000000 / 10000000000);
    assert.equal(o.last30.sentence, "All tokens by model: Opus 90.2%, Fable 9.5%, Haiku 0.3%");
    assert.equal(o.last30.cacheHit, "98.4%");
    assert.equal(o.last30.subagents, "22% of output");
    assert.equal(o.last30.price, "≈ $3,571");
    assert.equal(o.last30.plan, "(plan $200)");
    assert.equal(o.last30.unpriced, "");
    assert.deepEqual(o.top7, {
        rows: [{ name: "alpha", value: "8.83 M" }, { name: "beta", value: "5.12 M" }, { name: "gamma", value: "1.71 M" }, { name: "temporary directories", value: "1.53 M" }],
        more: "and 10 more: P",
        empty: ""
    });
    assert.equal(o.older, null);
    assert.equal(o.olderBefore, "");
    assert.equal(o.unreadable, "");
    assert.equal(o.error, "");
    assert.deepEqual(v.hints, [["P", "projects"], ["D", "days"], ["R", "refresh"], ["Esc", "close"]]);
});

t("overview: not priced, unreadable, null ratios, one session, no more projects, no output", () => {
    const st0 = T.opened().state;
    const a = fx("overview-full.json");
    a.last30.unpriced_models = ["claude-x-9", "unknown"];
    a.last30.cache_hit = null;
    a.last30.subagent_share = null;
    a.progress.unreadable = 3;
    a.today.sessions = 1;
    a.top7.more = 0;
    a.last14.days.forEach(d => d.output = 0);
    a.last14.peak = null;
    let st = feed(st0, a, "overview").state;
    let o = T.view(st, LIM).overview;
    assert.equal(o.last30.unpriced, "not priced: claude-x-9, unknown");
    assert.equal(o.last30.cacheHit, "–");
    assert.equal(o.last30.subagents, "– of output");
    assert.equal(o.unreadable, "3 transcripts could not be read");
    assert.equal(o.today.output, "463 k tokens · 1 session");
    assert.equal(o.top7.more, "");
    assert.ok(o.last14.bars.every(b => b.frac === 0));
    assert.equal(o.last14.middle, "no output");
    st = T.event(st, progress(1, 1, R(true, true, true, true, false), { unreadable: 1 })).state;
    assert.equal(T.view(st, LIM).overview.unreadable, "1 transcript could not be read");
    a.top7.projects = [];
    o = T.view(feed(st0, a, "overview").state, LIM).overview;
    assert.equal(o.top7.empty, "No Claude Code replies in the last 7 days.");
});

t("overview: no limits reading and the other limit states pass through", () => {
    const st = overview();
    assert.equal(T.view(st, T.limits(null, NOW)).overview.limits.known, false);
    assert.equal(T.view(st, lim(file(100))).overview.limits.foot, T.TEXT.usedUp);
});

t("overview: first run, as drawn, then filling section by section", () => {
    let r = T.opened();
    let st = answer(r.state, "overview-partial.json", "overview").state;
    let v = T.view(st, LIM);
    let o = v.overview;
    assert.equal(o.meta, "reading transcripts…");
    assert.deepEqual(o.today, { output: "463 k tokens · 14 sessions", cache: "96.8 M" });
    assert.equal(o.last14, null);
    assert.equal(o.last30, null);
    assert.equal(o.top7, null);
    assert.equal(o.olderBefore, "last14");
    assert.deepEqual(o.older, {
        label: "Older transcripts",
        line: "Reading 512 of 826 (2.7 GB)",
        pct: "62%",
        frac: 512 / 826,
        note: "14 days, 30 days and projects appear as their files are read; the first read takes a few seconds."
    });
    assert.deepEqual(v.hints, [["P", "projects"], ["D", "days"], ["Esc", "close"]]);
    // R is inert while the first read runs.
    assert.deepEqual(T.key(st, "R"), { state: st, effects: [], handled: false });
    // A progress event with nothing new ready: no question.
    r = T.event(st, progress(600, 826, R(true, false, false, false, false)));
    assert.deepEqual(sends(r), []);
    assert.equal(T.view(r.state, LIM).overview.older.line, "Reading 600 of 826 (2.7 GB)");
    assert.equal(T.view(r.state, LIM).overview.older.pct, "73%");
    // 7 days ready: asked again, once while in flight.
    r = T.event(r.state, progress(650, 826, R(true, true, false, false, false)));
    assert.deepEqual(sends(r), [{ req: "overview", id: 2 }]);
    r = T.event(r.state, progress(660, 826, R(true, true, false, false, false)));
    assert.deepEqual(sends(r), []);
    r = T.event(r.state, progress(700, 826, R(true, true, true, false, false)));
    assert.deepEqual(sends(r), []);
    // The answer was computed before 14 days was ready (that event came
    // first): projects in, the block before 14 days, and asked again at once.
    const part = fx("overview-full.json");
    Object.assign(part, { ready: false, last14: null, last30: null });
    part.progress = Object.assign({}, fx("overview-partial.json").progress, { files_read: 655, ready: R(true, true, false, false, false) });
    r = feed(r.state, part, "overview");
    assert.deepEqual(sends(r), [{ req: "overview", id: 3 }]);
    o = T.view(r.state, LIM).overview;
    assert.ok(o.top7);
    assert.equal(o.olderBefore, "last14");
    assert.equal(o.older.note, "14 days and 30 days appear as their files are read; the first read takes a few seconds.");
    part.last14 = fx("overview-full.json").last14;
    part.progress = Object.assign({}, part.progress, { ready: R(true, true, true, false, false) });
    r = feed(r.state, part, "overview");
    assert.deepEqual(sends(r), []);
    o = T.view(r.state, LIM).overview;
    assert.equal(o.olderBefore, "last30");
    assert.equal(o.older.note, "30 days appears as its files are read; the first read takes a few seconds.");
    // 30 days ready: the last question; the answer is ready and complete.
    r = T.event(r.state, progress(826, 826, R(true, true, true, true, false)));
    assert.deepEqual(sends(r), [{ req: "overview", id: 4 }]);
    r = answer(r.state, "overview-full.json", "overview");
    v = T.view(r.state, LIM);
    assert.equal(v.overview.older, null);
    assert.equal(v.overview.meta, "Ultra · this host");
    assert.deepEqual(v.hints.map(h => h[0]), ["P", "D", "R", "Esc"]);
    // The done event of that sync read files: asked once more.
    r = T.event(r.state, DONE(826));
    assert.deepEqual(sends(r), [{ req: "overview", id: 5 }]);
});

t("overview: today not ready yet, and a sync that is still listing", () => {
    const a = fx("overview-partial.json");
    a.today = null;
    a.progress.state = "starting";
    a.progress.files_total = 0;
    a.progress.files_read = 0;
    const o = T.view(feed(T.opened().state, a, "overview").state, LIM).overview;
    assert.equal(o.olderBefore, "today");
    assert.deepEqual(o.older, {
        label: "Transcripts",
        line: "Listing transcripts…",
        pct: "",
        frac: 0,
        note: "Today, 14 days, 30 days and projects appear as their files are read; the first read takes a few seconds."
    });
    // Everything but the last file read: never 100% before it is.
    const b = fx("overview-partial.json");
    b.progress.files_read = 999;
    b.progress.files_total = 1000;
    assert.equal(T.view(feed(T.opened().state, b, "overview").state, LIM).overview.older.pct, "99%");
});

t("refresh: sends refresh; its answer changes nothing; a sync that read files re-asks", () => {
    let st = overview();
    let r = T.key(st, "R");
    assert.equal(r.handled, true);
    assert.deepEqual(r.effects, [{ do: "send", req: { req: "refresh", id: 2 } }]);
    st = r.state;
    r = T.event(st, JSON.stringify({ answer: "refresh", id: 2, now: NOW }));
    assert.equal(r.state, st);
    assert.deepEqual(r.effects, []);
    r = T.event(st, progress(0, 2, R(false, false, true, true, false)));
    assert.deepEqual(sends(r), []);
    // Today and 7 days ready again: the shown answer already had them.
    r = T.event(r.state, progress(2, 2, R(true, true, true, true, false)));
    assert.deepEqual(sends(r), []);
    r = T.event(r.state, DONE(2));
    assert.deepEqual(sends(r), [{ req: "overview", id: 3 }]);
    // A sync with nothing to read does not.
    const quiet = T.event(overview(), DONE(0));
    assert.deepEqual(sends(quiet), []);
    // A done event while the overview is in flight: asked once more after it.
    let s2 = T.key(overview(), "R").state;
    s2 = T.key(T.key(s2, "P").state, "Esc").state;
    r = T.event(s2, DONE(3));
    assert.deepEqual(sends(r), []);
    r = answer(r.state, "overview-full.json", "overview");
    assert.equal(sends(r).length, 1);
    assert.equal(sends(r)[0].req, "overview");
});

t("helper error: a line, and R offered even during the first read", () => {
    let st = answer(T.opened().state, "overview-partial.json", "overview").state;
    st = T.event(st, JSON.stringify({ event: "error", kind: "OperationalError" })).state;
    const v = T.view(st, LIM);
    assert.equal(v.overview.error, "The last read failed (OperationalError). R tries again.");
    assert.deepEqual(v.hints.map(h => h[0]), ["P", "D", "R", "Esc"]);
    // The next sync's progress clears it.
    st = T.event(st, progress(1, 5, R(true, false, false, false, false))).state;
    assert.equal(T.view(st, LIM).overview.error, "");
});

t("lines that are not answers or events change nothing", () => {
    const st = overview();
    for (const line of ["", "not json", "[]", "null", "42", JSON.stringify({ event: "bad-input" }), JSON.stringify({ answer: "nonsense", id: 1 }), JSON.stringify({ event: "hello" })]) {
        const r = T.event(st, line);
        assert.equal(r.state, st, line);
        assert.deepEqual(r.effects, []);
    }
    // A closed panel ignores everything.
    const c = T.closed(st);
    assert.equal(T.event(c, fs.readFileSync(path.join(__dirname, "fixtures", "overview-full.json"), "utf8")).state, c);
    assert.equal(T.key(c, "Esc").handled, false);
});

// ---- projects ------------------------------------------------------------

t("projects: 7 days, page 1 of 2, as drawn", () => {
    let r = T.key(overview(), "P");
    assert.deepEqual(sends(r), [{ req: "projects", period: "7d", id: 2 }]);
    assert.equal(T.view(r.state, LIM).projects.state, "loading");
    const v = T.view(projects(), LIM);
    const p = v.projects;
    assert.equal(p.title, "Projects");
    assert.deepEqual(p.periods, [{ label: "Today", on: false }, { label: "7 days", on: true }, { label: "30 days", on: false }]);
    assert.equal(p.state, "list");
    assert.equal(p.summary, "by output · 18.7 M in all");
    assert.equal(p.range, "1–8 of 14 · page 1/2");
    assert.equal(p.rows.length, 8);
    assert.deepEqual(p.rows.map(x => [x.name, x.output, x.share, x.line]), [
        ["alpha", "8.83 M", "47%", "131 sessions · now · sub-agents 10%"],
        ["beta", "5.12 M", "27%", "7 sessions · 11 h ago · sub-agents 52%"],
        ["gamma", "1.71 M", "9%", "33 sessions · 16 h ago · sub-agents 13%"],
        ["temporary directories", "1.53 M", "8%", "16 sessions · 3 d ago · sub-agents 64%"],
        ["delta", "437 k", "2%", "1 session · 14 h ago · sub-agents 30%"],
        ["epsilon", "369 k", "2%", "3 sessions · 3 d ago · sub-agents 9%"],
        ["zeta", "360 k", "2%", "1 session · 9 h ago · sub-agents 0%"],
        ["eta", "267 k", "1%", "6 sessions · 18 h ago · sub-agents 0%"]
    ]);
    assert.deepEqual(p.rows.map(x => x.selected), [true, false, false, false, false, false, false, false]);
    assert.equal(p.rows[0].shareFrac, 8830000 / 18700000);
    assert.deepEqual(p.rows[0].split, [{ frac: 6560000 / 8830000, colour: "purple" }, { frac: 2200000 / 8830000, colour: "pink" }, { frac: 70000 / 8830000, colour: "cyan" }]);
    // Ordered by output, whatever the answer's model order.
    assert.deepEqual(p.rows[3].split.map(s => s.colour), ["cyan", "purple", "pink"]);
    assert.deepEqual(v.hints, [["↑↓", "select"], ["Enter", "detail"], ["Tab", "period"], ["PgUp/PgDn", "page"], ["D", "days"], ["Esc", "back"]]);
});

t("projects: today with one project, as drawn", () => {
    const r = keys(projects(), ["Tab", "Tab"]);
    assert.equal(r.state.period, "today");
    const v = T.view(answer(r.state, "projects-today.json", "projects").state, LIM);
    assert.deepEqual(v.projects.periods.map(x => x.on), [true, false, false]);
    assert.equal(v.projects.summary, "by output · 463 k in all");
    assert.equal(v.projects.range, "1–1 of 1");
    assert.deepEqual(v.projects.rows.map(x => [x.name, x.output, x.share, x.shareFrac, x.line, x.selected]), [["alpha", "463 k", "100%", 1, "14 sessions · now · sub-agents 6%", true]]);
    assert.deepEqual(v.hints, [["↑↓", "select"], ["Enter", "detail"], ["Tab", "period"], ["D", "days"], ["Esc", "back"]]);
});

t("projects: empty period, each wording, as drawn for today", () => {
    let st = keys(projects(), ["Tab", "Tab"]).state;
    let v = T.view(answer(st, "projects-today-empty.json", "projects").state, LIM);
    assert.equal(v.projects.state, "empty");
    assert.deepEqual(v.projects.empty, ["No Claude Code replies yet today.", "Tab shows the last 7 days."]);
    assert.equal(v.projects.summary, "");
    assert.deepEqual(v.projects.rows, []);
    assert.deepEqual(v.hints, [["Tab", "period"], ["D", "days"], ["Esc", "back"]]);
    st = T.key(overview(), "P").state;
    v = T.view(feed(st, Object.assign(fx("projects-today-empty.json"), { period: "7d" }), "projects").state, LIM);
    assert.deepEqual(v.projects.empty, ["No Claude Code replies in the last 7 days.", "Tab shows the last 30 days."]);
    v = T.view(feed(st, Object.assign(fx("projects-today-empty.json"), { period: "30d" }), "projects").state, LIM);
    assert.deepEqual(v.projects.empty, ["No Claude Code replies in the last 30 days.", "Tab shows today."]);
    // Enter does nothing in an empty list.
    const e = answer(keys(projects(), ["Tab", "Tab"]).state, "projects-today-empty.json", "projects").state;
    assert.equal(T.key(e, "Enter").handled, false);
});

t("projects: 30 days still building, as drawn; re-asked once when ready", () => {
    let r = T.key(projects(), "Tab");
    assert.deepEqual(sends(r), [{ req: "projects", period: "30d", id: 3 }]);
    // The 7-day list stays until the answer comes.
    assert.equal(T.view(r.state, LIM).projects.state, "list");
    assert.deepEqual(T.view(r.state, LIM).projects.periods.map(x => x.on), [false, true, false]);
    r = answer(r.state, "projects-30d-not-ready.json", "projects");
    const v = T.view(r.state, LIM);
    assert.equal(v.projects.state, "building");
    assert.deepEqual(v.projects.periods.map(x => x.on), [false, false, true]);
    assert.deepEqual(v.projects.building, {
        label: "Still reading older transcripts",
        line: "512 of 826 files",
        pct: "62%",
        frac: 512 / 826,
        note: "The 30-day list appears when every file that can hold its replies is read: a partial count would rank projects wrongly. Today and 7 days are already complete."
    });
    assert.deepEqual(v.hints, [["Tab", "period"], ["D", "days"], ["Esc", "back"]]);
    assert.equal(T.key(r.state, "Enter").handled, false);
    r = T.event(r.state, progress(700, 826, R(true, true, true, false, false)));
    assert.deepEqual(sends(r), []);
    assert.equal(T.view(r.state, LIM).projects.building.line, "700 of 826 files");
    r = T.event(r.state, progress(826, 826, R(true, true, true, true, false)));
    assert.deepEqual(sends(r), [{ req: "projects", period: "30d", id: 4 }]);
    r = T.event(r.state, progress(826, 826, R(true, true, true, true, false)));
    assert.deepEqual(sends(r), []);
    r = T.event(r.state, DONE(826));
    assert.deepEqual(sends(r), []);
    // 7 days and today building: their wordings.
    const nr = Object.assign(fx("projects-30d-not-ready.json"), { needs: "7d" });
    nr.progress.ready = R(true, false, false, false, false);
    let st = T.key(overview(), "P").state;
    assert.equal(T.view(feed(st, nr, "projects").state, LIM).projects.building.note,
        "The 7-day list appears when every file that can hold its replies is read: a partial count would rank projects wrongly. Today is already complete.");
    st = keys(st, ["Tab", "Tab"]).state;
    nr.needs = "today";
    nr.progress.ready = R(false, false, false, false, false);
    const b = T.view(feed(st, nr, "projects").state, LIM).projects.building;
    assert.equal(b.label, "Still reading transcripts");
    assert.equal(b.note, "Today's list appears when every file that can hold its replies is read: a partial count would rank projects wrongly.");
});

t("projects: late and mismatched answers are dropped", () => {
    let st = T.key(overview(), "P").state;
    const first = st.asked.projects;
    st = T.key(st, "Tab").state;
    const late = Object.assign(fx("projects-7d.json"), { id: first });
    const r = T.event(st, JSON.stringify(late));
    assert.equal(r.state, st);
    assert.equal(T.view(r.state, LIM).projects.state, "loading");
    // An answer for another page's id, and one with no id.
    assert.equal(T.event(st, JSON.stringify(Object.assign(fx("projects-7d.json"), { id: st.asked.overview }))).state, st);
    assert.equal(T.event(st, JSON.stringify(Object.assign(fx("projects-7d.json"), { id: null }))).state, st);
    // A late overview after leaving it is kept for the overview, not shown here.
    const ov = T.event(st, JSON.stringify(Object.assign(fx("overview-full.json"), { id: st.asked.overview })));
    assert.equal(T.view(ov.state, LIM).page, "projects");
});

t("projects: ↑↓ move and turn the page; both ends do nothing", () => {
    let st = projects();
    assert.deepEqual(T.key(st, "Up"), { state: st, effects: [], handled: true });
    let r = keys(st, ["Down", "Down"]);
    assert.equal(r.state.selected, 2);
    r = keys(st, ["Down", "Down", "Down", "Down", "Down", "Down", "Down"]);
    assert.equal(T.view(r.state, LIM).projects.rows[7].selected, true);
    assert.equal(T.view(r.state, LIM).projects.range, "1–8 of 14 · page 1/2");
    r = T.key(r.state, "Down");
    let p = T.view(r.state, LIM).projects;
    assert.equal(p.range, "9–14 of 14 · page 2/2");
    assert.deepEqual(p.rows.map(x => x.name), ["theta", "iota", "kappa", "lambda", "mu", "nu"]);
    assert.equal(p.rows[0].selected, true);
    assert.deepEqual(p.rows.map(x => x.line)[5], "1 session · 2 d ago · sub-agents 0%");
    r = T.key(r.state, "Up");
    assert.equal(T.view(r.state, LIM).projects.range, "1–8 of 14 · page 1/2");
    assert.equal(r.state.selected, 14);
    r = keys(r.state, ["Down", "Down", "Down", "Down", "Down", "Down", "Down"]);
    assert.equal(r.state.selected, 20);
    const end = T.key(r.state, "Down");
    assert.equal(end.state, r.state);
    assert.equal(end.handled, true);
    assert.deepEqual(end.effects, []);
});

t("projects: PgUp/PgDn, selection to the page's first row", () => {
    let st = T.key(projects(), "Down").state;
    let r = T.key(st, "PgDn");
    assert.equal(r.state.selected, 15);
    assert.equal(T.key(r.state, "PgDn").state, r.state);
    r = T.key(T.key(r.state, "Down").state, "PgUp");
    assert.equal(r.state.selected, 3);
    assert.equal(T.key(r.state, "PgUp").state, r.state);
});

t("projects: paging with 0, 1, 8, 9, 16 and 17 rows", () => {
    const want = {
        0: null,
        1: ["1–1 of 1", false],
        8: ["1–8 of 8", false],
        9: ["1–8 of 9 · page 1/2", true],
        16: ["1–8 of 16 · page 1/2", true],
        17: ["1–8 of 17 · page 1/3", true]
    };
    for (const k of Object.keys(want)) {
        const count = Number(k);
        const st = feed(T.key(overview(), "P").state, rowsAnswer(count, "7d"), "projects").state;
        const v = T.view(st, LIM);
        const paged = v.hints.some(h => h[0] === "PgUp/PgDn");
        if (!want[k]) {
            assert.equal(v.projects.state, "empty");
            assert.equal(paged, false);
            continue;
        }
        assert.equal(v.projects.range, want[k][0], k);
        assert.equal(paged, want[k][1], k);
        assert.equal(v.projects.rows.length, Math.min(8, count));
        // The last page: PgDn as far as it goes, then the range and rows.
        const last = keys(st, ["PgDn", "PgDn", "PgDn"]).state;
        const lv = T.view(last, LIM).projects;
        const pages = Math.ceil(count / 8);
        const from = (pages - 1) * 8 + 1;
        assert.equal(lv.range, `${from}–${count} of ${count}` + (pages > 1 ? ` · page ${pages}/${pages}` : ""), k);
        assert.equal(lv.rows.length, count - from + 1);
        // ↓ to the very last row, then ↓ does nothing.
        const bottom = keys(last, Array(8).fill("Down")).state;
        assert.equal(bottom.selected, 100 + count - 1);
    }
});

t("projects: selection across period changes: kept, moved to another page, gone", () => {
    // Kept: alpha is in today's list.
    let st = projects();
    let r = keys(st, ["Tab", "Tab"]);
    st = answer(r.state, "projects-today.json", "projects").state;
    assert.equal(st.selected, 3);
    // Moved to another page: eta (row 8 of the 7-day list) is row 12 in 30 days.
    st = keys(projects(), ["Down", "Down", "Down", "Down", "Down", "Down", "Down"]).state;
    assert.equal(st.selected, 14);
    st = T.key(st, "Tab").state;
    const month = rowsAnswer(28, "30d");
    month.projects[11] = Object.assign({}, month.projects[11], { id: 14, name: "eta" });
    st = feed(st, month, "projects").state;
    let p = T.view(st, LIM).projects;
    assert.equal(st.selected, 14);
    assert.equal(p.range, "9–16 of 28 · page 2/4");
    assert.deepEqual(p.rows.map(x => x.selected), [false, false, false, true, false, false, false, false]);
    assert.equal(p.rows[3].name, "eta");
    // Gone: nu has no output in 30 days, so the top row.
    st = keys(projects(), ["PgDn", "Down", "Down", "Down", "Down", "Down"]).state;
    assert.equal(st.selected, 20);
    st = feed(T.key(st, "Tab").state, rowsAnswer(28, "30d"), "projects").state;
    assert.equal(st.selected, 100);
    p = T.view(st, LIM).projects;
    assert.equal(p.range, "1–8 of 28 · page 1/4");
    assert.equal(p.rows[0].selected, true);
    // Tab cycles today → 7 days → 30 days → today; the period is kept on the
    // way back to the overview and 7 days again at the next open.
    st = projects();
    const periods = [];
    for (let i = 0; i < 4; i++) {
        r = T.key(st, "Tab");
        periods.push(sends(r)[0].period);
        st = r.state;
    }
    assert.deepEqual(periods, ["30d", "today", "7d", "30d"]);
    st = T.key(st, "Esc").state;
    assert.equal(st.period, "30d");
    assert.deepEqual(sends(T.key(st, "P")), [{ req: "projects", period: "30d", id: st.nextId }]);
    const again = T.opened(T.closed(st));
    assert.equal(again.state.period, "7d");
    assert.ok(again.effects[0].req.id > st.asked.projects);
});

t("projects: a 61-character name passes through whole", () => {
    const name = "an-example-repository-with-a-name-far-too-long-for-the-panel1";
    assert.equal(name.length, 61);
    const a = rowsAnswer(2, "7d");
    a.projects[0].name = name;
    const st = feed(T.key(overview(), "P").state, a, "projects").state;
    assert.equal(T.view(st, LIM).projects.rows[0].name, name);
});

t("projects: an unknown model id in a row's split", () => {
    const a = rowsAnswer(1, "7d");
    a.projects[0].models = [{ model: "claude-opus-5-5", output: 600 }, { model: "unknown", output: 400 }];
    a.projects[0].output = 1000;
    const st = feed(T.key(overview(), "P").state, a, "projects").state;
    assert.deepEqual(T.view(st, LIM).projects.rows[0].split, [{ frac: 0.6, colour: "purple" }, { frac: 0.4, colour: "green" }]);
});

t("projects: D days, Esc back to the overview", () => {
    let r = T.key(projects(), "D");
    assert.equal(r.state.page, "days");
    assert.deepEqual(sends(r), [{ req: "days", id: 3 }]);
    r = T.key(projects(), "Esc");
    assert.equal(r.state.page, "overview");
    assert.deepEqual(sends(r), [{ req: "overview", id: 3 }]);
    // The kept overview shows until its new answer comes.
    assert.equal(T.view(r.state, LIM).overview.loading, false);
});

// ---- detail --------------------------------------------------------------

t("detail: Enter asks for the selected project; drawn as designed", () => {
    let r = T.key(projects(), "Enter");
    assert.equal(r.state.page, "detail");
    assert.deepEqual(sends(r), [{ req: "project", project: 3, period: "7d", id: 3 }]);
    let v = T.view(r.state, LIM);
    assert.equal(v.detail.title, "‹ alpha");
    assert.equal(v.detail.state, "loading");
    r = answer(r.state, "project-alpha-7d.json", "detail");
    v = T.view(r.state, LIM);
    const d = v.detail;
    assert.equal(d.title, "‹ alpha");
    assert.deepEqual(d.periods.map(x => x.on), [false, true, false]);
    assert.equal(d.state, "shown");
    assert.equal(d.output, "8.83 M · 47% of all");
    assert.equal(d.sessions, "131");
    assert.equal(d.subagents, "10% of output");
    assert.deepEqual(d.split.map(s => s.colour), ["purple", "pink", "cyan"]);
    assert.equal(d.split[0].frac, 6540000 / 8830000);
    assert.equal(d.sentence, "Opus 74%, Fable 25%, Haiku 1% of output");
    assert.equal(d.last14.left, "04 Nov");
    assert.equal(d.last14.middle, "peak 3.52 M");
    assert.equal(d.last14.right, "today");
    assert.deepEqual(d.last14.bars[13], { frac: 463000 / 3520000, colour: "purple" });
    assert.deepEqual(d.rows, [
        { started: "09:14", last: "now", output: "3.9 k", replies: "14", active: "1 min" },
        { started: "Sat 18:29", last: "now", output: "1.26 M", replies: "1,461", active: "17 h 03" },
        { started: "09:14", last: "now", output: "3.1 k", replies: "6", active: "<1 min" },
        { started: "08:31", last: "23 min ago", output: "59.4 k", replies: "66", active: "10 min" },
        { started: "08:34", last: "35 min ago", output: "23.3 k", replies: "51", active: "5 min" },
        { started: "08:24", last: "43 min ago", output: "37.4 k", replies: "50", active: "7 min" }
    ]);
    assert.equal(d.note, "Active: time between replies, gaps over 10 min left out.");
    assert.deepEqual(v.hints, [["Tab", "period"], ["Esc", "back"]]);
});

t("detail: Tab asks again for the next period; previous answer kept until then", () => {
    let st = answer(T.key(projects(), "Enter").state, "project-alpha-7d.json", "detail").state;
    let r = T.key(st, "Tab");
    assert.deepEqual(sends(r), [{ req: "project", project: 3, period: "30d", id: 4 }]);
    let d = T.view(r.state, LIM).detail;
    assert.equal(d.output, "8.83 M · 47% of all");
    assert.deepEqual(d.periods.map(x => x.on), [false, true, false]);
    const month = fx("project-alpha-7d.json");
    month.period = "30d";
    month.totals = { output: 12000000, share: 0.36, sessions: 200, subagent_output: 0, models: [{ model: "claude-opus-5-5", output: 12000000 }] };
    r = feed(r.state, month, "detail");
    d = T.view(r.state, LIM).detail;
    assert.equal(d.output, "12.0 M · 36% of all");
    assert.equal(d.subagents, "0% of output");
    assert.equal(d.sentence, "Opus 100% of output");
    assert.deepEqual(d.periods.map(x => x.on), [false, false, true]);
    // The 14 days and the sessions do not follow the period.
    assert.equal(d.rows.length, 6);
    assert.equal(d.last14.middle, "peak 3.52 M");
    // The late 7-day answer to the first question is dropped.
    const late = Object.assign(fx("project-alpha-7d.json"), { id: st.asked.detail });
    assert.equal(T.event(r.state, JSON.stringify(late)).state, r.state);
});

t("detail: not ready (needs the whole sync), then ready", () => {
    let r = T.key(projects(), "Enter");
    const nr = Object.assign(fx("projects-30d-not-ready.json"), { answer: "project", needs: "all" });
    r = feed(r.state, nr, "detail");
    let v = T.view(r.state, LIM);
    assert.equal(v.detail.state, "building");
    assert.deepEqual(v.detail.building, {
        label: "Still reading older transcripts",
        line: "512 of 826 files",
        pct: "62%",
        frac: 512 / 826,
        note: "A project's detail appears when every transcript is read: its sessions and totals draw on all of them."
    });
    assert.deepEqual(v.hints, [["Tab", "period"], ["Esc", "back"]]);
    r = T.event(r.state, progress(826, 826, R(true, true, true, true, false)));
    assert.deepEqual(sends(r), []);
    r = T.event(r.state, DONE(826));
    assert.deepEqual(sends(r), [{ req: "project", project: 3, period: "7d", id: 4 }]);
});

t("detail: an unknown project", () => {
    let r = T.key(projects(), "Enter");
    r = T.event(r.state, JSON.stringify({ answer: "project", id: r.state.asked.detail, now: NOW, bounds: {}, ready: true, error: "unknown project" }));
    const d = T.view(r.state, LIM).detail;
    assert.equal(d.state, "error");
    assert.equal(d.error, "The helper could not answer: unknown project.");
});

t("detail: Esc back to projects, same selection and page", () => {
    let st = keys(projects(), ["PgDn", "Down", "Down"]).state;
    assert.equal(st.selected, 17);
    st = T.key(st, "Enter").state;
    assert.equal(st.detail.name, "kappa");
    const r = T.key(st, "Esc");
    assert.equal(r.state.page, "projects");
    assert.deepEqual(sends(r), [{ req: "projects", period: "7d", id: 4 }]);
    const p = T.view(r.state, LIM).projects;
    assert.equal(p.range, "9–14 of 14 · page 2/2");
    assert.equal(p.rows[2].selected, true);
    const after = answer(r.state, "projects-7d.json", "projects").state;
    assert.equal(after.selected, 17);
    assert.equal(T.view(after, LIM).projects.range, "9–14 of 14 · page 2/2");
});

t("detail: another project never shows the last one's numbers", () => {
    let st = answer(T.key(projects(), "Enter").state, "project-alpha-7d.json", "detail").state;
    st = keys(st, ["Esc", "Down", "Enter"]).state;
    const d = T.view(st, LIM).detail;
    assert.equal(d.title, "‹ beta");
    assert.equal(d.state, "loading");
    assert.equal(d.output, "");
    assert.deepEqual(d.rows, []);
});

// ---- days ----------------------------------------------------------------

t("days: as drawn", () => {
    let r = T.key(overview(), "D");
    assert.deepEqual(sends(r), [{ req: "days", id: 2 }]);
    assert.equal(T.view(r.state, LIM).days.state, "loading");
    const v = T.view(answer(r.state, "days.json", "days").state, LIM);
    const d = v.days;
    assert.equal(d.title, "Days");
    assert.equal(d.meta, "last 14 days");
    assert.deepEqual(d.columns, ["Day", "Output", "", "Sessions", "Top project"]);
    assert.equal(d.rows.length, 14);
    assert.deepEqual(d.rows[0], { day: "Tue 17", frac: 463000 / 3750000, colour: "purple", output: "463 k", sessions: "14", top: "alpha", today: true });
    assert.deepEqual(d.rows[2], { day: "Sun 15", frac: 1, colour: "grey", output: "3.75 M", sessions: "56", top: "alpha", today: false });
    assert.deepEqual(d.rows.map(x => [x.day, x.output, x.sessions, x.top]), [
        ["Tue 17", "463 k", "14", "alpha"], ["Mon 16", "2.97 M", "55", "alpha"], ["Sun 15", "3.75 M", "56", "alpha"],
        ["Sat 14", "3.14 M", "36", "alpha"], ["Fri 13", "2.52 M", "34", "beta"], ["Thu 12", "3.28 M", "10", "beta"],
        ["Wed 11", "2.58 M", "20", "beta"], ["Tue 10", "1.88 M", "9", "epsilon"], ["Mon 09", "1.27 M", "14", "beta"],
        ["Sun 08", "1.07 M", "8", "alpha"], ["Sat 07", "1.08 M", "8", "alpha"], ["Fri 06", "715 k", "7", "nu"],
        ["Thu 05", "623 k", "21", "alpha"], ["Wed 04", "543 k", "10", "alpha"]
    ]);
    assert.deepEqual(d.rows.map(x => Math.round(x.frac * 100)), [12, 79, 100, 84, 67, 87, 69, 50, 34, 29, 29, 19, 17, 14]);
    assert.deepEqual(v.hints, [["P", "projects"], ["Esc", "back"]]);
});

t("days: across the DST change, days with no output", () => {
    const v = T.view(answer(T.key(overview(), "D").state, "days-dst.json", "days").state, LIM);
    assert.deepEqual(v.days.rows.slice(0, 4).map(x => [x.day, x.output, x.sessions, x.top, x.today, x.frac]), [
        ["Mon 02", "120 k", "2", "alpha", true, 120000 / 250000],
        ["Sun 01", "250 k", "3", "alpha", false, 1],
        ["Sat 31", "0", "0", "", false, 0],
        ["Fri 30", "0", "0", "", false, 0]
    ]);
    assert.equal(v.days.rows[13].day, "Tue 20");
    const zero = fx("days-dst.json");
    zero.days.forEach(d => { d.output = 0; d.sessions = 0; d.top = null; });
    const z = T.view(feed(T.key(overview(), "D").state, zero, "days").state, LIM);
    assert.ok(z.days.rows.every(x => x.frac === 0));
});

t("days: building, P projects from the top, Esc back", () => {
    let r = T.key(overview(), "D");
    const nr = Object.assign(fx("projects-30d-not-ready.json"), { answer: "days", needs: "14d" });
    r = feed(r.state, nr, "days");
    const v = T.view(r.state, LIM);
    assert.equal(v.days.state, "building");
    assert.equal(v.days.building.note, "The days appear when every file that can hold their replies is read.");
    r = T.event(r.state, progress(700, 826, R(true, true, true, false, false)));
    assert.deepEqual(sends(r), [{ req: "days", id: 3 }]);
    let st = keys(projects(), ["PgDn"]).state;
    st = T.key(st, "D").state;
    r = T.key(st, "P");
    assert.equal(r.state.page, "projects");
    assert.equal(r.state.selected, null);
    assert.equal(T.view(r.state, LIM).projects.rows[0].selected, true);
    assert.equal(T.key(st, "Esc").state.page, "overview");
});

// ---- the helper's process ------------------------------------------------

t("helper missing and stopped: one line, only Esc; running again re-asks", () => {
    let st = projects();
    for (const [status, line] of [["missing", "The token helper (desk-tokens) was not found."], ["stopped", "The token helper (desk-tokens) stopped. Trying again."]]) {
        const r = T.helper(st, status);
        assert.deepEqual(r.effects, []);
        const v = T.view(r.state, LIM);
        assert.equal(v.single, line);
        assert.equal(v.projects, null);
        assert.deepEqual(v.hints, [["Esc", "close"]]);
        assert.deepEqual(T.key(r.state, "Esc").effects, [{ do: "close" }]);
        for (const k of T.KEY_NAMES.filter(x => x !== "Esc"))
            assert.equal(T.key(r.state, k).handled, false, k);
    }
    const stopped = T.helper(st, "stopped").state;
    const r = T.helper(stopped, "running");
    assert.deepEqual(sends(r), [{ req: "projects", period: "7d", id: 3 }]);
    assert.equal(T.view(r.state, LIM).single, "");
    // Running while running: nothing.
    assert.deepEqual(T.helper(st, "running").effects, []);
});

// ---- hints and keys agree ------------------------------------------------

t("every hinted key is handled and every handled key is hinted, in every state", () => {
    const states = {};
    states["overview loading"] = T.opened().state;
    states["overview"] = overview();
    states["overview first read"] = answer(T.opened().state, "overview-partial.json", "overview").state;
    states["overview error"] = T.event(states["overview first read"], JSON.stringify({ event: "error", kind: "X" })).state;
    states["projects loading"] = T.key(overview(), "P").state;
    states["projects 2 pages"] = projects();
    states["projects 1 page"] = feed(T.key(overview(), "P").state, rowsAnswer(3, "7d"), "projects").state;
    states["projects empty"] = feed(T.key(overview(), "P").state, rowsAnswer(0, "7d"), "projects").state;
    states["projects building"] = answer(T.key(projects(), "Tab").state, "projects-30d-not-ready.json", "projects").state;
    states["projects error"] = T.event(states["projects loading"], JSON.stringify({ answer: "projects", id: states["projects loading"].asked.projects, now: NOW, error: "bad period" })).state;
    states["detail loading"] = T.key(projects(), "Enter").state;
    states["detail"] = answer(states["detail loading"], "project-alpha-7d.json", "detail").state;
    states["detail building"] = feed(states["detail loading"], Object.assign(fx("projects-30d-not-ready.json"), { answer: "project", needs: "all" }), "detail").state;
    states["days loading"] = T.key(overview(), "D").state;
    states["days"] = answer(states["days loading"], "days.json", "days").state;
    states["days building"] = feed(states["days loading"], Object.assign(fx("projects-30d-not-ready.json"), { answer: "days", needs: "14d" }), "days").state;
    states["missing"] = T.helper(projects(), "missing").state;
    states["stopped"] = T.helper(overview(), "stopped").state;
    const names = { "↑↓": ["Up", "Down"], "PgUp/PgDn": ["PgUp", "PgDn"] };
    for (const [label, st] of Object.entries(states)) {
        const hinted = [].concat(...T.hints(st).map(h => names[h[0]] || [h[0]])).sort();
        const handled = T.KEY_NAMES.filter(k => T.key(st, k).handled).sort();
        assert.deepEqual(handled, hinted, label);
        assert.deepEqual(T.view(st, LIM).hints, T.hints(st), label);
        // Keys not in the design are never handled.
        for (const k of ["Backspace", "J", "K", "Home", "End", "F5", "Space"])
            assert.equal(T.key(st, k).handled, false, `${label}: ${k}`);
    }
    assert.equal(T.view(states["projects error"], LIM).projects.error, "The helper could not answer: bad period.");
});

t("Esc on the overview closes; closed() forgets all but the ids", () => {
    const st = overview();
    const r = T.key(st, "Esc");
    assert.deepEqual(r.effects, [{ do: "close" }]);
    const c = T.closed(r.state);
    assert.equal(c.open, false);
    assert.deepEqual(c.answers, {});
    assert.equal(c.nextId, st.nextId);
});

console.log(`ok: ${n} tests`);
