// The weather panel's library (quickshell/weather/weather.js) against
// invented desk-weather lines, hand-written in the helper's format in
// fixtures/ (a "@-N" or "@+N" in a time is N seconds before or after the
// base time the test applies the file at) and built here.
// Run under TZ=Europe/London: the times are that zone's, with the clock
// change of 25 Oct 2026 inside the clock-change cases.
// Run: node test-weather-panel.js <path to weather.js>
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

assert.equal(new Date("2026-01-15T12:00:00Z").getTimezoneOffset(), 0, "January is at UTC: run with TZ=Europe/London");
assert.equal(new Date("2026-07-15T12:00:00Z").getTimezoneOffset(), -60, "July is an hour ahead of UTC: run with TZ=Europe/London");

const W = require(path.resolve(process.argv[2]));
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

// Sun 22 Nov 2026 15:20 GMT; 02:06 the same night; Sun 25 Oct 2026 00:30
// BST, half an hour before the clocks go back.
const NOW = 1795360800;
const NIGHT = 1795313160;
const CC = 1792884600;
const M = "−";
const D = "–";

// A fixture's events, times resolved against `base`.
function events(name, base) {
    const text = fs.readFileSync(path.join(__dirname, "fixtures", name + ".jsonl"), "utf8");
    return text.split("\n").filter(l => l.trim() !== "").map(l => JSON.parse(l.replace(/"@([+-]\d+)"/g, (m, s) => String(base + Number(s)))));
}
// The state after fixtures' lines, each applied at `base`.
function load(names, base, st) {
    let s = st || W.initial();
    for (const name of [].concat(names))
        for (const ev of events(name, base))
            s = W.apply(s, ev, base);
    return s;
}
const feed = (st, list, now) => list.reduce((s, ev) => W.apply(s, ev, now), st);
const rain = () => load("01-rain-dusk", NOW);
const forecastOf = (name, base) => events(name, base).find(e => e.event === "forecast");
const keys = (ui, st, list) => list.reduce((r, k) => W.key(r.ui, st, k, false), { ui, effect: { kind: "none", url: "" } });

t("art and words for every Open-Meteo code, day and night", () => {
    const expected = {
        0: ["sunny", "clear-night", "Sunny", "Clear"], 1: ["sunny", "clear-night", "Mainly clear", "Mainly clear"],
        2: ["partlycloudy", "partlycloudy-night", "Partly cloudy", "Partly cloudy"], 3: ["cloudy", "cloudy", "Overcast", "Overcast"],
        45: ["fog", "fog", "Fog"], 48: ["fog", "fog", "Freezing fog"],
        51: ["rainy", "rainy", "Light drizzle"], 53: ["rainy", "rainy", "Drizzle"], 55: ["rainy", "rainy", "Heavy drizzle"],
        56: ["snowy-rainy", "snowy-rainy", "Light freezing drizzle"], 57: ["snowy-rainy", "snowy-rainy", "Heavy freezing drizzle"],
        61: ["rainy", "rainy", "Light rain"], 63: ["rainy", "rainy", "Rain"], 65: ["pouring", "pouring", "Heavy rain"],
        66: ["snowy-rainy", "snowy-rainy", "Light freezing rain"], 67: ["snowy-rainy", "snowy-rainy", "Heavy freezing rain"],
        71: ["snowy", "snowy", "Light snow"], 73: ["snowy", "snowy", "Snow"], 75: ["snowy", "snowy", "Heavy snow"], 77: ["snowy", "snowy", "Snow grains"],
        80: ["rainy", "rainy", "Light showers"], 81: ["rainy", "rainy", "Showers"], 82: ["pouring", "pouring", "Violent showers"],
        85: ["snowy", "snowy", "Light snow showers"], 86: ["snowy", "snowy", "Heavy snow showers"],
        95: ["lightning-rainy", "lightning-rainy", "Thunderstorm"], 96: ["lightning-rainy", "lightning-rainy", "Thunderstorm with hail"],
        99: ["lightning-rainy", "lightning-rainy", "Thunderstorm with heavy hail"]
    };
    assert.deepEqual(Object.keys(expected).map(Number), W.WMO.map(w => w[0]));
    for (const [code, e] of Object.entries(expected)) {
        const c = Number(code);
        assert.equal(W.artFor(c, 1), e[0], `day art ${c}`);
        assert.equal(W.artFor(c, true), e[0]);
        assert.equal(W.artFor(c, 0), e[1], `night art ${c}`);
        assert.equal(W.artFor(c, false), e[1]);
        assert.equal(W.conditionFor(c, 1), e[2]);
        assert.equal(W.conditionFor(c, 0), e[3] || e[2]);
    }
    assert.equal(W.artFor(97, 1), null);
    assert.equal(W.artFor(null, 1), null);
    assert.equal(W.conditionFor(4, 1), "");
    assert.ok(!W.WMO.some(w => w[1] === "windy" || w[2] === "windy"), "no code means wind");
});

t("numbers: true minus, rounding to zero, compass, ages", () => {
    assert.equal(W.degrees(-1.8, 1), `${M}1.8°`);
    assert.equal(W.degrees(-0.04, 1), "0.0°");
    assert.equal(W.degrees(-0.4, 0), "0°");
    assert.equal(W.degrees(-2.6, 0), `${M}3°`);
    assert.equal(W.degrees(31.6, 1), "31.6°");
    assert.equal(W.degrees(null, 1), D);
    assert.deepEqual([0, 22, 23, 90, 225, 337, 338, 360, -45, null].map(W.compass), ["N", "N", "NE", "E", "SW", "NW", "N", "N", "NW", ""]);
    assert.deepEqual([59, 60, 3599, 3600, 86399, 86400].map(W.span), ["under a minute", "1 min", "59 min", "1 h", "23 h", "1 d"]);
    assert.equal(W.ago(NOW - 59, NOW), "just now");
    assert.equal(W.ago(NOW - 120, NOW), "2 min ago");
    assert.deepEqual([30, 600, 4800, 7200, 4260].map(W.radarAgo), ["just now", "10 min ago", "1 h 20 min ago", "2 h ago", "1 h 11 min ago"]);
    assert.equal(W.when(NOW - 1080, NOW), "15:02");
    assert.equal(W.when(NOW - 60000, NOW), "yesterday 22:40");
    assert.equal(W.when(NOW + 42000, NOW), "tomorrow 03:00");
    assert.equal(W.when(NOW - 3 * 86400, NOW), "Thu 15:20");
    assert.equal(W.when(NOW - 9 * 86400, NOW), "13 Nov 15:20");
});

