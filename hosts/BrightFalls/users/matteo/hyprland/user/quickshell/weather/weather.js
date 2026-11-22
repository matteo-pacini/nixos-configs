// The weather panel's decisions: the state held from desk-weather's events,
// what each key does, the footer, and every text, tone and drawing input the
// forecast page, the radar page and the bar item show. The QML draws what
// these functions return and performs the effects; it decides nothing.
// Plain JavaScript so node can run it too.
//
// Times are Unix seconds, as the helper gives them; `now` is Unix seconds
// too (Date.now() / 1000). Clock times, day names and "today" are in the
// machine's local time zone, which is taken to be the forecast's. Day and
// month names are fixed here, not taken from the engine's locale.
//
// Tones are names: "normal", "soft", "dim", "yellow", "orange", "red",
// "green", "cyan", "pink"; QML maps them to Theme. Fractions are 0..1.
//
// The QML's part:
//   state = initial(); each stdout line: state = apply(state, JSON.parse(line),
//   now), and the restart back-off resets when healthy(event); the process
//   stopping, not starting, or running again: state = helperLost(state,
//   "stopped" | "missing" | "back", seconds to the next start).
//   On every open: ui = initialUi(now), then tick() at least once a second
//   while open (twice a second while the radar plays). A key: r = key(ui,
//   state, name, isAutoRepeat); ui = r.ui; run r.effect. Whenever the panel
//   closes (Esc, a click outside, another panel) with ui.page "radar", send
//   {"cmd":"radar","on":false}.
//
// view(state, now) -> {
//   single: "" | the one plain line that replaces the panel (helper or
//     settings errors); singleParts: [{ text, code }] the same line in pieces,
//     code true for a name drawn in the mono font. With single set, every
//     other field below is null.
//   hero: { big ("7.4°", "−1.8°", "–"), bigTone, age (the line top right),
//     ageTone, condition ("Light rain" | ""), range ("today 3° to 9°" | "") }
//   scene: { blank, day, frac (along the day or the night arc), edge (sun in
//     its first or last 12 % of the day), cloud 0..1, rain (0 none, else
//     0.5..3, streak density), snow, fog, lit (windows) }
//   stats: four of { label, value, unit, tone }: HUMIDITY, WIND, RAIN TODAY
//     or SNOW TODAY, SUNSET or SUNRISE; value "–" with tone "dim" when there
//     is no source.
//   warnings: [{ level "yellow" | "amber" | "red", tone, title, detail
//     (areas · when · Met Office), link }], most severe first; [] for none.
//   body: "forecast" (hours, days and air are filled) | "message" (message is).
//   message: the body's text when there is no forecast to show, else "".
//   hoursHead ("NEXT HOURS"), precipHead ("mm of rain below" | "mm of snow,
//     as water, below" | "mm of rain and snow, as water, below"),
//   hours: null | 3..8 of { now (the first, when it is the current hour),
//     label ("now", "17"), art (artFor key | null),
//     tempText ("9°" | "–"), temp (number | null), precip (mm | null),
//     precipText ("0.4" | ""), precipFrac (of the strip's scale: the wettest
//     shown hour, at least 2.5 mm) }
//   days: null | up to 6 of { label ("Today", "Mon"), today, art, precip,
//     precipText ("6.2 mm" | "–"), dry, loText, hiText, start, end (the bar,
//     0..1 over the rows' lowest and highest; null without both figures),
//     mark ("" | "yellow" | "orange" | "red": a warning covers that day) }
//   air: null | { shown, head, value ("28"), word ("Fair"), tone, bands: six
//     of { tone, on }, marker 0..1, parts: [{ label, value }], unit
//     ("µg/m³"), highest ("NO₂" | ""), pollen ("" | "grass pollen 34 grains/
//     m³"), text (the whole second line, plain), message, messageTone }:
//     shown false means draw only message.
//   source, sourceTone: the line above the footer.
// }
//
// radarView(state, now, frame, playing) -> { state: "frames" | "loading" |
//   "unavailable", head ("past 2 hours, not a forecast" | ""), note ("" |
//   "No rain on the radar." | "Radar not available." | "Fetching the
//   radar…"), frames: [{ time, dir }] oldest first, index (the shown one, or
//   -1), frameDir ("" when none), label ("15:10 · 10 min ago"), labelTone,
//   ticks: ["past" | "on" | "after"] one per frame, left, right (the oldest
//   and newest frame's clock), timeline (whether to draw the ticks), block
//   ({ zoom, tile, x0, y0, cols, rows, centre } | null), playing, source,
//   sourceTone }. `frame` is ui.frame.
//
// barView(state, now) -> { art (key | null), text ("7°", "–°"), dim (the
//   text), warning (null | "yellow" | "amber" | "red", the most severe in
//   force now), warningTone }
//
// ui (initialUi, key, tick): { now, page "forecast" | "radar", frame (null =
//   the newest, else a frame's time), playing, frameAt, warning (the index W
//   opens next), footer (null | the line after R) }.
// key effect: { kind: "none" | "close" | "refresh" | "radarOn" | "radarOff" |
//   "openLink", url ("" unless openLink) }.
// hints(ui, state) -> { keys: [[key, label]], message ("" | the line that
//   replaces them), tone }.

const SENSOR_SILENT = 1800;
const BATTERY_LOW = 15;
const FORECAST_OLD = 7200;
const MIN_FUTURE_HOURS = 3;
const WIND_STRONG = 40;
const RADAR_BEHIND = 1800;
const RADAR_GONE = 7200;
const HOURS = 8;
const DAYS = 6;
// How long a fetch's result shows in the footer, and how long "Fetching"
// waits for one.
const FOOTER_SHOW = 4;
const FOOTER_WAIT = 60;
// The radar loop: each frame, and the hold on the newest.
const FRAME_STEP = 0.5;
const FRAME_HOLD = 2;
// The helper's retry after an error: 60 s doubling to 15 min (contract).
const RETRY_FIRST = 60;
const RETRY_MAX = 900;

