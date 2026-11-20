// The token panel's decisions: the state held from desk-tokens' answers and
// events, what each key does, the footer hints, every text the four pages and
// the bar item show, and the reading of the plan-limits file. The QML draws
// what view() and limits() return and performs the effects; it decides
// nothing. Plain JavaScript so node can run it too.
//
// Times are epoch seconds, as the helper and the limits file give them.
// Dates and clock times are in the machine's local time zone; day and month
// names are fixed here, not taken from the engine's locale.
//
// Colour keys in views: "purple", "pink", "cyan", "green", "orange", "red",
// "grey", "muted", "fg". Fractions are 0..1.

// Set by hand, from no data source: the plan's name and price, and what the
// panel says about the 5-hour window when Claude Code reports none.
const PLAN = { name: "Ultra", usd: 200, fiveHour: "none on this plan" };

const PAGE_ROWS = 8;
const PERIODS = ["today", "7d", "30d"];
const PERIOD_LABELS = { today: "Today", "7d": "7 days", "30d": "30 days" };
// The overview's sections fill in this order as the first read goes on.
const READY_KEYS = ["today", "7d", "14d", "30d"];
// Every key name key() takes.
const KEY_NAMES = ["Up", "Down", "PgUp", "PgDn", "Tab", "Enter", "Esc", "P", "D", "R", "S"];

const STALE_SECONDS = 3600;

const TEXT = {
    title: "Claude usage",
    reading: "reading transcripts…",
    missing: "The token helper (desk-tokens) was not found.",
    stopped: "The token helper (desk-tokens) stopped. Trying again.",
    limitsUnknown: "Not known yet: Claude Code reports them after its first reply since the last reset. Usage below is counted here.",
    usedUp: "Used up: further use draws on usage credits, if enabled, until the reset.",
    stale: "Claude Code reports the limits only while a session is running.",
    weekly: "Weekly · all models",
    modelCap: "Weekly · Fable",
    modelCapValue: "per-model cap not reported",
    fiveHour: "5-hour",
    firstRead: "the first read takes a few seconds.",
    activeNote: "Active: time between replies, gaps over 10 min left out.",
    detailBuilding: "A project's detail appears when every transcript is read: its sessions and totals draw on all of them.",
    daysBuilding: "The days appear when every file that can hold their replies is read.",
    empty: {
        today: ["No Claude Code replies yet today.", "Tab shows the last 7 days."],
        "7d": ["No Claude Code replies in the last 7 days.", "Tab shows the last 30 days."],
        "30d": ["No Claude Code replies in the last 30 days.", "Tab shows today."]
    },
    top7Empty: "No Claude Code replies in the last 7 days.",
    price: "At API prices",
    unpriced: "unpriced",
    // The one muted line on every page that shows a cost.
    estimate: `Estimates at API list prices; the plan is a flat $${count(PLAN.usd)}.`
};

// The five token types in the cost breakdowns, in drawn order, each with the
// colour of its bar segment (the same in the overview and the detail).
const TYPES = [
    { key: "cache_read", label: "Cache read", colour: "purple" },
    { key: "cache_write_1h", label: "Cache write 1 h", colour: "pink" },
    { key: "cache_write_5m", label: "Cache write 5 min", colour: "orange" },
    { key: "output", label: "Output", colour: "green" },
    { key: "input", label: "Fresh input", colour: "cyan" }
];

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const FAMILIES = {
    opus: { name: "Opus", colour: "purple" },
    fable: { name: "Fable", colour: "pink" },
    haiku: { name: "Haiku", colour: "cyan" },
    sonnet: { name: "Sonnet", colour: "green" }
};

// The page each answer belongs to; the detail page asks with "project".
const PAGE_OF = { overview: "overview", projects: "projects", project: "detail", days: "days" };

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

// A token count: the plain integer under 1,000, else three significant
// digits with k, M or B ("463 k", "59.4 k", "8.83 M"), one decimal for k
// under 10 ("3.9 k"). A value that rounds up to 1,000 of a unit is written in
// the next one ("1.00 M", never "1000 k").
function tokens(n) {
    if (n < 1000)
        return String(Math.round(n));
    const units = [[1e3, "k"], [1e6, "M"], [1e9, "B"]];
    for (let i = 0; i < units.length; i++) {
        const v = n / units[i][0];
        let d = v < 10 ? (i === 0 ? 1 : 2) : v < 100 ? 1 : 0;
        let s = v.toFixed(d);
        if (d === 2 && parseFloat(s) >= 10)
            s = v.toFixed(d = 1);
        if (d === 1 && parseFloat(s) >= 100)
            s = v.toFixed(d = 0);
        if (parseFloat(s) < 1000 || i === units.length - 1)
            return `${s} ${units[i][1]}`;
    }
    return "";
}