t("rain at dusk: the reference state", () => {
    const v = W.view(rain(), NOW);
    assert.equal(v.single, "");
    assert.deepEqual(v.hero, { big: "7.4°", bigTone: "normal", age: "outdoor sensor · 2 min ago", ageTone: "soft", condition: "Light rain", range: "today 3° to 9°" });
    assert.deepEqual(v.stats, [
        { label: "HUMIDITY", value: "78", unit: "%", tone: "normal" },
        { label: "WIND", value: "19", unit: "km/h SW", tone: "normal" },
        { label: "RAIN TODAY", value: "6.2", unit: "mm", tone: "normal" },
        { label: "SUNSET", value: "16:06", unit: "", tone: "normal" }
    ]);
    assert.equal(v.source, "sensor 2 min ago · Open-Meteo 15:02 · no warnings, Met Office 15:10");
    assert.equal(v.sourceTone, "normal");
    assert.deepEqual(v.warnings, []);
    assert.equal(v.body, "forecast");
    assert.equal(v.message, "");
    // Sun 91 % along its day: low, at the edge; windows lit.
    assert.equal(v.scene.blank, false);
    assert.equal(v.scene.day, true);
    assert.ok(Math.abs(v.scene.frac - 28200 / 30960) < 1e-9);
    assert.equal(v.scene.edge, true);
    assert.equal(v.scene.lit, true);
    assert.equal(v.scene.cloud, 0.7);
    assert.equal(v.scene.rain, 1);
    assert.equal(v.scene.snow, false);
    assert.equal(v.scene.fog, false);
    assert.equal(v.hoursHead, "NEXT HOURS");
    assert.equal(v.precipHead, "mm of rain below");
});

t("the hours strip: 8 from the current hour, scaled to the wettest", () => {
    const h = W.view(rain(), NOW).hours;
    assert.equal(h.length, 8);
    assert.deepEqual(h.map(x => x.label), ["now", "16", "17", "18", "19", "20", "21", "22"]);
    assert.deepEqual(h.map(x => x.now), [true, false, false, false, false, false, false, false]);
    // A forecast whose first hour is still ahead has no current hour.
    const ahead = forecastOf("01-rain-dusk", NOW);
    ahead.hourly = ahead.hourly.slice(1);
    const ha = W.view(W.apply(rain(), ahead, NOW), NOW).hours;
    assert.equal(ha[0].now, false);
    assert.equal(ha[0].label, "16");
    assert.deepEqual(h.map(x => x.art), ["rainy", "rainy", "pouring", "rainy", "rainy", "rainy", "partlycloudy-night", "partlycloudy-night"]);
    assert.deepEqual(h.map(x => x.tempText), ["9°", "9°", "8°", "8°", "7°", "6°", "5°", "5°"]);
    assert.equal(h[1].temp, 8.6);
    assert.deepEqual(h.map(x => x.precipText), ["0.4", "1.3", "2.2", "1.6", "0.7", "0.2", "", ""]);
    // 2.2 mm is under the 2.5 mm floor of the scale.
    assert.equal(h[2].precipFrac, 2.2 / 2.5);
    assert.equal(h[6].precipFrac, 0);
    assert.equal(h[6].precip, 0);
    // An hour wetter than the floor sets the scale.
    const f = forecastOf("01-rain-dusk", NOW);
    f.hourly[3].precipitation = 5;
    const h2 = W.view(W.apply(rain(), f, NOW), NOW).hours;
    assert.equal(h2[3].precipFrac, 1);
    assert.equal(h2[0].precipFrac, 0.4 / 5);
    // At 16:00 the strip starts there; the past hour is gone.
    assert.equal(W.view(rain(), NOW + 2400).hours[0].label, "now");
    assert.equal(W.view(rain(), NOW + 2400).hours[1].label, "17");
});

t("the six days: labels, art, rain, the range bars", () => {
    const d = W.view(rain(), NOW).days;
    assert.equal(d.length, 6);
    assert.deepEqual(d.map(x => x.label), ["Today", "Mon", "Tue", "Wed", "Thu", "Fri"]);
    assert.equal(d[0].today, true);
    assert.equal(d[1].today, false);
    assert.deepEqual(d.map(x => x.art), ["rainy", "partlycloudy", "sunny", "cloudy", "pouring", "partlycloudy"]);
    assert.deepEqual(d.map(x => x.precipText), ["6.2 mm", "1.8 mm", D, D, "11.4 mm", "0.6 mm"]);
    assert.deepEqual(d.map(x => x.dry), [false, false, true, true, false, false]);
    assert.deepEqual(d.map(x => x.loText), ["3°", "2°", `${M}1°`, "1°", "5°", "4°"]);
    assert.deepEqual(d.map(x => x.hiText), ["9°", "8°", "6°", "7°", "11°", "10°"]);
    // Over −1 .. 11.
    assert.equal(d[2].start, 0);
    assert.equal(d[4].end, 1);
    assert.equal(d[0].start, 4 / 12);
    assert.equal(d[0].end, 10 / 12);
    assert.ok(d.every(x => x.mark === ""));
});

t("air quality: the row, its parts, the highest pollutant", () => {
    const a = W.view(rain(), NOW).air;
    assert.equal(a.shown, true);
    assert.equal(a.head, "European index · CAMS model");
    assert.equal(a.value, "28");
    assert.equal(a.word, "Fair");
    assert.equal(a.tone, "green");
    assert.deepEqual(a.bands.map(b => b.on), [false, true, false, false, false, false]);
    assert.deepEqual(a.bands.map(b => b.tone), ["cyan", "green", "yellow", "orange", "red", "pink"]);
    assert.equal(a.marker, 28 / 120);
    assert.deepEqual(a.parts, [{ label: "PM2.5", value: "6.7" }, { label: "PM10", value: "11" }, { label: "NO₂", value: "14" }, { label: "O₃", value: "52" }]);
    assert.equal(a.highest, "NO₂");
    assert.equal(a.pollen, "");
    assert.equal(a.text, "PM2.5 6.7 · PM10 11 · NO₂ 14 · O₃ 52 µg/m³ · highest: NO₂");
});

const airAt = (v, extra) => W.view(W.apply(rain(), Object.assign({ event: "air", fetched: NOW - 60, aqi: v, pm2_5: 1, pm10: 1, no2: 1, o3: 1, so2: 1, sub: { pm2_5: v }, pollen: {} }, extra || {}), NOW), NOW).air;

t("air quality: every band, on both sides of each boundary", () => {
    const words = [[0, "Good"], [19, "Good"], [20, "Fair"], [39, "Fair"], [40, "Moderate"], [59, "Moderate"], [60, "Poor"], [79, "Poor"], [80, "Very poor"], [100, "Very poor"], [101, "Extremely poor"], [134, "Extremely poor"]];
    for (const [v, w] of words)
        assert.equal(airAt(v).word, w, `index ${v}`);
    assert.equal(airAt(134).tone, "pink");
    assert.equal(airAt(88).tone, "red");
    assert.equal(airAt(134).marker, 1);
    assert.equal(airAt(120).marker, 1);
    assert.equal(airAt(60).marker, 0.5);
});