const MINUS = "−";
const DASH = "–";
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
const KEY_NAMES = ["R", "M", "W", "Space", "Left", "Right", "Esc"];
const MOVING_KEYS = ["Left", "Right"];
const LINK = /^https:\/\/(www|weather)\.metoffice\.gov\.uk\//;

// Every WMO code Open-Meteo lists: [code, day art, night art, day words,
// night words]; a null night entry is the day's.
const WMO = [
    [0, "sunny", "clear-night", "Sunny", "Clear"],
    [1, "sunny", "clear-night", "Mainly clear", null],
    [2, "partlycloudy", "partlycloudy-night", "Partly cloudy", null],
    [3, "cloudy", null, "Overcast", null],
    [45, "fog", null, "Fog", null],
    [48, "fog", null, "Freezing fog", null],
    [51, "rainy", null, "Light drizzle", null],
    [53, "rainy", null, "Drizzle", null],
    [55, "rainy", null, "Heavy drizzle", null],
    [56, "snowy-rainy", null, "Light freezing drizzle", null],
    [57, "snowy-rainy", null, "Heavy freezing drizzle", null],
    [61, "rainy", null, "Light rain", null],
    [63, "rainy", null, "Rain", null],
    [65, "pouring", null, "Heavy rain", null],
    [66, "snowy-rainy", null, "Light freezing rain", null],
    [67, "snowy-rainy", null, "Heavy freezing rain", null],
    [71, "snowy", null, "Light snow", null],
    [73, "snowy", null, "Snow", null],
    [75, "snowy", null, "Heavy snow", null],
    [77, "snowy", null, "Snow grains", null],
    [80, "rainy", null, "Light showers", null],
    [81, "rainy", null, "Showers", null],
    [82, "pouring", null, "Violent showers", null],
    [85, "snowy", null, "Light snow showers", null],
    [86, "snowy", null, "Heavy snow showers", null],
    [95, "lightning-rainy", null, "Thunderstorm", null],
    [96, "lightning-rainy", null, "Thunderstorm with hail", null],
    [99, "lightning-rainy", null, "Thunderstorm with heavy hail", null]
];
const SNOW_CODES = [71, 73, 75, 77, 85, 86];
const FOG_CODES = [45, 48];

// European AQI bands: [lowest index, word, tone]. The top band starts above
// 100, so 100 itself is Very poor.
const AQI_BANDS = [
    [0, "Good", "cyan"],
    [20, "Fair", "green"],
    [40, "Moderate", "yellow"],
    [60, "Poor", "orange"],
    [80, "Very poor", "red"],
    [100.000001, "Extremely poor", "pink"]
];
const POLLUTANTS = [["pm2_5", "PM2.5"], ["pm10", "PM10"], ["no2", "NO₂"], ["o3", "O₃"], ["so2", "SO₂"]];
const POLLEN = ["alder", "birch", "grass", "mugwort", "olive", "ragweed"];

const LEVELS = { yellow: { rank: 1, tone: "yellow" }, amber: { rank: 2, tone: "orange" }, red: { rank: 3, tone: "red" } };

function copy(o, changes) {
    return Object.assign({}, o, changes);
}

function num(v) {
    return typeof v === "number" && isFinite(v) ? v : null;
}