// A whole number with thousands separators: "1,461".
function count(n) {
    return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// US dollars: "≈ $0" for 0, "≈ <$0.01" under a cent, two decimals under 10
// ("≈ $4.37"), whole dollars under 10,000 ("≈ $3,571"), then three
// significant digits with k or M ("≈ $12.3 k", "≈ $123 k", "≈ $1.23 M"). A
// value that rounds up to the next form is written in it ("≈ $10", never
// "≈ $10.00"; "≈ $10.0 k", never "≈ $10,000").
function money(usd) {
    if (usd === 0)
        return "≈ $0";
    if (usd < 0.01)
        return "≈ <$0.01";
    if (usd < 10 && parseFloat(usd.toFixed(2)) < 10)
        return "≈ $" + usd.toFixed(2);
    if (Math.round(usd) < 10000)
        return "≈ $" + count(usd);
    const units = [[1e3, "k"], [1e6, "M"]];
    for (let i = 0; i < units.length; i++) {
        const v = usd / units[i][0];
        let d = v < 10 ? 2 : v < 100 ? 1 : 0;
        let s = v.toFixed(d);
        if (d === 2 && parseFloat(s) >= 10)
            s = v.toFixed(d = 1);
        if (d === 1 && parseFloat(s) >= 100)
            s = v.toFixed(d = 0);
        if (parseFloat(s) < 1000 || i === units.length - 1)
            return `≈ $${s} ${units[i][1]}`;
    }
    return "";
}

// A helper cost object's text: "≈ $4.37"; "unpriced" when none of its
// replies had a price; "≈ $4.37 + unpriced" when only some had. "" when there
// is no cost object (a helper older than the cost fields).
function costText(c) {
    if (!c || typeof c !== "object")
        return "";
    if (c.priced === false)
        return TEXT.unpriced;
    if (typeof c.usd !== "number" || !isFinite(c.usd))
        return "";
    return money(c.usd) + (c.partial ? ` + ${TEXT.unpriced}` : "");
}

// The order key of a cost: its priced dollars, or -1 (after every priced
// cost, zero included) when nothing of it is priced or it is missing.
function costRank(c) {
    if (!c || typeof c !== "object" || c.priced === false || typeof c.usd !== "number" || !isFinite(c.usd))
        return -1;
    return c.usd;
}

// "not priced: a, b" for an answer's unpriced_models; "" when none.
function notPriced(models) {
    return Array.isArray(models) && models.length ? `not priced: ${models.join(", ")}` : "";
}

// A ratio as a whole percentage: "47%"; "<1%" for one that rounds to 0 but
// is not 0; "–" for null.
function percent(frac) {
    if (frac === null || frac === undefined)
        return "–";
    const r = Math.round(frac * 100);
    return r === 0 && frac > 0 ? "<1%" : `${r}%`;
}

// A ratio as a percentage with one decimal: "98.4%"; "<0.1%" for one that
// rounds to 0 but is not 0; "–" for null.
function percent1(frac) {
    if (frac === null || frac === undefined)
        return "–";
    const r = Math.round(frac * 1000);
    return r === 0 && frac > 0 ? "<0.1%" : `${(r / 10).toFixed(1)}%`;
}

// Bytes in decimal units: "2.7 GB", "512 MB"; one decimal under 100.
function bytes(b) {
    const units = [[1, "B"], [1e3, "kB"], [1e6, "MB"], [1e9, "GB"], [1e12, "TB"]];
    let i = 0;
    while (i < units.length - 1 && b >= units[i + 1][0])
        i++;
    if (i === 0)
        return `${Math.round(b)} B`;
    for (; i < units.length; i++) {
        const v = b / units[i][0];
        let s = v.toFixed(1);
        if (parseFloat(s) >= 100)
            s = v.toFixed(0);
        if (parseFloat(s) < 1000 || i === units.length - 1)
            return `${s} ${units[i][1]}`;
    }
    return "";
}

// How long before `now` `t` was: "now" under a minute, "23 min ago", "11 h
// ago" under a day, else "3 d ago". Each unit rounds down.
function ago(now, t) {
    const s = now - t;
    if (s < 60)
        return "now";
    if (s < 3600)
        return `${Math.floor(s / 60)} min ago`;
    if (s < 86400)
        return `${Math.floor(s / 3600)} h ago`;
    return `${Math.floor(s / 86400)} d ago`;
}

// A session's active time: "<1 min", "10 min", "17 h 03".
function activeTime(seconds) {
    if (seconds < 60)
        return "<1 min";
    const m = Math.floor(seconds / 60);
    if (m < 60)
        return `${m} min`;
    return `${Math.floor(m / 60)} h ${pad(m % 60)}`;
}

function local(t) {
    return new Date(t * 1000);
}

// The local calendar day of `t` as a day count, so that two days' difference
// is in days even across a daylight-saving change.
function dayNumber(t) {
    const d = local(t);
    return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

function clock(t) {
    const d = local(t);
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// "04 Nov".
function dayShort(t) {
    const d = local(t);
    return `${pad(d.getDate())} ${MONTHS[d.getMonth()]}`;
}

// "Tue 17".
function dayName(t) {
    const d = local(t);
    return `${WEEKDAYS[d.getDay()]} ${pad(d.getDate())}`;
}

// When a session started, against `now`: "09:14" today, "Sat 18:29" on the
// six local days before, else "04 Nov".
function started(t, now) {
    const diff = dayNumber(now) - dayNumber(t);
    if (diff === 0)
        return clock(t);
    if (diff >= 1 && diff <= 6)
        return `${WEEKDAYS[local(t).getDay()]} ${clock(t)}`;
    return dayShort(t);
}

// When a limits reading was written, against `now`: "17:58" today, "Mon
// 17:58" on the six local days before, else "10 Nov 17:58" (a week back is
// today's weekday).
function reported(t, now) {
    const diff = dayNumber(now) - dayNumber(t);
    if (diff === 0)
        return clock(t);
    if (diff >= 1 && diff <= 6)
        return `${WEEKDAYS[local(t).getDay()]} ${clock(t)}`;
    return `${dayShort(t)} ${clock(t)}`;
}

// "resets Thu 09:00".
function resets(t) {
    return `resets ${WEEKDAYS[local(t).getDay()]} ${clock(t)}`;
}

// A model id's family: { name, colour }. claude-opus-*, -fable-*, -haiku-*
// and -sonnet-* by family; any other id is named by itself, in green.
function family(model) {
    const m = /^claude-(opus|fable|haiku|sonnet)-/.exec(model);
    return m ? FAMILIES[m[1]] : { name: String(model), colour: "green" };
}

// `models` ([{ model, <field> }]) merged by family, largest first (ties by
// name), families with nothing left out: [{ name, colour, value, frac }],
// frac of the sum.
function split(models, field) {
    const byName = {};
    const order = [];
    let total = 0;
    for (const m of models || []) {
        const f = family(m.model);
        const v = m[field] || 0;
        if (!byName[f.name]) {
            byName[f.name] = { name: f.name, colour: f.colour, value: 0, frac: 0 };
            order.push(f.name);
        }
        byName[f.name].value += v;
        total += v;
    }
    const out = order.map(n => byName[n]).filter(x => x.value > 0);
    out.sort((a, b) => b.value - a.value || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    out.forEach(x => x.frac = total > 0 ? x.value / total : 0);
    return out;
}

// "Opus 74%, Fable 25%, Haiku 1%" with whole percentages, or with one
// decimal; a family that would print as 0.0% is left out of the latter.
function sentence(parts, oneDecimal) {
    if (oneDecimal)
        return parts.filter(p => Math.round(p.frac * 1000) > 0).map(p => `${p.name} ${percent1(p.frac)}`).join(", ");
    return parts.map(p => `${p.name} ${percent(p.frac)}`).join(", ");
}

function splitBar(parts) {
    return parts.map(p => ({ frac: p.frac, colour: p.colour }));
}

function byName(a, b) {
    return a < b ? -1 : a > b ? 1 : 0;
}

// The cost-by-type block from a cost object with by_type and the five token
// counts beside it: { bar: [{ frac, colour }] (each type's share of the
// priced dollars; all 0 when they are 0), rows: [{ label, colour, tokens,
// cost }] }, five each, in TYPES order. null without a by_type.
function byType(cost, counts) {
    if (!cost || typeof cost !== "object" || !cost.by_type || typeof cost.by_type !== "object")
        return null;
    const usd = TYPES.map(ty => Number(cost.by_type[ty.key]) || 0);
    const sum = usd.reduce((a, b) => a + b, 0);
    return {
        bar: TYPES.map((ty, i) => ({ frac: sum > 0 ? usd[i] / sum : 0, colour: ty.colour })),
        rows: TYPES.map((ty, i) => {
            const n = counts && typeof counts[ty.key] === "number" ? counts[ty.key] : null;
            return {
                label: ty.label,
                colour: ty.colour,
                tokens: n === null ? "" : tokens(n),
                // A type with no tokens cost nothing, whatever else was unpriced.
                cost: n === 0 ? money(0) : costText({ usd: usd[i], priced: cost.priced, partial: cost.partial })
            };
        })
    };
}

// Cost objects merged: the priced dollars summed; unpriced when none has a
// priced part, partial when some part of them is unpriced and some is not.
function mergeCosts(list) {
    let usd = 0;
    let priced = false;
    let unpriced = false;
    for (const c of list) {
        if (!c || typeof c !== "object")
            continue;
        if (c.priced !== false) {
            priced = true;
            usd += Number(c.usd) || 0;
        }
        if (c.priced === false || c.partial)
            unpriced = true;
    }
    return { usd, priced: priced || !unpriced, partial: priced && unpriced };
}

// The cost by model family: [{ name, colour, share (of tokens, one
// decimal), cost }], largest cost first, unpriced last, then by name. null
// when no model carries a cost.
function familyCosts(models) {
    if (!(models || []).some(m => m.cost && typeof m.cost === "object"))
        return null;
    const costs = {};
    for (const m of models) {
        const n = family(m.model).name;
        (costs[n] = costs[n] || []).push(m.cost);
    }
    const rows = split(models, "tokens").map(p => {
        const c = mergeCosts(costs[p.name]);
        return { name: p.name, colour: p.colour, share: percent1(p.frac), cost: costText(c), rank: costRank(c) };
    });
    rows.sort((a, b) => b.rank - a.rank || byName(a.name, b.name));
    return rows.map(r => ({ name: r.name, colour: r.colour, share: r.share, cost: r.cost }));
}

function window_(w) {
    if (!w || typeof w !== "object")
        return null;
    if (typeof w.used_percentage !== "number" || !isFinite(w.used_percentage) || typeof w.resets_at !== "number" || !isFinite(w.resets_at))
        return null;
    return { pct: w.used_percentage, resetsAt: w.resets_at };
}

function reading(text, now) {
    let o = null;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!o || typeof o !== "object" || Array.isArray(o) || typeof o.written_at !== "number")
        return null;
    const week = window_(o.seven_day);
    if (!week || week.resetsAt <= now)
        return null;
    const five = window_(o.five_hour);
    // When the weekly figure was seen (its session's transcript time), if
    // the writer knew it; written_at is when a session last reported it.
    const seen = typeof o.seven_day.evidence_at === "number" ? Math.min(o.seven_day.evidence_at, now) : o.written_at;
    return {
        pct: week.pct,
        resetsAt: week.resetsAt,
        writtenAt: o.written_at,
        seenAt: seen,
        stale: now - o.written_at >= STALE_SECONDS,
        fiveHour: five && five.resetsAt > now ? five : null
    };
}

// The colour and glyph for a percentage as reported (before rounding).
function level(pct) {
    if (pct >= 100)
        return { glyph: "full", colour: "red" };
    if (pct >= 80)
        return { glyph: "high", colour: "orange" };
    return { glyph: "low", colour: "fg" };
}

// The shown percentage: the reported value rounded down.
function shownPercent(pct) {
    return `${Math.floor(pct)}%`;
}

// A limits row; `dated` gives it the reading's time even while it is fresh.
function limitRow(label, w, r, now, dated) {
    return {
        label,
        value: r.stale ? shownPercent(w.pct) : `${shownPercent(w.pct)} · ${resets(w.resetsAt)}`,
        note: r.stale || dated ? `as of ${reported(r.seenAt, now)}` : "",
        colour: level(w.pct).colour
    };
}

// The footer line after R, from limits().reading: what R re-reads, and the
// quota as last reported, which only Claude Code's status line updates.
function refreshLine(r, now) {
    return `Counting tokens again from the transcripts · ${r ? `quota as reported ${reported(r.seenAt, now)}` : "no quota reported yet"}`;
}

// The limits file's text (null or "" when there is none) read at `now`.
// Returns:
//   reading: null (no reading: no file, not JSON, no usable seven_day, or
//     its reset has passed) | { pct, resetsAt, writtenAt, seenAt (the weekly
//     figure's evidence_at, else writtenAt; the "as of" time), stale, fiveHour:
//     null | { pct, resetsAt } (only with a reset still ahead) }
//   bar: { text, glyph: "none" | "low" | "high" | "full", colour, dim }
//   panel: the overview's Plan limits section:
//     { known, chip (the "from Claude Code" chip), line (shown alone when
//       not known), main: null | row, meter: null | { frac, colour },
//       model: null | row, fiveHour: null | row, foot: "" | text }
//     row: { label, value, note (muted, after value), colour }
//   Rows come in this order: main, meter, model, fiveHour, foot.
function limits(text, now) {
    const r = reading(text, now);
    if (!r) {
        return {
            reading: null,
            bar: { text: "–", glyph: "none", colour: "fg", dim: true },
            panel: { known: false, chip: false, line: TEXT.limitsUnknown, main: null, meter: null, model: null, fiveHour: null, foot: "" }
        };
    }
    const lv = level(r.pct);
    let fiveHour = null;
    if (r.fiveHour)
        fiveHour = limitRow(TEXT.fiveHour, r.fiveHour, r, now);
    else if (!r.stale && r.pct < 80)
        fiveHour = { label: TEXT.fiveHour, value: PLAN.fiveHour, note: "", colour: "muted" };
    return {
        reading: r,
        bar: { text: shownPercent(r.pct), glyph: lv.glyph, colour: lv.colour, dim: r.stale },
        panel: {
            known: true,
            chip: !r.stale,
            line: "",
            main: limitRow(TEXT.weekly, r, r, now, true),
            meter: { frac: Math.max(0, Math.min(1, r.pct / 100)), colour: r.stale ? "grey" : lv.colour === "fg" ? "purple" : lv.colour },
            model: !r.stale && r.pct < 100 ? { label: TEXT.modelCap, value: TEXT.modelCapValue, note: "", colour: "muted" } : null,
            fiveHour,
            foot: r.stale ? TEXT.stale : r.pct >= 100 ? TEXT.usedUp : ""
        }
    };
}

function copy(st, changes) {
    return Object.assign({}, st, changes);
}

function withEntry(map, key, value) {
    const out = Object.assign({}, map);
    out[key] = value;
    return out;
}

function without(map, key) {
    const out = Object.assign({}, map);
    delete out[key];
    return out;
}

// The state of a closed panel. Fields: open; helper "running" | "missing" |
// "stopped"; page "overview" | "projects" | "detail" | "days"; period
// "today" | "7d" | "30d"; nextId (the next request id); per page, keyed by
// page: asked (the id of the last request), inFlight (no answer to it yet),
// again (ask once more when it is answered), answers (the last answer kept),
// waiting (the readiness key a not-ready answer named); progress (the newest
// progress, from an event or an answer); error (the last sync's error kind,
// or ""); selected (project id or null); detail (null | { id, name }); sort
// (the projects page's order: "output" | "cost").
function initial() {
    return {
        open: false,
        helper: "running",
        page: "overview",
        period: "7d",
        sort: "output",
        nextId: 1,
        asked: {},
        inFlight: {},
        again: {},
        answers: {},
        waiting: {},
        progress: null,
        error: "",
        selected: null,
        detail: null
    };
}

function request(st, page) {
    if (page === "projects")
        return { req: "projects", period: st.period };
    if (page === "detail")
        return { req: "project", project: st.detail.id, period: st.period };
    return { req: page };
}

// Sends the page's request for what the state shows now.
function ask(st, page) {
    const id = st.nextId;
    const req = Object.assign(request(st, page), { id });
    return {
        state: copy(st, {
            nextId: id + 1,
            asked: withEntry(st.asked, page, id),
            inFlight: withEntry(st.inFlight, page, true),
            again: withEntry(st.again, page, false),
            waiting: without(st.waiting, page)
        }),
        effects: [{ do: "send", req }]
    };
}

// Asks now, or once the request in flight is answered.
function askSoon(st, page) {
    if (st.inFlight[page])
        return { state: copy(st, { again: withEntry(st.again, page, true) }), effects: [] };
    return ask(st, page);
}

function go(st, page, changes) {
    return ask(copy(st, Object.assign({ page }, changes || {})), page);
}

function same(st) {
    return { state: st, effects: [] };
}

// The panel opened: the overview, period 7 days, and the overview asked.
// `st` is the state from before (it keeps the request ids unique), or
// undefined. Returns { state, effects }.
function opened(st) {
    const s = copy(initial(), { open: true, nextId: st ? st.nextId : 1 });
    return ask(s, "overview");
}

// The panel closed: everything but the request ids is forgotten.
function closed(st) {
    return copy(initial(), { nextId: st.nextId });
}

// The helper process's status: "running", "missing" (not on PATH) or
// "stopped" (exited, being restarted). A helper running again after a stop
// is a new process: the page is asked again. Returns { state, effects }.
function helper(st, status) {
    const was = st.helper;
    const s = copy(st, { helper: status });
    if (status !== "running")
        return same(copy(s, { inFlight: {}, again: {}, waiting: {} }));
    if (was !== "running" && s.open)
        return ask(s, s.page);
    return same(s);
}

// True when a progress event shows a period ready that the shown overview
// was computed without.
function overviewBehind(st) {
    const a = st.answers.overview;
    if (!a || a.error || a.ready || !st.progress || !st.progress.ready)
        return false;
    const had = a.progress && a.progress.ready ? a.progress.ready : {};
    return READY_KEYS.some(k => st.progress.ready[k] && !had[k]);
}

function onProgress(st, ev) {
    const s = copy(st, { progress: ev, error: "" });
    const page = s.page;
    const needs = s.waiting[page];
    if (needs) {
        if (ev.ready && ev.ready[needs])
            return ask(s, page);
        return same(s);
    }
    // An overview in flight is not asked again: its answer carries its own
    // progress, and later events are compared with that.
    if (page === "overview" && !s.inFlight.overview && overviewBehind(s))
        return ask(s, page);
    // A finished sync that read something: what is shown may be older, and
    // an answer in flight may have been computed before the sync committed.
    if (ev.state === "done" && ev.files_total > 0 && s.answers[page])
        return askSoon(s, page);
    return same(s);
}

function onAnswer(st, ev) {
    const page = PAGE_OF[ev.answer];
    if (!page || st.asked[page] !== ev.id)
        return same(st);
    let s = copy(st, { inFlight: withEntry(st.inFlight, page, false) });
    // The overview may have been computed before a ready event that came
    // ahead of it in the stream.
    const before = st.progress && st.progress.ready;
    const lagging = page === "overview" && !ev.error && ev.ready === false && before && ev.progress && ev.progress.ready
        && READY_KEYS.some(k => before[k] && !ev.progress.ready[k]);
    if (ev.progress)
        s.progress = Object.assign({ event: "progress", now: ev.now }, ev.progress);
    // An overview with ready false is partial, not refused: it is shown.
    if (ev.ready === false && !ev.error && page !== "overview") {
        s.waiting = withEntry(s.waiting, page, ev.needs);
    } else {
        s.answers = withEntry(s.answers, page, ev);
        s.waiting = without(s.waiting, page);
        if (page === "projects" && !ev.error) {
            const rows = ordered(s, ev);
            if (!rows.some(r => r.id === s.selected))
                s.selected = rows.length ? rows[0].id : null;
        }
    }
    if ((s.again[page] || lagging) && s.page === page)
        return ask(s, page);
    return same(s);
}

// One line from the helper's stdout. Answers are kept only when their id is
// the last one asked for their page; a not-ready answer is remembered and
// the request sent again once a progress event shows what it needs; the
// overview is asked again whenever a period it lacked becomes ready, and the
// shown page whenever a sync that read files finishes. Lines that are not
// JSON objects, bad-input events and the refresh answer change nothing.
// Returns { state, effects, took }: `took` is true for a progress or error
// event or an answer to a page, the lines that show the helper working.
function event(st, line) {
    let ev = null;
    try {
        ev = JSON.parse(line);
    } catch (e) {
        return Object.assign(same(st), { took: false });
    }
    if (!ev || typeof ev !== "object" || Array.isArray(ev))
        return Object.assign(same(st), { took: false });
    const took = ev.event === "progress" || ev.event === "error" || typeof PAGE_OF[ev.answer] === "string";
    let r = same(st);
    if (st.open && ev.event === "progress")
        r = onProgress(st, ev);
    else if (st.open && ev.event === "error")
        r = same(copy(st, { error: String(ev.kind || "error") }));
    else if (st.open && typeof ev.answer === "string")
        r = onAnswer(st, ev);
    return Object.assign(r, { took });
}

function single(st) {
    if (st.helper === "missing")
        return TEXT.missing;
    if (st.helper === "stopped")
        return TEXT.stopped;
    return "";
}

// The overview's first read: its last answer still lacks sections.
function firstRead(st) {
    const a = st.answers.overview;
    return !!(a && !a.error && a.ready === false);
}

function progressBar(p) {
    if (!p || p.state === "starting" || !p.files_total)
        return { frac: 0, pct: "" };
    const f = p.files_read / p.files_total;
    let r = Math.round(f * 100);
    if (r >= 100 && p.files_read < p.files_total)
        r = 99;
    return { frac: Math.min(1, f), pct: `${r}%` };
}

function joinNames(names) {
    if (names.length <= 1)
        return names.join("");
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

function periodControl(period) {
    return PERIODS.map(p => ({ label: PERIOD_LABELS[p], on: p === period }));
}

// A projects answer's rows in the shown order: as the helper sends them (by
// output) or by cost (largest first, unpriced last, then name, then id).
function ordered(st, a) {
    const rows = a.projects || [];
    if (st.sort !== "cost")
        return rows;
    return rows.slice().sort((x, y) => costRank(y.cost) - costRank(x.cost) || byName(x.name, y.name) || x.id - y.id);
}

function shownProjects(st) {
    if (st.waiting.projects)
        return { kind: "building", period: st.period, rows: [] };
    const a = st.answers.projects;
    if (!a)
        return { kind: "loading", period: st.period, rows: [] };
    if (a.error)
        return { kind: "error", period: st.period, rows: [], error: a.error };
    const rows = ordered(st, a);
    return { kind: rows.length ? "list" : "empty", period: a.period, rows, answer: a };
}

function selectedIndex(st, rows) {
    const i = rows.findIndex(r => r.id === st.selected);
    return i < 0 ? 0 : i;
}

function building(st, label, note) {
    const p = st.progress;
    const bar = progressBar(p);
    return {
        label,
        line: p && p.state !== "starting" ? `${count(p.files_read)} of ${count(p.files_total)} files` : "Listing transcripts…",
        pct: bar.pct,
        frac: bar.frac,
        note
    };
}

function bars(last14, today, peakDate) {
    const peak = last14.peak;
    const days = last14.days || [];
    const top = peak ? peak.output : 0;
    return {
        bars: days.map(d => ({ frac: top > 0 ? d.output / top : 0, colour: d.start === today ? "purple" : "grey" })),
        left: days.length ? dayShort(days[0].start) : "",
        middle: peak ? `peak ${tokens(peak.output)}` + (peakDate ? ` (${dayShort(peak.start)})` : "") : "no output",
        right: "today"
    };
}

function overviewView(st, lim) {
    const a = st.answers.overview && !st.answers.overview.error ? st.answers.overview : null;
    const reading = firstRead(st);
    const out = {
        title: TEXT.title,
        meta: reading ? TEXT.reading : `${PLAN.name} · this host`,
        labels: {
            limits: "Plan limits",
            chip: "from Claude Code",
            today: "Today",
            output: "Output",
            cache: "Context read from cache",
            last14: "Last 14 days · output tokens",
            last30: "30 days",
            cacheHit: "Cache hit",
            subagents: "Sub-agents",
            price: TEXT.price,
            top7: "Projects · 7 days output"
        },
        limits: lim ? lim.panel : limits(null, 0).panel,
        loading: !a,
        today: null,
        last14: null,
        last30: null,
        top7: null,
        older: null,
        // Where the older-transcripts block goes: before "today", "last14",
        // "last30" or "top7"; "" when it is not shown.
        olderBefore: "",
        unreadable: "",
        estimate: "",
        error: st.error ? `The last read failed (${st.error}). R tries again.` : ""
    };
    const p = st.progress;
    if (p && p.unreadable > 0)
        out.unreadable = p.unreadable === 1 ? "1 transcript could not be read" : `${count(p.unreadable)} transcripts could not be read`;
    if (!a)
        return out;
    if (a.today)
        out.today = {
            output: `${tokens(a.today.output)} tokens · ${count(a.today.sessions)} ${a.today.sessions === 1 ? "session" : "sessions"}`,
            cache: tokens(a.today.cache_read),
            cost: costText(a.today.cost)
        };
    if (a.last14)
        out.last14 = bars(a.last14, a.bounds.today, true);
    if (a.last30) {
        const l = a.last30;
        const parts = split(l.models, "tokens");
        out.last30 = {
            split: splitBar(parts),
            sentence: "All tokens by model: " + sentence(parts, true),
            cacheHit: percent1(l.cache_hit),
            subagents: `${percent(l.subagent_share)} of output`,
            // cost_usd: what a helper older than the cost object sends.
            price: l.cost ? costText(l.cost) : typeof l.cost_usd === "number" ? money(l.cost_usd) : "",
            plan: `(plan $${count(PLAN.usd)})`,
            unpriced: notPriced(l.unpriced_models),
            byType: byType(l.cost, l.totals),
            families: familyCosts(l.models)
        };
    }
    if (a.top7) {
        const t = a.top7;
        out.top7 = {
            rows: t.projects.map(r => ({ name: r.name, value: tokens(r.output), cost: costText(r.cost) })),
            more: t.more > 0 ? `and ${count(t.more)} more: P` : "",
            empty: t.projects.length ? "" : TEXT.top7Empty
        };
    }
    if ((out.today && out.today.cost) || (out.last30 && out.last30.price) || (out.top7 && out.top7.rows.some(r => r.cost)))
        out.estimate = TEXT.estimate;
    if (reading) {
        const missing = [];
        const names = { today: "today", last14: "14 days", last30: "30 days", top7: "projects" };
        for (const k of ["today", "last14", "last30", "top7"]) {
            if (!out[k])
                missing.push(k);
        }
        if (missing.length) {
            const words = missing.map(k => names[k]);
            words[0] = words[0].charAt(0).toUpperCase() + words[0].slice(1);
            const verb = words.length === 1 ? "appears as its files are read" : "appear as their files are read";
            const bar = progressBar(p);
            out.olderBefore = missing[0];
            out.older = {
                label: out.today ? "Older transcripts" : "Transcripts",
                line: p && p.state !== "starting" ? `Reading ${count(p.files_read)} of ${count(p.files_total)} (${bytes(p.bytes_total)})` : "Listing transcripts…",
                pct: bar.pct,
                frac: bar.frac,
                note: `${joinNames(words)} ${verb}; ${TEXT.firstRead}`
            };
        }
    }
    return out;
}

function projectsView(st) {
    const sp = shownProjects(st);
    const out = {
        title: "Projects",
        periods: periodControl(sp.period),
        state: sp.kind,
        summary: "",
        range: "",
        rows: [],
        empty: [],
        building: null,
        unpriced: "",
        estimate: "",
        error: sp.kind === "error" ? `The helper could not answer: ${sp.error}.` : ""
    };
    if (sp.kind === "empty")
        out.empty = TEXT.empty[sp.period].slice();
    if (sp.kind === "building") {
        const ready = PERIODS.filter(p => p !== st.period && st.progress && st.progress.ready && st.progress.ready[p]).map(p => PERIOD_LABELS[p]);
        const list = st.period === "today" ? "Today's list" : st.period === "7d" ? "The 7-day list" : "The 30-day list";
        let note = `${list} appears when every file that can hold its replies is read: a partial count would rank projects wrongly.`;
        if (ready.length)
            note += ` ${joinNames(ready)} ${ready.length === 1 ? "is" : "are"} already complete.`;
        out.building = building(st, st.period === "today" ? "Still reading transcripts" : "Still reading older transcripts", note);
    }
    if (sp.kind !== "list")
        return out;
    const a = sp.answer;
    const rows = sp.rows;
    const i = selectedIndex(st, rows);
    const page = Math.floor(i / PAGE_ROWS);
    const pages = Math.ceil(rows.length / PAGE_ROWS);
    const first = page * PAGE_ROWS;
    const last = Math.min(rows.length, first + PAGE_ROWS);
    const total = costText(a.cost);
    out.summary = `by ${st.sort === "cost" ? "cost" : "output"} · ${tokens(a.output)}` + (total ? ` · ${total}` : "") + " in all";
    out.range = `${first + 1}–${last} of ${rows.length}` + (pages > 1 ? ` · page ${page + 1}/${pages}` : "");
    out.rows = rows.slice(first, last).map((r, j) => {
        const share = a.output > 0 ? r.output / a.output : null;
        return {
            id: r.id,
            name: r.name,
            output: tokens(r.output),
            share: percent(share),
            shareFrac: share || 0,
            split: splitBar(split(r.models, "output")),
            line: `${count(r.sessions)} ${r.sessions === 1 ? "session" : "sessions"} · ${ago(a.now, r.last_reply)} · sub-agents ${percent(r.output > 0 ? r.subagent_output / r.output : null)}`,
            cost: costText(r.cost),
            selected: first + j === i
        };
    });
    out.unpriced = notPriced(a.unpriced_models);
    if (total || rows.some(r => costText(r.cost)))
        out.estimate = TEXT.estimate;
    return out;
}

function detailView(st) {
    const out = {
        title: `‹ ${st.detail ? st.detail.name : ""}`,
        periods: periodControl(st.period),
        labels: { output: "Output", sessions: "Sessions", subagents: "Sub-agents", cost: TEXT.price, byType: "By type", last14: "Last 14 days · output", rows: "Last sessions" },
        // The fourth header is "" while no session shows a cost.
        columns: ["Started", "Last reply", "Output", ""],
        state: "loading",
        output: "",
        sessions: "",
        subagents: "",
        cost: "",
        split: [],
        sentence: "",
        byType: null,
        last14: null,
        rows: [],
        note: TEXT.activeNote,
        unpriced: "",
        estimate: "",
        building: null,
        error: ""
    };
    if (st.waiting.detail) {
        out.state = "building";
        out.building = building(st, "Still reading older transcripts", TEXT.detailBuilding);
        return out;
    }
    const a = st.answers.detail;
    if (!a)
        return out;
    if (a.error) {
        out.state = "error";
        out.error = `The helper could not answer: ${a.error}.`;
        return out;
    }
    const t = a.totals;
    const parts = split(t.models, "output");
    out.title = `‹ ${a.project.name}`;
    out.periods = periodControl(a.period);
    out.state = "shown";
    out.output = `${tokens(t.output)} · ${percent(t.share)} of all`;
    out.sessions = count(t.sessions);
    out.subagents = `${percent(t.output > 0 ? t.subagent_output / t.output : null)} of output`;
    out.split = splitBar(parts);
    out.sentence = parts.length ? `${sentence(parts, false)} of output` : "";
    out.cost = costText(t.cost);
    out.byType = byType(t.cost, t.tokens);
    out.last14 = bars(a.last14, a.bounds.today, false);
    out.rows = a.sessions.map(x => ({
        started: started(x.first_reply, a.now),
        last: ago(a.now, x.last_reply),
        output: tokens(x.output),
        cost: costText(x.cost),
        replies: count(x.replies),
        active: activeTime(x.active_seconds),
        line: `${count(x.replies)} ${x.replies === 1 ? "reply" : "replies"} · active ${activeTime(x.active_seconds)}`
    }));
    if (out.rows.some(r => r.cost))
        out.columns = ["Started", "Last reply", "Output", "Cost"];
    out.unpriced = notPriced(a.unpriced_models);
    if (out.cost || out.rows.some(r => r.cost))
        out.estimate = TEXT.estimate;
    return out;
}

function daysView(st) {
    const out = {
        title: "Days",
        meta: "last 14 days",
        // The fourth header is "" while no day shows a cost.
        columns: ["Day", "Output", "", "", "Sessions", "Top project"],
        state: "loading",
        rows: [],
        estimate: "",
        building: null,
        error: ""
    };
    if (st.waiting.days) {
        out.state = "building";
        out.building = building(st, "Still reading older transcripts", TEXT.daysBuilding);
        return out;
    }
    const a = st.answers.days;
    if (!a)
        return out;
    if (a.error) {
        out.state = "error";
        out.error = `The helper could not answer: ${a.error}.`;
        return out;
    }
    const most = Math.max.apply(null, [0].concat(a.days.map(d => d.output)));
    out.state = "shown";
    out.rows = a.days.map(d => ({
        day: dayName(d.start),
        frac: most > 0 ? d.output / most : 0,
        colour: d.start === a.bounds.today ? "purple" : "grey",
        output: tokens(d.output),
        cost: costText(d.cost),
        sessions: count(d.sessions),
        top: d.top ? d.top.name : "",
        today: d.start === a.bounds.today
    }));
    if (out.rows.some(r => r.cost)) {
        out.columns = ["Day", "Output", "", "Cost", "Sessions", "Top project"];
        out.estimate = TEXT.estimate;
    }
    return out;
}

function nextPeriod(p) {
    return PERIODS[(PERIODS.indexOf(p) + 1) % PERIODS.length];
}

function moveTo(st, rows, i) {
    if (i < 0 || i >= rows.length)
        return same(st);
    return same(copy(st, { selected: rows[i].id }));
}

// The key table for the state as it is: [{ keys, hint: [key, label], run }],
// in footer order. Only what is listed is handled and hinted.
function table(st) {
    const esc = (label, run) => ({ keys: ["Esc"], hint: ["Esc", label], run });
    if (single(st))
        return [esc("close", s => ({ state: s, effects: [{ do: "close" }] }))];
    if (st.page === "overview") {
        const t = [
            { keys: ["P"], hint: ["P", "projects"], run: s => go(s, "projects", { selected: null }) },
            { keys: ["D"], hint: ["D", "days"], run: s => go(s, "days") }
        ];
        // Hidden while the first read runs, unless that read failed.
        if (!firstRead(st) || st.error)
            t.push({ keys: ["R"], hint: ["R", "refresh counts"], run: s => ({ state: copy(s, { nextId: s.nextId + 1 }), effects: [{ do: "send", req: { req: "refresh", id: s.nextId } }, { do: "reloadLimits" }] }) });
        t.push(esc("close", s => ({ state: s, effects: [{ do: "close" }] })));
        return t;
    }
    if (st.page === "projects") {
        const sp = shownProjects(st);
        const rows = sp.rows;
        const t = [];
        if (sp.kind === "list") {
            t.push({
                keys: ["Up", "Down"],
                hint: ["↑↓", "select"],
                run: (s, k) => moveTo(s, rows, selectedIndex(s, rows) + (k === "Up" ? -1 : 1))
            });
            t.push({
                keys: ["Enter"],
                hint: ["Enter", "detail"],
                run: s => {
                    const r = rows[selectedIndex(s, rows)];
                    return go(s, "detail", { selected: r.id, detail: { id: r.id, name: r.name }, answers: without(s.answers, "detail") });
                }
            });
        }
        t.push({ keys: ["Tab"], hint: ["Tab", "period"], run: s => ask(copy(s, { period: nextPeriod(s.period) }), "projects") });
        // Not offered for an answer without costs (an older helper).
        if (sp.kind === "list" && sp.answer.cost)
            t.push({ keys: ["S"], hint: ["S", "sort"], run: s => same(copy(s, { sort: s.sort === "cost" ? "output" : "cost" })) });
        if (sp.kind === "list" && rows.length > PAGE_ROWS) {
            t.push({
                keys: ["PgUp", "PgDn"],
                hint: ["PgUp/PgDn", "page"],
                run: (s, k) => {
                    const page = Math.floor(selectedIndex(s, rows) / PAGE_ROWS) + (k === "PgUp" ? -1 : 1);
                    return moveTo(s, rows, page < 0 ? -1 : page * PAGE_ROWS);
                }
            });
        }
        t.push({ keys: ["D"], hint: ["D", "days"], run: s => go(s, "days") });
        t.push(esc("back", s => go(s, "overview")));
        return t;
    }
    if (st.page === "detail")
        return [
            { keys: ["Tab"], hint: ["Tab", "period"], run: s => ask(copy(s, { period: nextPeriod(s.period) }), "detail") },
            esc("back", s => go(s, "projects"))
        ];
    return [
        { keys: ["P"], hint: ["P", "projects"], run: s => go(s, "projects", { selected: null }) },
        esc("back", s => go(s, "overview"))
    ];
}

// A key pressed in the open panel. `key` is one of KEY_NAMES ("Up", "Down",
// "PgUp", "PgDn", "Tab", "Enter", "Esc", "P", "D", "R", "S"); `repeat` is true
// for a held key's auto-repeat, which only the moving keys (arrows, paging)
// act on. Returns { state, effects, handled }; handled is false for a key the
// footer does not offer in this state, which then changes nothing. Effects:
// { do: "send", req } (write req as one JSON line to the helper),
// { do: "reloadLimits" } (read the limits file again and show refreshLine()
// in the footer for a moment) and { do: "close" } (close the panel, then
// call closed()).
function key(st, k, repeat) {
    if (!st.open)
        return { state: st, effects: [], handled: false };
    const entry = table(st).find(e => e.keys.includes(k));
    if (!entry)
        return { state: st, effects: [], handled: false };
    if (repeat && !["Up", "Down", "PgUp", "PgDn"].includes(k))
        return { state: st, effects: [], handled: true };
    const r = entry.run(st, k);
    return { state: r.state, effects: r.effects, handled: true };
}

// The footer's [key, label] pairs, in KeyHints' form: exactly the keys key()
// handles now.
function hints(st) {
    return table(st).map(e => e.hint);
}

// Everything the open panel draws. `lim` is limits()'s result (the overview
// shows its panel section). Returns { single, page, hints, overview,
// projects, detail, days }: single is the one line that replaces the panel
// ("" when none); only the current page's view is filled, the others null.
//   overview: { title, meta, labels: { limits, chip, today, output, cache,
//     last14, last30, cacheHit, subagents, price, top7 } (the sections' and
//     rows' names; price also names Today's cost row), limits
//     (limits().panel), loading (no answer yet), today: null | { output,
//     cache, cost }, last14: null | bars, last30: null | { split, sentence,
//     cacheHit, subagents, price, plan, unpriced, byType: null | byType,
//     families: null | [{ name, colour, share, cost }] }, top7: null |
//     { rows: [{ name, value, cost }], more, empty }, older: null | { label,
//     line, pct, frac, note }, olderBefore, unreadable, estimate, error }
//   bars: { bars: [{ frac, colour }] (oldest first), left, middle, right }
//   byType: { bar: [{ frac, colour }], rows: [{ label, colour, tokens,
//     cost }] }, five each, in the same order and colours on every page
//   projects: { title, periods: [{ label, on }], state: "loading" | "list" |
//     "empty" | "building" | "error", summary, range, rows: [{ id, name,
//     output, share, shareFrac, split: [{ frac, colour }], line, cost,
//     selected }] (this page only, in the shown order), empty (two lines),
//     building: null | { label, line, pct, frac, note }, unpriced, estimate,
//     error }
//   detail: { title, periods, labels: { output, sessions, subagents, cost,
//     byType, last14, rows }, columns (the sessions grid's four headers),
//     state: "loading" | "shown" | "building" | "error", output, sessions,
//     subagents, cost, split, sentence, byType: null | byType, last14: null
//     | bars, rows: [{ started, last, output, cost, replies, active, line }],
//     note, unpriced, estimate, building, error }
//   days: { title, meta, columns (six headers), state: "loading" | "shown" |
//     "building" | "error", rows: [{ day, frac, colour, output, cost,
//     sessions, top, today }] (newest first), estimate, building, error }
// A cost text is "" when the helper sent no cost for it; estimate (the one
// muted line above the footer) and unpriced ("not priced: …") are "" when
// not shown.
function view(st, lim) {
    const out = { single: single(st), page: st.page, hints: hints(st), overview: null, projects: null, detail: null, days: null };
    if (out.single)
        return out;
    if (st.page === "overview")
        out.overview = overviewView(st, lim);
    else if (st.page === "projects")
        out.projects = projectsView(st);
    else if (st.page === "detail")
        out.detail = detailView(st);
    else
        out.days = daysView(st);
    return out;
}

if (typeof module !== "undefined")
    module.exports = {
        PLAN, PAGE_ROWS, PERIODS, KEY_NAMES, TEXT,
        tokens, count, money, costText, percent, percent1, bytes, ago, activeTime, started, resets, dayShort, dayName,
        family, split, sentence,
        limits, refreshLine,
        initial, opened, closed, helper, event, key, hints, view
    };