t("air quality: SO₂ joins when it sets the index; pollen only above zero", () => {
    const a = airAt(30, { so2: 61.2, sub: { pm2_5: 5, pm10: 4, no2: 10, o3: 9, so2: 30 }, pm2_5: null });
    assert.equal(a.highest, "SO₂");
    assert.deepEqual(a.parts.map(p => p.label), ["PM2.5", "PM10", "NO₂", "O₃", "SO₂"]);
    assert.equal(a.parts[0].value, D);
    assert.equal(a.parts[4].value, "61");
    const p = airAt(52, { pollen: { alder: 0, birch: 2.4, grass: 34.2, mugwort: null, olive: 0, ragweed: 0 } });
    assert.equal(p.pollen, "grass pollen 34, birch pollen 2.4 grains/m³");
    assert.match(p.text, / · grass pollen 34, birch pollen 2\.4 grains\/m³$/);
    assert.equal(airAt(52, { pollen: { alder: null, birch: null, grass: null, mugwort: null, olive: null, ragweed: null } }).pollen, "");
});

t("air quality not available, not yet read, no index", () => {
    let st = W.apply(rain(), { event: "air_error", at: NOW - 30, reason: "network" }, NOW);
    let a = W.view(st, NOW).air;
    assert.equal(a.shown, false);
    assert.equal(a.message, "No air quality figures: could not reach the service. Last read 14:55.");
    assert.equal(a.messageTone, "orange");
    // The forecast above it is unaffected.
    assert.equal(W.view(st, NOW).body, "forecast");
    st = load(["01-rain-dusk"], NOW);
    st = feed(W.initial(), events("01-rain-dusk", NOW).filter(e => e.event !== "air"), NOW);
    a = W.view(st, NOW).air;
    assert.deepEqual([a.shown, a.message, a.messageTone], [false, "No air quality figures yet.", "dim"]);
    a = W.view(W.apply(st, { event: "air_error", at: NOW, reason: "http" }, NOW), NOW).air;
    assert.equal(a.message, "No air quality figures: the service answered with an error.");
    assert.equal(airAt(null).message, "No air quality index in the last reading.");
});

t("snow at night: minus sign, sunrise next, snow as water", () => {
    const v = W.view(load("02-snow-night", NIGHT), NIGHT);
    assert.equal(v.hero.big, `${M}1.8°`);
    assert.equal(v.hero.condition, "Snow");
    assert.equal(v.hero.range, `today ${M}3° to 1°`);
    assert.equal(v.hero.age, "outdoor sensor · 1 min ago");
    assert.deepEqual(v.stats.map(s => [s.label, s.value, s.unit]), [["HUMIDITY", "94", "%"], ["WIND", "11", "km/h N"], ["SNOW TODAY", "3.3", "mm"], ["SUNRISE", "07:31", ""]]);
    assert.equal(v.precipHead, "mm of snow, as water, below");
    assert.equal(v.hours[0].art, "snowy");
    assert.equal(v.days[1].art, "snowy-rainy");
    assert.equal(v.days[2].art, "fog");
    // Night: from yesterday's sunset (today's a day back, as the forecast
    // starts today) to this morning's sunrise.
    assert.equal(v.scene.day, false);
    assert.ok(Math.abs(v.scene.frac - 36000 / 55500) < 1e-9);
    assert.equal(v.scene.edge, false);
    assert.equal(v.scene.lit, true);
    assert.equal(v.scene.snow, true);
    assert.equal(v.scene.rain, 0);
    // Mixed rain and snow in the strip.
    const f = forecastOf("02-snow-night", NIGHT);
    f.hourly[3].snowfall = 0;
    assert.equal(W.view(W.apply(load("02-snow-night", NIGHT), f, NIGHT), NIGHT).precipHead, "mm of rain and snow, as water, below");
});

t("scene: clear midday, fog, sun in the middle, after sunset", () => {
    const st = rain();
    const f = forecastOf("01-rain-dusk", NOW);
    const noon = NOW - 3 * 3600 - 1200;
    Object.assign(f.current, { code: 45, cloud: 30, precipitation: 0, time: noon - 600 });
    const v = W.view(W.apply(st, f, NOW), noon).scene;
    assert.equal(v.day, true);
    assert.ok(Math.abs(v.frac - (noon - (NOW - 28200)) / 30960) < 1e-9);
    assert.equal(v.edge, false);
    assert.equal(v.lit, false);
    assert.equal(v.fog, true);
    assert.equal(v.cloud, 0.3);
    // After sunset: along to tomorrow's sunrise.
    const late = W.view(st, NOW + 2760 + 3600).scene;
    assert.equal(late.day, false);
    assert.ok(Math.abs(late.frac - 3600 / (58200 - 2760)) < 1e-9);
    // No tomorrow in the forecast: today's sunrise a day on.
    const short = forecastOf("01-rain-dusk", NOW);
    short.daily = short.daily.slice(0, 1);
    const alone = W.view(W.apply(st, short, NOW), NOW + 2760 + 3600).scene;
    assert.ok(Math.abs(alone.frac - 3600 / (86400 - 28200 - 2760)) < 1e-9);
    // The edge's two sides: 12 % into the day.
    const edgeAt = q => W.view(st, NOW - 28200 + Math.round(q * 30960)).scene.edge;
    assert.equal(edgeAt(0.11), true);
    assert.equal(edgeAt(0.13), false);
    assert.equal(edgeAt(0.87), false);
    assert.equal(edgeAt(0.89), true);
});

const sensor = (extra, now) => Object.assign({ event: "sensor", temperature: 7.4, humidity: 78, battery: 55, at: (now || NOW) - 120, available: true }, extra);

t("sensor silent after 30 min: the model's figure, in orange", () => {
    const st = W.apply(rain(), sensor({ at: NOW - 1799 }), NOW);
    assert.equal(W.view(st, NOW).hero.big, "7.4°");
    assert.equal(W.view(st, NOW).hero.age, "outdoor sensor · 29 min ago");
    const silent = W.apply(rain(), sensor({ at: NOW - 1800 }), NOW);
    let v = W.view(silent, NOW);
    assert.equal(v.hero.big, "7.8°");
    assert.equal(v.hero.age, "forecast model · sensor silent for 30 min");
    assert.equal(v.hero.ageTone, "orange");
    v = W.view(W.apply(rain(), sensor({ at: NOW - 3 * 3600 - 360 }), NOW), NOW);
    assert.equal(v.hero.age, "forecast model · sensor silent for 3 h");
    assert.equal(v.stats[0].value, "67");
    assert.equal(v.source, "sensor last heard 12:14 · Open-Meteo 15:02 · no warnings, Met Office 15:10");
    assert.equal(v.sourceTone, "orange");
});

