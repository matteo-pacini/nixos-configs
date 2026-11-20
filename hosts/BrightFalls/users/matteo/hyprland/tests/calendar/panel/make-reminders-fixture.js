// Writes fixture-reminders.jsonl: a contract-shaped export with alarms,
// from invented events (no personal data), for the reminder tests.
// usage: node make-reminders-fixture.js <out>
"use strict";
const fs = require("fs");
const out = process.argv[2];

const CALS = [
    { name: "Work", color: "#0082c9" },
    { name: "Home", color: "#49a03f" },
    { name: "Family", color: "#c71585" },
    { name: "Sport", color: "#e9a23b" },
];
const color = (c) => CALS.find((x) => x.name === c).color;

// [uid, start, end, title, calendar, alarms (undefined: no field), extra fields]
const busy = [1, 2, 3, 4, 5, 6, 7].map((n) => {
    const at = (m) => "2026-11-17 " + String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
    const m = 8 * 60 + (n - 1) * 30;
    return ["t-busy-" + n, at(m), at(m + 120), "T busy " + n, "Sport", []];
});
const EVENTS = [
    ["t-one", "2026-11-16 10:00", "2026-11-16 11:00", "T one alarm", "Work", ["2026-11-16 09:30"]],
    ["t-two", "2026-11-16 12:00", "2026-11-16 13:00", "T two alarms", "Work", ["2026-11-16 11:00", "2026-11-16 11:45"]],
    ["t-default", "2026-11-16 14:00", "2026-11-16 15:00", "T default lead", "Work", undefined],
    ["t-empty", "2026-11-16 15:00", "2026-11-16 16:00", "T empty alarms", "Home", []],
    ["t-cancelled", "2026-11-16 16:00", "2026-11-16 17:00", "T cancelled", "Work", [], { cancelled: "CANCELLED" }],
    ["t-after", "2026-11-16 17:00", "2026-11-16 18:00", "T alarm after start", "Home", ["2026-11-16 17:05"]],
    ["t-zone", "2026-11-16 19:00", "2026-11-16 20:00", "T zone & <unknown>", "Work", [], { "tz-unresolved": "True" }],
    ["t-ad-alarms", "2026-11-16", "2026-11-16", "T all-day alarms", "Home", ["2026-11-15 23:50", "2026-11-16 09:00"]],
    ["t-ad-plain", "2026-11-17", "2026-11-17", "T all-day plain", "Family", []],
    ["t-ad-same", "2026-11-17", "2026-11-17", "T all-day same day", "Family", ["2026-11-17 09:00"]],
    ...busy,
    ["t-multi", "2026-11-18 10:00", "2026-11-20 16:00", "T multi-day", "Family", []],
];

const pad = (n) => (n < 10 ? "0" : "") + n;
const ymd = (d) => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());

const first = new Date(2026, 10, 14);
const days = 10;
const lines = [];
for (let i = 0; i < days; i++) {
    const key = ymd(new Date(2026, 10, 14 + i));
    lines.push(JSON.stringify(EVENTS.filter(([, s, e]) => s.slice(0, 10) <= key && key <= e.slice(0, 10)).map(([uid, s, e, title, cal, alarms, extra]) => {
        const el = {
            start: s, end: e, title, "all-day": s.length === 10 ? "True" : "False", uid,
            "calendar-color": color(cal), calendar: cal, cancelled: "", location: "", "tz-unresolved": "False",
        };
        if (alarms !== undefined)
            el.alarms = alarms;
        return Object.assign(el, extra || {});
    })));
}
const header = { version: 1, window_start: ymd(first), days, generated: "2026-11-16T06:00:00+00:00", calendars: CALS };
fs.writeFileSync(out + ".tmp", JSON.stringify(header) + "\n" + lines.join("\n") + "\n");
fs.renameSync(out + ".tmp", out);