function pick(a, b) {
    return a !== null && a !== undefined ? a : b;
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function local(t) {
    return new Date(t * 1000);
}

function clock(t) {
    const d = local(t);
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// The local calendar day of `t` as a day count, so that two days'
// difference is in days even across a clock change.
function dayNumber(t) {
    const d = local(t);
    return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

// "2026-11-22" for the local day `offset` days from `t`'s.
function dateKey(t, offset) {
    const d = local(t);
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate() + (offset || 0));
    return `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}`;
}

// The local midnight that starts a "2026-11-22" day, `offset` days on.
function dayStart(key, offset) {
    const p = key.split("-").map(Number);
    return new Date(p[0], p[1] - 1, p[2] + (offset || 0)).getTime() / 1000;
}

// A past or future time against now: "12:14" today, "yesterday 22:40",
// "tomorrow 06:00", "Mon 22:40" within six days, else "15 Nov 22:40".
function when(t, now) {
    const diff = dayNumber(t) - dayNumber(now);
    if (diff === 0)
        return clock(t);
    if (diff === -1)
        return `yesterday ${clock(t)}`;
    if (diff === 1)
        return `tomorrow ${clock(t)}`;
    if (Math.abs(diff) <= 6)
        return `${WEEKDAYS[local(t).getDay()]} ${clock(t)}`;
    const d = local(t);
    return `${pad(d.getDate())} ${MONTHS[d.getMonth()]} ${clock(t)}`;
}

// A length of time, each unit rounded down: "under a minute", "3 min",
// "2 h", "4 d".
function span(seconds) {
    const s = Math.max(0, seconds);
    if (s < 60)
        return "under a minute";
    if (s < 3600)
        return `${Math.floor(s / 60)} min`;
    if (s < 86400)
        return `${Math.floor(s / 3600)} h`;
    return `${Math.floor(s / 86400)} d`;
}

// "just now", "2 min ago", "3 h ago".
function ago(t, now) {
    const s = now - t;
    return s < 60 ? "just now" : `${span(s)} ago`;
}

// The radar's finer form: "just now", "10 min ago", "1 h 20 min ago", "2 h
// ago".
function radarAgo(seconds) {
    const s = Math.max(0, seconds);
    if (s < 60)
        return "just now";
    const m = Math.floor(s / 60);
    if (m < 60)
        return `${m} min ago`;
    return `${Math.floor(m / 60)} h${m % 60 ? ` ${m % 60} min` : ""} ago`;
}

// A temperature with a true minus sign: "7.4°", "−1.8°", "9°"; "–" for none.
function degrees(v, decimals) {
    if (num(v) === null)
        return DASH;
    let x = Number(v.toFixed(decimals));
    if (x === 0)
        x = 0;
    return (x < 0 ? MINUS : "") + Math.abs(x).toFixed(decimals) + "°";
}

// The eight-point compass word for a direction the wind comes from.
function compass(dir) {
    if (num(dir) === null)
        return "";
    return COMPASS[Math.round((((dir % 360) + 360) % 360) / 45) % 8];
}

function wmo(code) {
    return WMO.find(w => w[0] === code) || null;
}

// The art key for a WMO code: one of sunny, clear-night, partlycloudy,
// partlycloudy-night, cloudy, rainy, pouring, lightning-rainy, snowy,
// snowy-rainy, fog. `isDay` is Open-Meteo's is_day (1 or 0, or a boolean).
// null for a code not in Open-Meteo's list. No code means wind, so "windy"
// is never returned.
function artFor(code, isDay) {
    const w = wmo(code);
    if (!w)
        return null;
    return isDay === 0 || isDay === false ? pick(w[2], w[1]) : w[1];
}

// The words for a WMO code, "" for an unknown one.
function conditionFor(code, isDay) {
    const w = wmo(code);
    if (!w)
        return "";
    return isDay === 0 || isDay === false ? pick(w[4], w[3]) : w[3];
}

function isSnow(code) {
    return SNOW_CODES.indexOf(code) >= 0;
}

function isRain(code) {
    return (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
}

function source() {
    // last: the last good event; error: { at, reason } of an error since it;
    // errors: consecutive errors since it.
    return { last: null, error: null, errors: 0 };
}

// The state before the helper has said anything. Fields: helper "running" |
// "stopped" | "missing"; retryIn (s, as helperLost gave it); started (the
// first line's time); config null | { state, key }; broker null |
// "connected" | "lost"; sensor null | { temperature, humidity, battery, at,
// available }; forecast, air, warnings, radar: { last, error, errors }.
function initial() {
    return {
        helper: "running",
        retryIn: 0,
        started: null,
        config: null,
        broker: null,
        sensor: null,
        forecast: source(),
        air: source(),
        warnings: source(),
        radar: source()
    };
}

const SOURCES = ["forecast", "air", "warnings", "radar"];

// The state after one helper line, already parsed. Unknown events change
// nothing.
function apply(st, ev, now) {
    if (!ev || typeof ev !== "object" || typeof ev.event !== "string")
        return st;
    const s = copy(st, { started: st.started === null ? now : st.started });
    const name = ev.event;
    if (name === "config") {
        s.config = { state: String(ev.state), key: typeof ev.key === "string" ? ev.key : "" };
    } else if (name === "broker") {
        s.broker = ev.state === "connected" ? "connected" : "lost";
    } else if (name === "sensor") {
        s.sensor = {
            temperature: num(ev.temperature),
            humidity: num(ev.humidity),
            battery: num(ev.battery),
            at: pick(num(ev.at), now),
            available: ev.available !== false
        };
    } else if (SOURCES.indexOf(name) >= 0) {
        s[name] = { last: ev, error: null, errors: 0 };
    } else if (name.endsWith("_error") && SOURCES.indexOf(name.slice(0, -6)) >= 0) {
        const k = name.slice(0, -6);
        s[k] = { last: st[k].last, error: { at: pick(num(ev.at), now), reason: String(ev.reason || "") }, errors: st[k].errors + 1 };
    } else {
        return st;
    }
    return s;
}

// Whether a line shows the helper working, so its restart back-off resets.
// A settings error is not: the helper then waits, silent, until it is
// started again, so it is no sign of a working helper.
function healthy(ev) {
    if (!ev || typeof ev !== "object")
        return false;
    if (ev.event === "config")
        return ev.state === "ok";
    return ["broker", "sensor"].concat(SOURCES).concat(SOURCES.map(k => k + "_error")).indexOf(ev.event) >= 0;
}

// The shell's report on the helper process: "stopped" (exited, starting
// again in `retryInSeconds`), "missing" (not on PATH) or "back" (running
// again). The data stays; the broker's state is unknown until it says.
function helperLost(st, why, retryInSeconds) {
    if (why === "back")
        return copy(st, { helper: "running", retryIn: 0, broker: null });
    return copy(st, { helper: why === "missing" ? "missing" : "stopped", retryIn: Math.max(0, Math.round(retryInSeconds || 0)) });
}

// The one line replacing the panel, as { text, parts }; text "" for none.
// A settings error outranks "stopped": a helper started again reads the same
// settings and reports the same error.
function single(st) {
    let parts = null;
    if (st.helper === "missing")
        parts = [["The weather helper is not installed (", false], ["desk-weather", true], [" is not on PATH).", false]];
    else if (st.config && st.config.state === "missing")
        parts = [["Weather is not set up: there is no settings file.", false]];
    else if (st.config && st.config.state !== "ok")
        parts = st.config.key
            ? [["Weather is not set up: ", false], [st.config.key, true], [" in the settings file is missing or not valid.", false]]
            : [["Weather is not set up: the settings file is not valid.", false]];
    else if (st.helper === "stopped")
        parts = [[`The weather helper stopped. Starting it again in ${st.retryIn} s.`, false]];
    if (!parts)
        return { text: "", parts: [] };
    return { text: parts.map(p => p[0]).join(""), parts: parts.map(p => ({ text: p[0], code: p[1] })) };
}

// The sensor: "fresh", "unreachable" (broker lost), "never" (no reading),
// "offline" (Zigbee2MQTT says so) or "silent" (none for 30 min).
function sensorState(st, now) {
    const s = st.sensor;
    if (st.broker === "lost")
        return "unreachable";
    if (!s)
        return "never";
    if (!s.available)
        return "offline";
    return now - s.at < SENSOR_SILENT ? "fresh" : "silent";
}

// The forecast as far as it is still a forecast, or null: fewer than three
// hours starting after now means none. `hour` is the hourly entry holding
// now; `current` the current block while it is under an hour from now;
// `here` this hour's values, from current when it has them.
function model(st, now) {
    const f = st.forecast.last;
    if (!f || !Array.isArray(f.hourly))
        return null;
    const hourly = f.hourly.filter(h => h && num(h.time) !== null);
    if (hourly.filter(h => h.time > now).length < MIN_FUTURE_HOURS)
        return null;
    const hour = hourly.find(h => h.time <= now && now < h.time + 3600) || null;
    const c = f.current && num(f.current.time) !== null && Math.abs(now - f.current.time) < 3600 ? f.current : null;
    const field = k => pick(c ? num(c[k]) : null, hour ? num(hour[k]) : null);
    const here = {
        temperature: field("temperature"),
        humidity: c ? num(c.humidity) : null,
        code: c && num(c.code) !== null ? c.code : hour ? num(hour.code) : null,
        isDay: c && c.is_day !== null && c.is_day !== undefined ? c.is_day : hour ? hour.is_day : null,
        cloud: field("cloud"),
        precipitation: field("precipitation"),
        wind: c ? num(c.wind) : null,
        windDir: c ? num(c.wind_dir) : null
    };
    return { f, hourly, hour, current: c, here, daily: Array.isArray(f.daily) ? f.daily.filter(d => d && typeof d.date === "string") : [] };
}

function dailyFor(m, now, offset) {
    const key = dateKey(now, offset);
    return m.daily.find(d => d.date === key) || null;
}

function reasonWords(reason, who) {
    if (reason === "http")
        return `${who} answered with an error`;
    if (reason === "parse")
        return `could not read the answer from ${who}`;
    return `could not reach ${who}`;
}

// The next try after an error, as the helper times it.
function retryText(src) {
    if (!src.error)
        return "";
    const wait = Math.min(RETRY_FIRST * Math.pow(2, Math.max(0, src.errors - 1)), RETRY_MAX);
    return wait === RETRY_FIRST ? "Retrying every minute." : `Retrying at ${clock(src.error.at + wait)}.`;
}

// The warnings not yet over, from the last good read (kept through errors,
// as each carries its own end).
function shownWarnings(st, now) {
    const w = st.warnings.last;
    if (!w || !Array.isArray(w.items))
        return [];
    return w.items.filter(i => i && LEVELS[i.level] && (num(i.to) === null || i.to > now));
}

function inForce(item, now) {
    return (num(item.from) === null || item.from <= now) && (num(item.to) === null || item.to > now);
}

function warnPoint(t, now, alone) {
    const diff = dayNumber(t) - dayNumber(now);
    if (diff === 0)
        return alone ? clock(t) : `${clock(t)} today`;
    const d = local(t);
    const day = Math.abs(diff) <= 6 ? WEEKDAYS[d.getDay()] : `${pad(d.getDate())} ${MONTHS[d.getMonth()]}`;
    return `${day} ${clock(t)}`;
}

// "06:00 to 23:59 today", "Mon 03:00 to Mon 15:00", "21:00 today to Tue
// 09:00"; the feed's own text when the times did not parse.
function warnWhen(item, now) {
    const from = num(item.from), to = num(item.to);
    if (from === null || to === null)
        return typeof item.when === "string" ? item.when : "";
    if (dayNumber(from) === dayNumber(now) && dayNumber(to) === dayNumber(now))
        return `${clock(from)} to ${clock(to)} today`;
    return `${warnPoint(from, now, false)} to ${warnPoint(to, now, false)}`;
}

function warningsView(st, now) {
    return shownWarnings(st, now).map(i => ({
        level: i.level,
        tone: LEVELS[i.level].tone,
        title: typeof i.title === "string" ? i.title : "",
        detail: [typeof i.areas === "string" ? i.areas : "", warnWhen(i, now), "Met Office"].filter(x => x !== "").join(" · "),
        link: typeof i.link === "string" && LINK.test(i.link) ? i.link : ""
    }));
}

// The most severe warning covering a local day, as a tone, or "". A warning
// with neither time known is placed on no day.
function dayMark(items, key) {
    const start = dayStart(key, 0), end = dayStart(key, 1);
    let best = null;
    for (const i of items) {
        const from = num(i.from), to = num(i.to);
        if (from === null && to === null)
            continue;
        if ((from === null || from < end) && (to === null || to > start) && (!best || LEVELS[i.level].rank > LEVELS[best.level].rank))
            best = i;
    }
    return best ? LEVELS[best.level].tone : "";
}

function hoursView(m, now) {
    const start = m.hourly.findIndex(h => h.time + 3600 > now);
    const list = m.hourly.slice(start, start + HOURS);
    const top = Math.max(2.5, ...list.map(h => num(h.precipitation) || 0));
    return list.map((h, i) => {
        const p = num(h.precipitation);
        const current = i === 0 && h.time <= now;
        return {
            now: current,
            label: current ? "now" : pad(local(h.time).getHours()),
            art: artFor(h.code, h.is_day),
            tempText: degrees(h.temperature, 0),
            temp: num(h.temperature),
            precip: p,
            precipText: p > 0 ? p.toFixed(1) : "",
            precipFrac: p > 0 ? p / top : 0
        };
    });
}

// The strip's unit line: precipitation is always water, snow included.
function precipWords(list) {
    const wet = list.filter(h => num(h.precipitation) > 0);
    const snowy = wet.filter(h => num(h.snowfall) > 0);
    if (snowy.length === 0)
        return "mm of rain below";
    return snowy.length === wet.length ? "mm of snow, as water, below" : "mm of rain and snow, as water, below";
}

function daysView(m, items, now) {
    const i0 = m.daily.findIndex(d => d.date === dateKey(now, 0));
    if (i0 < 0)
        return [];
    const list = m.daily.slice(i0, i0 + DAYS);
    const los = list.map(d => num(d.tmin)).filter(v => v !== null);
    const his = list.map(d => num(d.tmax)).filter(v => v !== null);
    const lo = los.length ? Math.min(...los) : 0;
    const width = (his.length ? Math.max(...his) : 0) - lo || 1;
    return list.map((d, i) => {
        const p = num(d.precipitation);
        const tmin = num(d.tmin), tmax = num(d.tmax);
        const bar = tmin !== null && tmax !== null;
        return {
            label: i === 0 ? "Today" : WEEKDAYS[new Date(dayStart(d.date, 0) * 1000).getDay()],
            today: i === 0,
            art: artFor(d.code, 1),
            precip: p,
            precipText: p > 0 ? `${p.toFixed(1)} mm` : DASH,
            dry: !(p > 0),
            loText: degrees(tmin, 0),
            hiText: degrees(tmax, 0),
            start: bar ? (tmin - lo) / width : null,
            end: bar ? (tmax - lo) / width : null,
            mark: dayMark(items, d.date)
        };
    });
}

// A concentration: one decimal under 10, whole from 10; "–" for none.
function conc(v) {
    if (num(v) === null)
        return DASH;
    return v < 10 ? v.toFixed(1) : String(Math.round(v));
}

function band(v) {
    let b = 0;
    for (let i = 0; i < AQI_BANDS.length; i++)
        if (v >= AQI_BANDS[i][0])
            b = i;
    return b;
}

function airView(st, now) {
    const a = st.air;
    const out = { shown: false, head: "European index · CAMS model", value: "", word: "", tone: "normal", bands: [], marker: 0, parts: [], unit: "µg/m³", highest: "", pollen: "", text: "", message: "", messageTone: "normal" };
    if (a.error) {
        out.message = `No air quality figures: ${reasonWords(a.error.reason, "the service")}.` + (a.last ? ` Last read ${when(a.last.fetched, now)}.` : "");
        out.messageTone = "orange";
        return out;
    }
    if (!a.last) {
        out.message = "No air quality figures yet.";
        out.messageTone = "dim";
        return out;
    }
    const ev = a.last;
    const v = num(ev.aqi);
    if (v === null) {
        out.message = "No air quality index in the last reading.";
        out.messageTone = "orange";
        return out;
    }
    const b = band(v);
    const sub = ev.sub && typeof ev.sub === "object" ? ev.sub : {};
    let top = null;
    for (const p of POLLUTANTS)
        if (num(sub[p[0]]) !== null && (top === null || sub[p[0]] > sub[top[0]]))
            top = p;
    const shownKeys = ["pm2_5", "pm10", "no2", "o3"].concat(top && top[0] === "so2" ? ["so2"] : []);
    out.shown = true;
    out.value = String(Math.round(v));
    out.word = AQI_BANDS[b][1];
    out.tone = AQI_BANDS[b][2];
    out.bands = AQI_BANDS.map((x, i) => ({ tone: x[2], on: i === b }));
    out.marker = Math.min(Math.max(v, 0), 120) / 120;
    out.parts = POLLUTANTS.filter(p => shownKeys.indexOf(p[0]) >= 0).map(p => ({ label: p[1], value: conc(ev[p[0]]) }));
    out.highest = top ? top[1] : "";
    const pollen = ev.pollen && typeof ev.pollen === "object" ? ev.pollen : {};
    const kinds = POLLEN.filter(k => num(pollen[k]) > 0).sort((x, y) => pollen[y] - pollen[x]);
    out.pollen = kinds.length ? kinds.map(k => `${k} pollen ${conc(pollen[k])}`).join(", ") + " grains/m³" : "";
    out.text = out.parts.map(p => `${p.label} ${p.value}`).join(" · ") + ` ${out.unit}` + (out.highest ? ` · highest: ${out.highest}` : "") + (out.pollen ? ` · ${out.pollen}` : "");
    return out;
}

function sceneView(m, now) {
    const blank = { blank: true, day: false, frac: 0, edge: false, cloud: 0, rain: 0, snow: false, fog: false, lit: false };
    if (!m)
        return blank;
    const today = dailyFor(m, now, 0);
    const sr = today ? num(today.sunrise) : null, ss = today ? num(today.sunset) : null;
    let day, frac;
    if (sr !== null && ss !== null) {
        if (now >= sr && now <= ss) {
            day = true;
            frac = (now - sr) / (ss - sr);
        } else if (now < sr) {
            // Before sunrise: along the night from yesterday's sunset, or
            // today's a day back when the forecast does not reach yesterday.
            const y = dailyFor(m, now, -1);
            const from = pick(y ? num(y.sunset) : null, ss - 86400);
            day = false;
            frac = (now - from) / (sr - from);
        } else {
            const t = dailyFor(m, now, 1);
            const to = pick(t ? num(t.sunrise) : null, sr + 86400);
            day = false;
            frac = (now - ss) / (to - ss);
        }
    } else {
        day = m.here.isDay === 1 || m.here.isDay === true;
        frac = 0.5;
    }
    frac = Math.min(1, Math.max(0, frac));
    const code = m.here.code;
    const p = pick(m.here.precipitation, 0);
    const snow = isSnow(code);
    const raining = isRain(code) || (p > 0 && !snow);
    const edge = day && (frac < 0.12 || frac > 0.88);
    return {
        blank: false,
        day,
        frac,
        edge,
        cloud: m.here.cloud === null ? 0 : Math.min(1, Math.max(0, m.here.cloud / 100)),
        rain: raining ? Math.min(3, Math.max(0.5, 0.6 + p)) : 0,
        snow,
        fog: FOG_CODES.indexOf(code) >= 0,
        lit: !day || edge
    };
}

function stat(label, value, unit, tone) {
    return value === null ? { label, value: DASH, unit: "", tone: "dim" } : { label, value, unit, tone: tone || "normal" };
}

function statsView(st, m, now, fresh) {
    const s = st.sensor;
    const humidity = fresh ? s.humidity : m ? m.here.humidity : null;
    const out = [stat("HUMIDITY", humidity === null ? null : String(Math.round(humidity)), "%")];
    const wind = m ? m.here.wind : null;
    out.push(stat("WIND", wind === null ? null : String(Math.round(wind)), ["km/h", compass(m && m.here.windDir)].filter(x => x).join(" "), wind >= WIND_STRONG ? "orange" : "normal"));
    const today = m ? dailyFor(m, now, 0) : null;
    const p = today ? num(today.precipitation) : null;
    out.push(stat(today && isSnow(today.code) ? "SNOW TODAY" : "RAIN TODAY", p === null ? null : p === 0 ? "0" : p.toFixed(1), "mm"));
    let next = null;
    if (m)
        for (const d of m.daily)
            for (const k of ["sunrise", "sunset"])
                if (num(d[k]) !== null && d[k] > now && (!next || d[k] < next.t))
                    next = { t: d[k], label: k.toUpperCase() };
    out.push(next ? stat(next.label, clock(next.t), "") : stat("SUNSET", null));
    return out;
}

// The parts of the source line: [{ text, warn }].
function sensorPart(st, now, forecastFailed) {
    const s = st.sensor;
    switch (sensorState(st, now)) {
    case "fresh":
        return { text: `sensor ${ago(s.at, now)}`, warn: false };
    case "unreachable":
        return { text: "sensor: message broker not reachable" + (forecastFailed ? "" : ", retrying"), warn: true };
    case "never":
        return { text: "sensor: no reading yet", warn: true };
    case "offline":
        return { text: `sensor offline, last heard ${when(s.at, now)}`, warn: true };
    }
    return { text: `sensor last heard ${when(s.at, now)}`, warn: true };
}

function warningsPart(st, now) {
    const w = st.warnings;
    if (w.error)
        return { text: `warnings not checked${w.last ? ` since ${when(w.last.fetched, now)}` : ""}: ${reasonWords(w.error.reason, "the Met Office")}`, warn: true };
    if (!w.last)
        return null;
    const n = shownWarnings(st, now).length;
    return { text: `${n === 0 ? "no warnings" : n === 1 ? "1 warning" : `${n} warnings`}, Met Office ${when(w.last.fetched, now)}`, warn: false };
}

function join(parts) {
    const p = parts.filter(x => x);
    return { text: p.map(x => x.text).join(" · "), tone: p.some(x => x.warn) ? "orange" : "normal" };
}

function forecastSource(st, m, now) {
    const f = st.forecast;
    const firstStart = !f.last && !f.error;
    const parts = [];
    if (m) {
        const age = now - f.last.fetched;
        if (age > FORECAST_OLD) {
            parts.push({ text: `forecast from ${when(f.last.fetched, now)}, ${span(age)} old`, warn: true });
            if (f.error)
                parts.push({ text: "last fetch failed, retrying", warn: true });
        } else {
            parts.push({ text: `Open-Meteo ${when(f.last.fetched, now)}`, warn: false });
        }
    } else if (f.error) {
        parts.push({ text: `forecast: ${reasonWords(f.error.reason, "the service")}`, warn: true });
    } else if (f.last) {
        parts.push({ text: `forecast from ${when(f.last.fetched, now)} has run out`, warn: true });
    }
    if (firstStart && sensorState(st, now) === "never")
        return { text: st.started === null ? "" : `started ${clock(st.started)}`, tone: "normal" };
    return join([sensorPart(st, now, !m && !!f.error)].concat(parts, [warningsPart(st, now)]));
}

function heroView(st, m, now, state) {
    const s = st.sensor;
    const fresh = state === "fresh";
    const sensorTemp = fresh ? s.temperature : null;
    const temp = pick(sensorTemp, m ? m.here.temperature : null);
    const out = {
        big: temp === null ? DASH : degrees(temp, 1),
        bigTone: temp === null ? "dim" : "normal",
        age: "",
        ageTone: "soft",
        condition: m ? conditionFor(m.here.code, m.here.isDay) : "",
        range: ""
    };
    if (m) {
        const d = dailyFor(m, now, 0);
        if (d && num(d.tmin) !== null && num(d.tmax) !== null)
            out.range = `today ${degrees(d.tmin, 0)} to ${degrees(d.tmax, 0)}`;
    }
    if (sensorTemp !== null) {
        out.age = `outdoor sensor · ${ago(s.at, now)}`;
        if (s.battery !== null && s.battery <= BATTERY_LOW) {
            out.age += ` · battery ${Math.round(s.battery)} %`;
            out.ageTone = "yellow";
        }
        return out;
    }
    const why = state === "unreachable" ? "sensor not reachable"
        : state === "never" ? "sensor not heard yet"
        : state === "offline" ? "sensor offline"
        : state === "silent" ? `sensor silent for ${span(now - s.at)}`
        : "sensor sent no temperature";
    const f = st.forecast;
    if (m) {
        out.age = `forecast model · ${why}`;
        out.ageTone = "orange";
    } else if (!f.last && !f.error) {
        out.age = state === "never" ? "waiting for the sensor" : why;
        out.ageTone = state === "never" ? "dim" : "orange";
    } else {
        out.age = "no sensor reading, no forecast";
        out.ageTone = "orange";
    }
    return out;
}

function messageView(st, now, fresh) {
    const f = st.forecast;
    if (!f.last && !f.error)
        return "Fetching the first forecast.";
    const retry = retryText(f);
    if (!fresh) {
        const s = st.sensor;
        const said = s ? `The sensor was last heard ${when(s.at, now)}` : "The sensor has not been heard";
        return [`Nothing to show. ${said} and ${f.last ? "the last forecast has run out" : "no forecast has arrived"}.`, retry].filter(x => x).join(" ");
    }
    if (f.last)
        return [`No forecast. The last one is from ${when(f.last.fetched, now)} and has run out.`, retry].filter(x => x).join(" ");
    return ["No forecast has arrived yet.", retry].filter(x => x).join(" ");
}

// Everything the forecast page draws; the fields are in the header comment.
function view(st, now) {
    const one = single(st);
    const out = { single: one.text, singleParts: one.parts, hero: null, scene: null, stats: null, warnings: null, body: null, message: null, hoursHead: null, precipHead: null, hours: null, days: null, air: null, source: null, sourceTone: null };
    if (one.text)
        return out;
    const m = model(st, now);
    const state = sensorState(st, now);
    const fresh = state === "fresh" && st.sensor.temperature !== null;
    out.hero = heroView(st, m, now, state);
    out.scene = sceneView(m, now);
    out.stats = statsView(st, m, now, state === "fresh");
    out.warnings = warningsView(st, now);
    const src = forecastSource(st, m, now);
    out.source = src.text;
    out.sourceTone = src.tone;
    if (!m) {
        out.body = "message";
        out.message = messageView(st, now, fresh);
        return out;
    }
    out.body = "forecast";
    out.message = "";
    out.hoursHead = "NEXT HOURS";
    out.hours = hoursView(m, now);
    const start = m.hourly.findIndex(h => h.time + 3600 > now);
    out.precipHead = precipWords(m.hourly.slice(start, start + HOURS));
    out.days = daysView(m, shownWarnings(st, now), now);
    out.air = airView(st, now);
    return out;
}

// The radar's frames, oldest first, as the last good radar event lists them.
function radarFrames(st) {
    const r = st.radar.last;
    if (!r || !Array.isArray(r.frames))
        return [];
    return r.frames.filter(f => f && num(f.time) !== null && typeof f.dir === "string");
}

// Whether any frame is under two hours old.
function radarReady(st, now) {
    const fr = radarFrames(st);
    return fr.length > 0 && now - fr[fr.length - 1].time < RADAR_GONE;
}

// The index of the frame at `time` (null = the newest); a frame dropped
// since gives the next newer one.
function frameIndex(frames, time) {
    if (time === null || time === undefined)
        return frames.length - 1;
    const i = frames.findIndex(f => f.time >= time);
    return i < 0 ? frames.length - 1 : i;
}

// Everything the radar page draws; the fields are in the header comment.
function radarView(st, now, frame, playing) {
    const r = st.radar;
    const sensor = sensorPart(st, now, false);
    const frames = radarFrames(st);
    const out = { state: "frames", head: "", note: "", frames: [], index: -1, frameDir: "", label: "", labelTone: "normal", ticks: [], left: "", right: "", timeline: false, block: null, playing: false, source: "", sourceTone: "normal" };
    if (r.last)
        out.block = { zoom: r.last.zoom, tile: r.last.tile, x0: r.last.x0, y0: r.last.y0, cols: r.last.cols, rows: r.last.rows, centre: r.last.centre };
    if (!radarReady(st, now)) {
        const loading = !r.last && !r.error;
        out.state = loading ? "loading" : "unavailable";
        out.note = loading ? "Fetching the radar…" : "Radar not available.";
        const radar = r.error ? { text: `radar: ${reasonWords(r.error.reason, "RainViewer")}`, warn: true }
            : loading ? { text: "radar: RainViewer", warn: false }
            : { text: "radar: no frame in the last 2 hours", warn: true };
        const j = join([sensor, radar]);
        out.source = j.text;
        out.sourceTone = j.tone;
        return out;
    }
    const last = frames.length - 1;
    const i = frameIndex(frames, frame);
    const newest = frames[last].time;
    const behind = now - newest > RADAR_BEHIND;
    const shown = frames[i];
    out.head = "past 2 hours, not a forecast";
    out.frames = frames.map(f => ({ time: f.time, dir: f.dir }));
    out.index = i;
    out.frameDir = shown.dir;
    out.label = `${clock(shown.time)} · ${radarAgo(now - shown.time)}` + (behind && i === last ? ", radar is behind" : "");
    out.labelTone = behind ? "orange" : "normal";
    out.note = shown.dry === true ? "No rain on the radar." : "";
    out.ticks = frames.map((f, k) => k < i ? "past" : k === i ? "on" : "after");
    out.left = clock(frames[0].time);
    out.right = clock(newest);
    out.timeline = true;
    out.playing = !!playing;
    const j = behind
        ? join([sensor, { text: `radar: RainViewer, no new frame since ${clock(newest)}`, warn: true }])
        : join([sensor, { text: "radar: RainViewer", warn: false }, { text: "outline: Natural Earth", warn: false }]);
    out.source = j.text;
    out.sourceTone = j.tone;
    return out;
}

// The bar item; the fields are in the header comment.
function barView(st, now) {
    let worst = null;
    for (const i of shownWarnings(st, now))
        if (inForce(i, now) && (!worst || LEVELS[i.level].rank > LEVELS[worst].rank))
            worst = i.level;
    const warning = { warning: worst, warningTone: worst ? LEVELS[worst].tone : "" };
    if (single(st).text)
        return { art: null, text: DASH + "°", dim: true, warning: null, warningTone: "" };
    const m = model(st, now);
    const fresh = sensorState(st, now) === "fresh" && st.sensor.temperature !== null;
    const temp = fresh ? st.sensor.temperature : m ? m.here.temperature : null;
    return Object.assign({
        art: m ? artFor(m.here.code, m.here.isDay) : null,
        text: degrees(temp, 0),
        dim: !fresh
    }, warning, temp === null ? { text: DASH + "°" } : {});
}

function effect(kind, url) {
    return { kind, url: url || "" };
}

// The ui of a panel just opened: the forecast page.
function initialUi(now) {
    return { now: now, page: "forecast", frame: null, playing: false, frameAt: null, warning: 0, footer: null };
}

function linked(st, now) {
    return warningsView(st, now).filter(w => w.link);
}

// The key table for the ui and state as they are: [{ keys, hint, run }], in
// footer order. Only what is listed is handled and hinted.
function table(ui, st) {
    const esc = { keys: ["Esc"], hint: ["Esc", "close"], run: u => ({ ui: u, effect: effect("close") }) };
    if (single(st).text)
        return [esc];
    if (ui.page === "radar") {
        const toForecast = { keys: ["M"], hint: ["M", "forecast"], run: u => ({ ui: copy(u, { page: "forecast", playing: false, frameAt: null }), effect: effect("radarOff") }) };
        if (!radarReady(st, ui.now))
            return [toForecast, esc];
        const frames = radarFrames(st);
        return [
            { keys: ["Space"], hint: ["Space", ui.playing ? "pause" : "play"], run: u => ({ ui: copy(u, { playing: !u.playing, frameAt: null }), effect: effect("none") }) },
            {
                keys: ["Left", "Right"],
                hint: ["← →", "frame"],
                run: (u, k) => {
                    const i = Math.max(0, Math.min(frames.length - 1, frameIndex(frames, u.frame) + (k === "Left" ? -1 : 1)));
                    return { ui: copy(u, { frame: frames[i].time, playing: false, frameAt: null }), effect: effect("none") };
                }
            },
            toForecast,
            esc
        ];
    }
    const t = [
        {
            keys: ["R"],
            hint: ["R", "refresh"],
            run: (u, k, s) => ({
                ui: copy(u, { footer: { fetched: s.forecast.last ? s.forecast.last.fetched : null, errorAt: s.forecast.error ? s.forecast.error.at : null, until: null, waitUntil: null } }),
                effect: effect("refresh")
            })
        },
        { keys: ["M"], hint: ["M", "radar"], run: u => ({ ui: copy(u, { page: "radar", frame: null, playing: false, frameAt: null }), effect: effect("radarOn") }) }
    ];
    const links = linked(st, ui.now);
    if (links.length)
        t.push({
            keys: ["W"],
            hint: ["W", "warning page"],
            run: u => {
                const i = u.warning % links.length;
                return { ui: copy(u, { warning: i + 1 }), effect: effect("openLink", links[i].link) };
            }
        });
    t.push(esc);
    return t;
}

// A key pressed in the open panel: one of KEY_NAMES. A held key's
// auto-repeat acts only for ← and →. Returns { ui, effect }.
function key(ui, st, name, isAutoRepeat) {
    const entry = table(ui, st).find(e => e.keys.indexOf(name) >= 0);
    if (!entry || (isAutoRepeat && MOVING_KEYS.indexOf(name) < 0))
        return { ui, effect: effect("none") };
    return entry.run(ui, name, st);
}

// The line after R: { text, tone, done } (done: the fetch has answered).
function footerLine(ui, st) {
    const f = ui.footer;
    if (!f)
        return null;
    const fc = st.forecast;
    // An error since R is the latest word: a good fetch clears the error.
    if (fc.error && fc.error.at !== f.errorAt) {
        const why = fc.error.reason === "http" ? "The forecast service answered with an error."
            : fc.error.reason === "parse" ? "Could not read the forecast service's answer."
            : "Could not reach the forecast service.";
        return { text: why + (fc.last ? ` Still showing ${clock(fc.last.fetched)}.` : ""), tone: "orange", done: true };
    }
    if (fc.last && fc.last.fetched !== f.fetched)
        return { text: "Forecast updated.", tone: "green", done: true };
    return { text: "Fetching the forecast…", tone: "dim", done: false };
}

// The clock moving on: the ui's `now`, the radar loop while it plays, and
// the footer line expiring (4 s after the fetch answered, or 60 s without
// an answer). Returns { ui }.
function tick(ui, st, now) {
    const u = copy(ui, { now });
    const line = footerLine(u, st);
    if (line) {
        const f = u.footer;
        if (line.done)
            u.footer = f.until === null ? copy(f, { until: now + FOOTER_SHOW }) : now >= f.until ? null : f;
        else
            u.footer = f.waitUntil === null ? copy(f, { waitUntil: now + FOOTER_WAIT }) : now >= f.waitUntil ? null : f;
    }
    if (u.page === "radar" && u.playing) {
        if (!radarReady(st, now)) {
            u.playing = false;
        } else {
            const frames = radarFrames(st);
            const i = frameIndex(frames, u.frame);
            const last = frames.length - 1;
            if (u.frameAt === null) {
                u.frameAt = now;
            } else if (now - u.frameAt >= (i === last ? FRAME_HOLD : FRAME_STEP)) {
                u.frame = frames[i === last ? 0 : i + 1].time;
                u.frameAt = now;
            }
        }
    }
    return { ui: u };
}

// The footer: the keys key() handles now, or the line after R in their
// place.
function hints(ui, st) {
    const line = single(st).text ? null : footerLine(ui, st);
    return {
        keys: table(ui, st).map(e => e.hint),
        message: line ? line.text : "",
        tone: line ? line.tone : "normal"
    };
}

if (typeof module !== "undefined")
    module.exports = {
        SENSOR_SILENT, BATTERY_LOW, FORECAST_OLD, MIN_FUTURE_HOURS, WIND_STRONG, RADAR_BEHIND, RADAR_GONE, KEY_NAMES, WMO,
        initial, apply, healthy, helperLost, view, radarView, barView, initialUi, key, tick, hints, artFor, conditionFor,
        degrees, compass, span, ago, radarAgo, when
    };