t("broker not reachable: same fallback, the cause in the source line", () => {
    const v = W.view(W.apply(rain(), { event: "broker", state: "lost" }, NOW), NOW);
    assert.equal(v.hero.big, "7.8°");
    assert.equal(v.hero.age, "forecast model · sensor not reachable");
    assert.equal(v.hero.ageTone, "orange");
    assert.equal(v.source, "sensor: message broker not reachable, retrying · Open-Meteo 15:02 · no warnings, Met Office 15:10");
    assert.equal(v.sourceTone, "orange");
    // Back: the last reading counts again.
    const back = W.apply(W.apply(rain(), { event: "broker", state: "lost" }, NOW), { event: "broker", state: "connected" }, NOW);
    assert.equal(W.view(back, NOW).hero.big, "7.4°");
});

t("sensor offline in Zigbee2MQTT, or never heard", () => {
    let v = W.view(W.apply(rain(), sensor({ available: false }), NOW), NOW);
    assert.equal(v.hero.age, "forecast model · sensor offline");
    assert.equal(v.source.split(" · ")[0], "sensor offline, last heard 15:18");
    const none = feed(W.initial(), events("01-rain-dusk", NOW).filter(e => e.event !== "sensor"), NOW);
    v = W.view(none, NOW);
    assert.equal(v.hero.age, "forecast model · sensor not heard yet");
    assert.equal(v.source.split(" · ")[0], "sensor: no reading yet");
    // A reading with no temperature: the model's.
    v = W.view(W.apply(rain(), sensor({ temperature: null }), NOW), NOW);
    assert.equal(v.hero.big, "7.8°");
    assert.equal(v.hero.age, "forecast model · sensor sent no temperature");
    assert.equal(v.stats[0].value, "78");
});

t("battery low at 15 % and below, in yellow", () => {
    let v = W.view(W.apply(rain(), sensor({ battery: 16 }), NOW), NOW);
    assert.equal(v.hero.age, "outdoor sensor · 2 min ago");
    assert.equal(v.hero.ageTone, "soft");
    v = W.view(W.apply(rain(), sensor({ battery: 15 }), NOW), NOW);
    assert.equal(v.hero.age, "outdoor sensor · 2 min ago · battery 15 %");
    v = W.view(W.apply(rain(), sensor({ battery: 9 }), NOW), NOW);
    assert.equal(v.hero.age, "outdoor sensor · 2 min ago · battery 9 %");
    assert.equal(v.hero.ageTone, "yellow");
    assert.equal(W.view(W.apply(rain(), sensor({ battery: null }), NOW), NOW).hero.ageTone, "soft");
});

t("wind orange from 40 km/h", () => {
    const at = w => {
        const f = forecastOf("01-rain-dusk", NOW);
        f.current.wind = w;
        return W.view(W.apply(rain(), f, NOW), NOW).stats[1];
    };
    assert.equal(at(39.9).tone, "normal");
    assert.equal(at(40).tone, "orange");
    assert.equal(at(46.2).value, "46");
    assert.equal(at(null).value, D);
    assert.equal(at(null).tone, "dim");
});

t("forecast old after 2 h: carries on, past hours dropped, orange source", () => {
    const st = load("03-forecast-old", NOW);
    const v = W.view(st, NOW);
    assert.equal(v.source, "sensor 2 min ago · forecast from 12:02, 3 h old · last fetch failed, retrying");
    assert.equal(v.sourceTone, "orange");
    assert.equal(v.body, "forecast");
    assert.equal(v.hours[0].label, "now");
    assert.equal(v.hours[0].tempText, "8°");
    assert.equal(v.hours[1].label, "16");
    // The current block is three hours old: this hour's entry speaks.
    assert.equal(v.hero.condition, "Light rain");
    assert.equal(v.stats[1].value, D);
    assert.equal(v.stats[0].value, "78");
    const at = age => {
        const f = forecastOf("01-rain-dusk", NOW);
        f.fetched = NOW - age;
        return W.view(W.apply(rain(), f, NOW), NOW);
    };
    assert.equal(at(7200).source.split(" · ")[1], "Open-Meteo 13:20");
    assert.equal(at(7200).sourceTone, "normal");
    assert.equal(at(7201).source.split(" · ")[1], "forecast from 13:19, 2 h old");
    assert.equal(at(7201).sourceTone, "orange");
});

t("forecast shown only with at least 3 future hours", () => {
    let v = W.view(load("04-no-forecast", NOW), NOW);
    assert.equal(v.body, "message");
    const f = forecastOf("04-no-forecast", NOW);
    f.hourly.push({ time: NOW + 9600, temperature: 7, code: 3, is_day: 0, precipitation: 0, snowfall: 0, cloud: 80 });
    v = W.view(W.apply(load("04-no-forecast", NOW), f, NOW), NOW);
    assert.equal(v.body, "forecast");
    assert.equal(v.hours.length, 4);
    // An hour starting exactly now is not a future one.
    const g = forecastOf("04-no-forecast", NOW);
    g.hourly.push({ time: NOW, temperature: 7, code: 3, is_day: 0, precipitation: 0, snowfall: 0, cloud: 80 });
    assert.equal(W.view(W.apply(load("04-no-forecast", NOW), g, NOW), NOW).body, "message");
});

t("no forecast, sensor fine: blank sky, dashes, the sensor's figures", () => {
    const v = W.view(load("04-no-forecast", NOW), NOW);
    assert.equal(v.message, "No forecast. The last one is from yesterday 21:02 and has run out. Retrying every minute.");
    assert.equal(v.scene.blank, true);
    assert.equal(v.scene.lit, false);
    assert.deepEqual(v.hero, { big: "7.4°", bigTone: "normal", age: "outdoor sensor · 2 min ago", ageTone: "soft", condition: "", range: "" });
    assert.deepEqual(v.stats.map(s => [s.value, s.tone]), [["78", "normal"], [D, "dim"], [D, "dim"], [D, "dim"]]);
    assert.equal(v.stats[3].label, "SUNSET");
    assert.equal(v.source, "sensor 2 min ago · forecast: could not reach the service");
    assert.equal(v.sourceTone, "orange");
    assert.equal(v.hours, null);
    assert.equal(v.days, null);
    assert.equal(v.air, null);
});

t("retry wording follows the helper's doubling", () => {
    let st = load("04-no-forecast", NOW);
    st = W.apply(st, { event: "forecast_error", at: NOW - 30, reason: "http" }, NOW);
    let v = W.view(st, NOW);
    assert.equal(v.message, "No forecast. The last one is from yesterday 21:02 and has run out. Retrying at 15:21.");
    assert.equal(v.source, "sensor 2 min ago · forecast: the service answered with an error");
    for (let i = 0; i < 6; i++)
        st = W.apply(st, { event: "forecast_error", at: NOW, reason: "parse" }, NOW);
    v = W.view(st, NOW);
    assert.equal(v.message.split(". ").pop(), "Retrying at 15:35.");
    assert.equal(v.source, "sensor 2 min ago · forecast: could not read the answer from the service");
    // Never a forecast.
    const fresh = feed(W.initial(), [{ event: "config", state: "ok" }, sensor({}), { event: "forecast_error", at: NOW, reason: "network" }], NOW);
    assert.equal(W.view(fresh, NOW).message, "No forecast has arrived yet. Retrying every minute.");
});

