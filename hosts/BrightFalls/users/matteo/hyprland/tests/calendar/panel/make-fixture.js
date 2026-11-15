// Writes a contract-shaped export from invented events (no personal data).
// usage: node make-fixture.js <out> [generated ISO] [extra events JSON]
"use strict";
const fs = require("fs");
const out = process.argv[2];
const generated = process.argv[3] || "2026-11-15T09:50:00+00:00";
const extra = process.argv[4] ? JSON.parse(process.argv[4]) : [];

const CALS = [
    { name: "Work", color: "#0082c9" },
    { name: "Home", color: "#49a03f" },
    { name: "Family", color: "#c71585" },
    { name: "Sport", color: "#e9a23b" },
];
const color = (c) => CALS.find((x) => x.name === c).color;

// [start, end, title, calendar, cancelled?, tzUnresolved?]; all-day ends are inclusive, as khal prints them.
const EVENTS = [
    ["2026-08-04 09:00", "2026-08-04 10:00", "FX first in window", "Work"],
    ["2026-11-03 09:00", "2026-11-03 10:00", "FX standup", "Work"],
    ["2026-11-09 14:00", "2026-11-09 15:00", "FX planning", "Work"],
    ["2026-11-09 18:00", "2026-11-09 19:00", "FX call", "Family"],
    ["2026-11-12", "2026-11-12", "FX bins", "Home"],
    ["2026-11-15 08:30", "2026-11-15 09:00", "FX early", "Home"],
    ["2026-11-15 11:00", "2026-11-15 12:00", "FX meeting", "Work"],
    ["2026-11-15 17:00", "2026-11-15 18:00", "FX gym", "Sport"],
    ["2026-11-15 19:30", "2026-11-15 21:30", "FX dinner", "Family"],
    ["2026-11-20", "2026-11-22", "FX trip", "Family"],
    ["2026-11-24 10:00", "2026-11-24 11:00", "FX review", "Work"],
    ["2026-11-24 10:00", "2026-11-24 10:45", "FX plumber", "Home"],
    ["2026-11-24 10:20", "2026-11-24 11:00", "FX physio", "Sport"],
    ["2026-11-26 12:00", "2026-11-26 13:00", "FX cancelled", "Work", true],
    ["2026-11-27 23:00", "2026-11-28 01:00", "FX night run", "Sport"],
    ["2026-11-30 14:00", "2026-11-30 15:00", "FX flight", "Work", false, true],
    ["2026-12-01 10:00", "2026-12-03 16:00", "FX offsite", "Work"],
    ["2026-12-25", "2026-12-25", "FX holiday", "Family"],
    ["2026-12-25 13:00", "2026-12-25 14:00", "FX lunch", "Work"],
    ["2026-12-31 23:30", "2027-01-01 00:30", "FX new year", "Home"],
    ["2027-02-14", "2027-02-14", "FX february", "Family"],
    ["2027-11-30 09:00", "2027-11-30 10:00", "FX last in window", "Work"],
].concat(extra);

const pad = (n) => (n < 10 ? "0" : "") + n;
const ymd = (d) => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
const day = (s) => { const p = s.split(/[- :]/).map(Number); return new Date(p[0], p[1] - 1, p[2]); };

const first = new Date(2026, 7, 1), last = new Date(2027, 10, 30);
const days = Math.round((last - first) / 864e5) + 1;
const lines = [];
const used = new Set();
for (let i = 0; i < days; i++) {
    const d = new Date(2026, 7, 1 + i), key = ymd(d);
    const evs = EVENTS.filter(([s, e]) => ymd(day(s)) <= key && key <= ymd(day(e))).map(([s, e, title, cal, cancelled, tz]) => {
        if (!cancelled) used.add(cal);
        return {
            start: s, end: e, title, "all-day": s.length === 10 ? "True" : "False",
            uid: "fx-" + title.replace(/\W+/g, "-").toLowerCase() + "-" + s.slice(0, 10),
            "calendar-color": color(cal), calendar: cal, cancelled: cancelled ? "CANCELLED" : "", location: "", "tz-unresolved": tz ? "True" : "False",
        };
    });
    lines.push(JSON.stringify(evs));
}
const header = { version: 1, window_start: ymd(first), days, generated, calendars: CALS.filter((c) => used.has(c.name)) };
fs.writeFileSync(out + ".tmp", JSON.stringify(header) + "\n" + lines.join("\n") + "\n");
fs.renameSync(out + ".tmp", out);