t("first start: waiting, blank, started at", () => {
    const v = W.view(load("06-first-start", NOW), NOW + 1);
    assert.equal(v.message, "Fetching the first forecast.");
    assert.deepEqual(v.hero, { big: D, bigTone: "dim", age: "waiting for the sensor", ageTone: "dim", condition: "", range: "" });
    assert.deepEqual(v.stats.map(s => s.value), [D, D, D, D]);
    assert.equal(v.scene.blank, true);
    assert.equal(v.source, "started 15:20");
    assert.equal(v.sourceTone, "normal");
    // The sensor first: its line, no forecast part yet.
    const s = W.apply(load("06-first-start", NOW), sensor({}), NOW);
    assert.equal(W.view(s, NOW).source, "sensor 2 min ago");
    assert.equal(W.view(s, NOW).message, "Fetching the first forecast.");
    assert.equal(W.view(W.initial(), NOW).source, "");
});

t("nothing at all", () => {
    const v = W.view(load("05-nothing", NOW), NOW);
    assert.equal(v.message, "Nothing to show. The sensor was last heard yesterday 22:40 and the last forecast has run out. Retrying every minute.");
    assert.equal(v.hero.age, "no sensor reading, no forecast");
    assert.equal(v.hero.ageTone, "orange");
    assert.equal(v.hero.big, D);
    assert.equal(v.source, "sensor: message broker not reachable · forecast: could not reach the service");
    assert.equal(v.sourceTone, "orange");
    const never = feed(W.initial(), [{ event: "config", state: "ok" }, { event: "forecast_error", at: NOW, reason: "network" }], NOW);
    assert.equal(W.view(never, NOW).message, "Nothing to show. The sensor has not been heard and no forecast has arrived. Retrying every minute.");
});

const warned = () => load(["01-rain-dusk", "07-warnings"], NOW);

t("warnings: strips most severe first, the expired one gone", () => {
    const v = W.view(warned(), NOW);
    assert.deepEqual(v.warnings.map(w => [w.level, w.tone, w.title]), [
        ["amber", "orange", "Amber warning of wind"],
        ["yellow", "yellow", "Yellow warning of rain"],
        ["yellow", "yellow", "Yellow warning of fog"]
    ]);
    assert.equal(v.warnings[0].detail, "Northshire, Eastshire · Mon 03:00 to Mon 15:00 · Met Office");
    assert.equal(v.warnings[1].detail, "06:00 to 23:59 today · Met Office");
    // Times that did not parse: the feed's own words.
    assert.equal(v.warnings[2].detail, "Westshire · 0400 Tue 24 Nov to 1100 Tue 24 Nov · Met Office");
    assert.equal(v.warnings[2].link, "");
    assert.equal(v.source, "sensor 2 min ago · Open-Meteo 15:02 · 3 warnings, Met Office 15:10");
    // The day rows: yellow today, amber Monday; the unplaced one marks none.
    assert.deepEqual(v.days.map(d => d.mark), ["yellow", "orange", "", "", "", ""]);
    // Across midnight from today.
    const st = W.apply(rain(), { event: "warnings", fetched: NOW, items: [{ level: "yellow", type: "wind", title: "Yellow warning of wind and rain", areas: "", from: NOW + 20400, to: NOW + 150000, when: "", link: "https://www.metoffice.gov.uk/x" }] }, NOW);
    const w = W.view(st, NOW);
    assert.equal(w.warnings[0].detail, "21:00 today to Tue 09:00 · Met Office");
    assert.deepEqual(w.days.map(d => d.mark), ["yellow", "yellow", "yellow", "", "", ""]);
    assert.equal(w.source.split(" · ").pop(), "1 warning, Met Office 15:20");
    // A warning ending exactly at a midnight does not mark the next day.
    const edge = W.apply(rain(), { event: "warnings", fetched: NOW, items: [{ level: "red", title: "Red", from: NOW - 3600, to: NOW + 31200, link: "" }] }, NOW);
    assert.deepEqual(W.view(edge, NOW).days.map(d => d.mark), ["red", "", "", "", "", ""]);
});

t("warnings feed not read: no strip, no 'no warnings', kept items stay", () => {
    let st = W.apply(rain(), { event: "warnings_error", at: NOW - 60, reason: "network" }, NOW);
    st = W.apply(st, { event: "warnings", fetched: NOW - 7800, items: [] }, NOW);
    st = W.apply(st, { event: "warnings_error", at: NOW - 60, reason: "network" }, NOW);
    let v = W.view(st, NOW);
    assert.deepEqual(v.warnings, []);
    assert.equal(v.source, "sensor 2 min ago · Open-Meteo 15:02 · warnings not checked since 13:10: could not reach the Met Office");
    assert.equal(v.sourceTone, "orange");
    const never = feed(W.initial(), events("01-rain-dusk", NOW).filter(e => e.event !== "warnings").concat([{ event: "warnings_error", at: NOW, reason: "http" }]), NOW);
    assert.equal(W.view(never, NOW).source.split(" · ").pop(), "warnings not checked: the Met Office answered with an error");
    // Not read at all yet: no part.
    assert.equal(W.view(feed(W.initial(), events("01-rain-dusk", NOW).filter(e => e.event !== "warnings"), NOW), NOW).source, "sensor 2 min ago · Open-Meteo 15:02");
    // An earlier read's warnings stay through an error until they end.
    v = W.view(W.apply(warned(), { event: "warnings_error", at: NOW, reason: "network" }, NOW), NOW);
    assert.equal(v.warnings.length, 3);
    assert.equal(W.view(W.apply(warned(), { event: "warnings_error", at: NOW, reason: "network" }, NOW), NOW + 86000).warnings.length, 1);
});

t("bar item: every state", () => {
    assert.deepEqual(W.barView(rain(), NOW), { art: "rainy", text: "7°", dim: false, warning: null, warningTone: "" });
    assert.deepEqual(W.barView(load("02-snow-night", NIGHT), NIGHT), { art: "snowy", text: `${M}2°`, dim: false, warning: null, warningTone: "" });
    // Yellow in force now; amber not until Monday.
    assert.deepEqual(W.barView(warned(), NOW), { art: "rainy", text: "7°", dim: false, warning: "yellow", warningTone: "yellow" });
    assert.equal(W.barView(warned(), NOW + 42000).warning, "amber");
    const red = W.apply(rain(), { event: "warnings", fetched: NOW, items: [{ level: "yellow", from: null, to: null, title: "", link: "" }, { level: "red", from: NOW - 1, to: NOW + 1, title: "", link: "" }] }, NOW);
    assert.equal(W.barView(red, NOW).warningTone, "red");
    assert.equal(W.barView(red, NOW + 1).warning, "yellow");
    // Sensor silent: the model's temperature, dimmed.
    assert.deepEqual(W.barView(W.apply(rain(), sensor({ at: NOW - 4000 }), NOW), NOW), { art: "rainy", text: "8°", dim: true, warning: null, warningTone: "" });
    // No forecast: the sensor's alone.
    assert.deepEqual(W.barView(load("04-no-forecast", NOW), NOW), { art: null, text: "7°", dim: false, warning: null, warningTone: "" });
    // Nothing, or an error.
    assert.deepEqual(W.barView(load("05-nothing", NOW), NOW), { art: null, text: `${D}°`, dim: true, warning: null, warningTone: "" });
    assert.deepEqual(W.barView(W.helperLost(warned(), "stopped", 8), NOW), { art: null, text: `${D}°`, dim: true, warning: null, warningTone: "" });
    assert.deepEqual(W.barView(load("10-config-invalid", NOW), NOW).text, `${D}°`);
    assert.equal(W.barView(W.initial(), NOW).text, `${D}°`);
});

t("errors: one plain line, the key named in mono", () => {
    let v = W.view(load("10-config-invalid", NOW), NOW);
    assert.equal(v.single, "Weather is not set up: latitude in the settings file is missing or not valid.");
    assert.deepEqual(v.singleParts, [{ text: "Weather is not set up: ", code: false }, { text: "latitude", code: true }, { text: " in the settings file is missing or not valid.", code: false }]);
    assert.equal(v.hero, null);
    assert.equal(W.view(load("11-config-missing", NOW), NOW).single, "Weather is not set up: there is no settings file.");
    assert.equal(W.view(W.apply(W.initial(), { event: "config", state: "invalid", key: null }, NOW), NOW).single, "Weather is not set up: the settings file is not valid.");
    v = W.view(W.helperLost(rain(), "stopped", 8), NOW);
    assert.equal(v.single, "The weather helper stopped. Starting it again in 8 s.");
    v = W.view(W.helperLost(rain(), "missing", 2), NOW);
    assert.equal(v.single, "The weather helper is not installed (desk-weather is not on PATH).");
    assert.deepEqual(v.singleParts.map(p => p.code), [false, true, false]);
    // Back: the data is still there; the broker is unknown until it says.
    const back = W.helperLost(W.helperLost(W.apply(rain(), { event: "broker", state: "lost" }, NOW), "stopped", 4), "back", 0);
    assert.equal(W.view(back, NOW).single, "");
    assert.equal(back.broker, null);
    assert.equal(W.view(back, NOW).hero.big, "7.4°");
    const st = load("10-config-invalid", NOW);
    assert.deepEqual(W.hints(W.initialUi(NOW), st), { keys: [["Esc", "close"]], message: "", tone: "normal" });
    // The helper exits after a settings error: the error stays the line.
    assert.equal(W.view(W.helperLost(st, "stopped", 4), NOW).single, "Weather is not set up: latitude in the settings file is missing or not valid.");
    assert.equal(W.view(W.helperLost(load("11-config-missing", NOW), "stopped", 4), NOW).single, "Weather is not set up: there is no settings file.");
    assert.equal(W.view(W.helperLost(st, "missing", 4), NOW).single, "The weather helper is not installed (desk-weather is not on PATH).");
});

t("healthy lines reset the back-off; settings errors and junk do not", () => {
    for (const e of ["broker", "sensor", "forecast", "air", "warnings", "radar", "forecast_error", "air_error", "warnings_error", "radar_error"])
        assert.equal(W.healthy({ event: e }), true, e);
    assert.equal(W.healthy({ event: "config", state: "ok" }), true);
    assert.equal(W.healthy({ event: "config", state: "invalid", key: "mqtt.host" }), false);
    assert.equal(W.healthy({ event: "config", state: "missing" }), false);
    assert.equal(W.healthy({ event: "rumour" }), false);
    assert.equal(W.healthy(null), false);
    assert.equal(W.healthy("text"), false);
});

t("events the panel does not know change nothing", () => {
    const st = rain();
    assert.equal(W.apply(st, { event: "rumour" }, NOW), st);
    assert.equal(W.apply(st, { event: "weather_error" }, NOW), st);
    assert.equal(W.apply(st, null, NOW), st);
    assert.equal(W.apply(st, { no: "event" }, NOW), st);
    // started is the first line's time and stays.
    assert.equal(W.apply(W.apply(W.initial(), { event: "config", state: "ok" }, NOW), { event: "broker", state: "connected" }, NOW + 50).started, NOW);
});

t("keys on the forecast page: hints, R, M, W, Esc", () => {
    const st = rain();
    const ui = W.initialUi(NOW);
    assert.deepEqual(W.hints(ui, st).keys, [["R", "refresh"], ["M", "radar"], ["Esc", "close"]]);
    assert.deepEqual(W.hints(ui, warned()).keys, [["R", "refresh"], ["M", "radar"], ["W", "warning page"], ["Esc", "close"]]);
    assert.equal(W.key(ui, st, "R", false).effect.kind, "refresh");
    assert.equal(W.key(ui, st, "Esc", false).effect.kind, "close");
    const m = W.key(ui, st, "M", false);
    assert.equal(m.effect.kind, "radarOn");
    assert.equal(m.ui.page, "radar");
    assert.equal(m.ui.frame, null);
    // Keys the page does not offer do nothing.
    for (const k of ["W", "Space", "Left", "Right", "Q"]) {
        const r = W.key(ui, st, k, false);
        assert.equal(r.effect.kind, "none", k);
        assert.equal(r.ui, ui);
    }
    // W: the first warning with a Met Office link, then the next, round again.
    const ws = warned();
    const r = keys(ui, ws, ["W"]);
    assert.deepEqual(r.effect, { kind: "openLink", url: "https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-warnings#?id=aaaa" });
    assert.equal(keys(ui, ws, ["W", "W"]).effect.url, "https://weather.metoffice.gov.uk/warnings#?id=bbbb");
    assert.equal(keys(ui, ws, ["W", "W", "W"]).effect.url, "https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-warnings#?id=aaaa");
    // Only warnings with a link count.
    const nolink = W.apply(rain(), { event: "warnings", fetched: NOW, items: [{ level: "yellow", from: null, to: null, title: "x", link: "https://www.metoffice.gov.uk.example.org/" }] }, NOW);
    assert.deepEqual(W.hints(ui, nolink).keys.map(k => k[0]), ["R", "M", "Esc"]);
});

t("held keys act once, except the arrows", () => {
    const st = load(["01-rain-dusk", "07-warnings", "08-radar"], NOW);
    const ui = W.initialUi(NOW);
    for (const k of ["R", "M", "W", "Esc"]) {
        const r = W.key(ui, st, k, true);
        assert.equal(r.effect.kind, "none", k);
        assert.equal(r.ui, ui, k);
    }
    const radar = W.key(ui, st, "M", false).ui;
    for (const k of ["Space", "M", "Esc"])
        assert.equal(W.key(radar, st, k, true).ui, radar, k);
    const left = W.key(radar, st, "Left", true);
    assert.equal(left.ui.frame, NOW - 1200);
    assert.equal(W.key(left.ui, st, "Right", true).ui.frame, NOW - 600);
    assert.deepEqual(W.KEY_NAMES, ["R", "M", "W", "Space", "Left", "Right", "Esc"]);
});

t("the line after R: fetching, updated, expiry", () => {
    const st = rain();
    let ui = W.key(W.initialUi(NOW), st, "R", false).ui;
    assert.deepEqual(W.hints(ui, st), { keys: [["R", "refresh"], ["M", "radar"], ["Esc", "close"]], message: "Fetching the forecast…", tone: "dim" });
    ui = W.tick(ui, st, NOW).ui;
    const f = forecastOf("01-rain-dusk", NOW);
    f.fetched = NOW + 60;
    const after = W.apply(st, f, NOW + 60);
    assert.deepEqual([W.hints(ui, after).message, W.hints(ui, after).tone], ["Forecast updated.", "green"]);
    ui = W.tick(ui, after, NOW + 61).ui;
    ui = W.tick(ui, after, NOW + 64.9).ui;
    assert.equal(W.hints(ui, after).message, "Forecast updated.");
    ui = W.tick(ui, after, NOW + 65).ui;
    assert.equal(ui.footer, null);
    assert.equal(W.hints(ui, after).message, "");
    // No answer in 60 s: the hints come back.
    let wait = W.tick(W.key(W.initialUi(NOW), st, "R", false).ui, st, NOW).ui;
    wait = W.tick(wait, st, NOW + 59).ui;
    assert.equal(W.hints(wait, st).message, "Fetching the forecast…");
    assert.equal(W.tick(wait, st, NOW + 60).ui.footer, null);
});

t("the line after R: the fetch failed, old forecast kept", () => {
    const st = rain();
    const ui = W.key(W.initialUi(NOW), st, "R", false).ui;
    const fail = reason => W.hints(ui, W.apply(st, { event: "forecast_error", at: NOW + 5, reason }, NOW + 5));
    assert.deepEqual([fail("network").message, fail("network").tone], ["Could not reach the forecast service. Still showing 15:02.", "orange"]);
    assert.equal(fail("http").message, "The forecast service answered with an error. Still showing 15:02.");
    assert.equal(fail("parse").message, "Could not read the forecast service's answer. Still showing 15:02.");
    // An earlier error is not this fetch's answer.
    const erred = W.apply(st, { event: "forecast_error", at: NOW - 30, reason: "network" }, NOW);
    const ui2 = W.key(W.initialUi(NOW), erred, "R", false).ui;
    assert.equal(W.hints(ui2, erred).message, "Fetching the forecast…");
    assert.equal(W.hints(ui2, W.apply(erred, { event: "forecast_error", at: NOW + 2, reason: "network" }, NOW)).message.slice(0, 12), "Could not re");
    // No forecast at all: nothing to keep.
    const first = load("06-first-start", NOW);
    const ui3 = W.key(W.initialUi(NOW), first, "R", false).ui;
    assert.equal(W.hints(ui3, W.apply(first, { event: "forecast_error", at: NOW, reason: "network" }, NOW)).message, "Could not reach the forecast service.");
});

const radarSt = () => load(["01-rain-dusk", "08-radar"], NOW);

t("radar page: the newest frame, paused", () => {
    const st = radarSt();
    const ui = W.key(W.initialUi(NOW), st, "M", false).ui;
    const r = W.radarView(st, NOW, ui.frame, ui.playing);
    assert.equal(r.state, "frames");
    assert.equal(r.head, "past 2 hours, not a forecast");
    assert.equal(r.frames.length, 13);
    assert.equal(r.index, 12);
    assert.equal(r.frameDir, "/cache/radar/f12");
    assert.equal(r.label, "15:10 · 10 min ago");
    assert.equal(r.labelTone, "normal");
    assert.equal(r.note, "");
    assert.deepEqual(r.ticks, Array(12).fill("past").concat(["on"]));
    assert.deepEqual([r.left, r.right], ["13:10", "15:10"]);
    assert.equal(r.timeline, true);
    assert.deepEqual(r.block, { zoom: 6, tile: 256, x0: 30, y0: 18, cols: 3, rows: 4, centre: [412.3, 520.8] });
    assert.equal(r.source, "sensor 2 min ago · radar: RainViewer · outline: Natural Earth");
    assert.equal(r.sourceTone, "normal");
    assert.deepEqual(W.hints(ui, st).keys, [["Space", "play"], ["← →", "frame"], ["M", "forecast"], ["Esc", "close"]]);
    const back = W.key(ui, st, "M", false);
    assert.equal(back.effect.kind, "radarOff");
    assert.equal(back.ui.page, "forecast");
    assert.equal(W.key(ui, st, "Esc", false).effect.kind, "close");
    assert.equal(W.key(ui, st, "R", false).effect.kind, "none");
    assert.equal(W.key(ui, st, "W", false).effect.kind, "none");
});

t("radar: stepping, the ends, a dry frame, frames dropped", () => {
    const st = radarSt();
    let ui = W.key(W.initialUi(NOW), st, "M", false).ui;
    assert.equal(W.key(ui, st, "Right", false).ui.frame, NOW - 600);
    ui = keys(ui, st, Array(7).fill("Left")).ui;
    let r = W.radarView(st, NOW, ui.frame, false);
    assert.equal(r.index, 5);
    assert.equal(r.note, "No rain on the radar.");
    assert.equal(r.label, "14:00 · 1 h 20 min ago");
    assert.deepEqual(r.ticks.slice(4, 7), ["past", "on", "after"]);
    assert.equal(W.radarView(st, NOW, NOW - 4200, false).note, "", "dry null is not dry");
    ui = keys(ui, st, Array(9).fill("Left")).ui;
    assert.equal(W.radarView(st, NOW, ui.frame, false).index, 0);
    // A new event drops the oldest frame: the shown one is found by time.
    const frames = events("08-radar", NOW + 600)[0];
    const moved = W.apply(st, frames, NOW + 600);
    assert.equal(W.radarView(moved, NOW + 600, NOW - 7800, false).index, 0);
    assert.equal(W.radarView(moved, NOW + 600, NOW - 4800, false).index, 4);
    assert.equal(W.radarView(moved, NOW + 600, null, false).frameDir, "/cache/radar/f12");
});

t("radar: playing loops at half a second, holds the newest for two", () => {
    const st = radarSt();
    let ui = W.key(W.initialUi(NOW), st, "M", false).ui;
    ui = W.key(ui, st, "Space", false).ui;
    assert.equal(ui.playing, true);
    assert.deepEqual(W.hints(ui, st).keys[0], ["Space", "pause"]);
    ui = W.tick(ui, st, NOW).ui;
    ui = W.tick(ui, st, NOW + 1.9).ui;
    assert.equal(ui.frame, null);
    ui = W.tick(ui, st, NOW + 2).ui;
    assert.equal(ui.frame, NOW - 7800);
    ui = W.tick(ui, st, NOW + 2.4).ui;
    assert.equal(ui.frame, NOW - 7800);
    ui = W.tick(ui, st, NOW + 2.5).ui;
    assert.equal(ui.frame, NOW - 7200);
    let at = NOW + 2.5;
    for (let i = 0; i < 11; i++)
        ui = W.tick(ui, st, at += 0.5).ui;
    assert.equal(W.radarView(st, at, ui.frame, ui.playing).index, 12);
    ui = W.tick(ui, st, at + 1.9).ui;
    assert.equal(W.radarView(st, at, ui.frame, true).index, 12);
    ui = W.tick(ui, st, at + 2).ui;
    assert.equal(W.radarView(st, at, ui.frame, true).index, 0);
    // An arrow pauses; Space again plays from there.
    const step = W.key(ui, st, "Right", false).ui;
    assert.equal(step.playing, false);
    assert.equal(W.key(step, st, "Space", false).ui.playing, true);
    // Not playing: tick leaves the frame.
    assert.equal(W.tick(step, st, at + 10).ui.frame, step.frame);
    // Leaving the page stops the loop.
    assert.equal(W.key(ui, st, "M", false).ui.playing, false);
});

t("radar behind after 30 min", () => {
    const st = radarSt();
    let r = W.radarView(st, NOW + 1200, null, false);
    assert.equal(r.label, "15:10 · 30 min ago");
    assert.equal(r.labelTone, "normal");
    r = W.radarView(st, NOW + 1201, null, false);
    assert.equal(r.label, "15:10 · 30 min ago, radar is behind");
    assert.equal(r.labelTone, "orange");
    r = W.radarView(st, NOW + 3600, null, false);
    assert.equal(r.label, "15:10 · 1 h 10 min ago, radar is behind");
    assert.equal(r.source, "sensor last heard 15:18 · radar: RainViewer, no new frame since 15:10");
    assert.equal(r.sourceTone, "orange");
    // An older frame keeps the orange, not the words.
    r = W.radarView(st, NOW + 3600, NOW - 1200, false);
    assert.equal(r.label, "15:00 · 1 h 20 min ago");
    assert.equal(r.labelTone, "orange");
});

t("radar not available: no frame under 2 h, an error, still loading", () => {
    const st = radarSt();
    assert.equal(W.radarView(st, NOW + 6599, null, false).state, "frames");
    let r = W.radarView(st, NOW + 6600, null, false);
    assert.equal(r.state, "unavailable");
    assert.equal(r.note, "Radar not available.");
    assert.equal(r.head, "");
    assert.equal(r.timeline, false);
    assert.deepEqual(r.ticks, []);
    assert.equal(r.frameDir, "");
    assert.equal(r.source.split(" · ")[1], "radar: no frame in the last 2 hours");
    assert.notEqual(r.block, null, "the outline and marker still draw");
    const gone = W.tick(W.key(W.key(W.initialUi(NOW), st, "M", false).ui, st, "Space", false).ui, st, NOW + 6600).ui;
    assert.equal(gone.playing, false);
    assert.deepEqual(W.hints(gone, st).keys, [["M", "forecast"], ["Esc", "close"]]);
    assert.equal(W.key(gone, st, "Space", false).effect.kind, "none");
    assert.equal(W.key(gone, st, "Left", false).ui, gone);
    const err = W.apply(rain(), { event: "radar_error", at: NOW, reason: "network" }, NOW);
    r = W.radarView(err, NOW, null, false);
    assert.deepEqual([r.state, r.note, r.source, r.sourceTone], ["unavailable", "Radar not available.", "sensor 2 min ago · radar: could not reach RainViewer", "orange"]);
    assert.equal(r.block, null);
    r = W.radarView(rain(), NOW, null, false);
    assert.deepEqual([r.state, r.note, r.source, r.sourceTone], ["loading", "Fetching the radar…", "sensor 2 min ago · radar: RainViewer", "normal"]);
    // A failed fetch with fresh frames still shows them.
    assert.equal(W.radarView(W.apply(st, { event: "radar_error", at: NOW, reason: "http" }, NOW), NOW, null, false).state, "frames");
    const empty = W.apply(rain(), { event: "radar", fetched: NOW, zoom: 6, tile: 256, x0: 30, y0: 18, cols: 3, rows: 4, centre: [1, 2], frames: [] }, NOW);
    assert.equal(W.radarView(empty, NOW, null, false).state, "unavailable");
});

t("a night and a day across the clock change", () => {
    const st = load("09-clock-change", CC);
    let v = W.view(st, CC);
    // 00:30 BST: the hour from 00:00 BST, then 01:00 twice.
    assert.deepEqual(v.hours.map(h => h.label), ["now", "01", "01", "02", "03", "04", "05", "06"]);
    assert.equal(v.days[0].label, "Today");
    assert.equal(v.days[1].label, "Mon");
    assert.equal(v.days.length, 2);
    assert.equal(v.scene.day, false);
    assert.ok(Math.abs(v.scene.frac - 24120 / 50520) < 1e-9);
    assert.equal(v.hero.condition, "Clear");
    assert.equal(v.stats[3].label, "SUNRISE");
    assert.equal(v.stats[3].value, "06:50");
    assert.equal(W.barView(st, CC).art, "clear-night");
    // Noon GMT the same day.
    const noon = CC + 45000;
    const day = W.apply(st, sensor({ temperature: 11.6, at: noon - 60 }, noon), noon);
    v = W.view(day, noon);
    assert.equal(v.scene.day, true);
    assert.ok(Math.abs(v.scene.frac - 18600 / 35760) < 1e-9);
    assert.equal(v.hours[0].label, "now");
    assert.equal(v.hours[1].label, "13");
    assert.equal(v.hours.length, 4);
    assert.equal(v.stats[3].label, "SUNSET");
    assert.equal(v.stats[3].value, "16:46");
    assert.equal(v.hero.condition, "Sunny");
    assert.equal(v.stats[1].value, D, "the current block is from the night");
    // Fetched 00:20 BST: 12 h 40 min of real time to 12:00 GMT, though the
    // wall clock moved 11 h 40 min.
    assert.equal(v.source, "sensor 1 min ago · forecast from 00:20, 12 h old");
    assert.equal(W.when(CC + 1800, noon), "01:00");
    assert.equal(W.when(CC + 5400, noon), "01:00");
    assert.equal(W.when(CC - 86400, noon), "yesterday 00:30");
    assert.equal(W.when(noon - 86400, noon), "yesterday 13:00");
});

console.log(`ok: ${n} tests`);
