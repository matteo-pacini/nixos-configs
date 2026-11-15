// Fixture test for quickshell/calendar/queries.js against fixture-events.jsonl
// (next to this file). Run in the Europe/London zone:
//   TZ=Europe/London node test-calendar.js [path/to/queries.js]
// The default library is the repository's; pass ~/.config/quickshell/calendar/queries.js
// to test a live edit. As a flake check: nix build .#checks.x86_64-linux.calendar-panel
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const q = require(path.resolve(process.argv[2] || path.join(__dirname, "../../../user/quickshell/calendar/queries.js")));

const data = q.parse(fs.readFileSync(path.join(__dirname, "fixture-events.jsonl"), "utf8"));
const D = (s) => { const p = s.split(/[- :T]/).map(Number); return new Date(p[0], p[1] - 1, p[2], p[3] || 0, p[4] || 0); };
const names = (cals) => cals.map((c) => c.name);

// Header and parse.
assert.deepStrictEqual(names(data.calendars), ["Work", "Home", "Family", "Sport"]);
assert.strictEqual(q.ymd(data.first), "2026-08-01");
assert.strictEqual(q.ymd(data.last), "2027-11-30");
assert.strictEqual(q.parse("not json\n[]"), null);
assert.strictEqual(q.parse(""), null);

// Window.
assert.strictEqual(q.inWindow(data, D("2026-07-31")), false);
assert.strictEqual(q.inWindow(data, D("2026-08-01")), true);
assert.strictEqual(q.inWindow(data, D("2027-11-30")), true);
assert.strictEqual(q.inWindow(data, D("2027-12-01")), false);
assert.deepStrictEqual(q.monthDots(data, 2026, 7, 3), {}, "months before the window have no dots");
assert.deepStrictEqual(Object.keys(q.monthDots(data, 2027, 11, 3)), ["30"]);

// Month dots: header order, three at most, cancelled ignored.
const nov = q.monthDots(data, 2026, 11, 3);
assert.deepStrictEqual(Object.keys(nov).map(Number), [3, 9, 12, 15, 20, 21, 22, 24, 27, 28, 30]);
assert.deepStrictEqual(names(nov[15]), ["Work", "Home", "Family"], "four calendars, first three in header order");
assert.deepStrictEqual(names(nov[9]), ["Work", "Family"]);
assert.deepStrictEqual(names(nov[24]), ["Work", "Home", "Sport"]);
assert.deepStrictEqual(nov[12], [{ name: "Home", color: "#49a03f" }]);
assert.strictEqual(nov[26], undefined, "cancelled-only day has no dot");
assert.deepStrictEqual(names(q.monthCalendars(data, 2026, 11)), ["Work", "Home", "Family", "Sport"]);
assert.deepStrictEqual(names(q.monthCalendars(data, 2027, 2)), ["Family"]);
assert.deepStrictEqual(names(q.monthCalendars(data, 2027, 1)), ["Home"], "the event crossing into the new year");

// Day lists: all-day first, then start, then title.
const brief = (s) => q.dayEvents(data, D(s)).map((e) => e.title);
assert.deepStrictEqual(brief("2026-11-15"), ["FX early", "FX meeting", "FX gym", "FX dinner"]);
assert.deepStrictEqual(brief("2026-11-24"), ["FX plumber", "FX review", "FX physio"]);
assert.deepStrictEqual(brief("2026-11-25"), [], "empty day");
assert.deepStrictEqual(brief("2026-11-26"), [], "cancelled hidden");
assert.deepStrictEqual(brief("2026-12-25"), ["FX holiday", "FX lunch"], "all-day first");
assert.deepStrictEqual(brief("2026-11-28"), ["FX night run"], "crossing midnight is on the next day too");

// Rows.
const now = D("2026-11-15 09:53");
const r = (s, i, at) => q.row(q.dayEvents(data, D(s))[i], D(s), at || now);
assert.deepStrictEqual(r("2026-11-15", 0), { time: "08:30 – 09:00", sub: "Home", over: true, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-15", 1), { time: "11:00 – 12:00", sub: "Work", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-12", 0), { time: "all day", sub: "Home", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-21", 0), { time: "day 2 of 3", sub: "Family · 20 to 22 November", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-20", 0), { time: "day 1 of 3", sub: "Family · 20 to 22 November", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-12-02", 0), { time: "day 2 of 3", sub: "Work · 1 to 3 December, 10:00 – 16:00", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-28", 0), { time: "day 2 of 2", sub: "Sport · 27 to 28 November, 23:00 – 01:00", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2027-01-01", 0), { time: "day 2 of 2", sub: "Home · 31 Dec to 1 Jan, 23:30 – 00:30", over: false, tzUnknown: false });
assert.deepStrictEqual(r("2026-11-30", 0), { time: "14:00 – 15:00", sub: "Work", over: false, tzUnknown: true }, "tz-unresolved is carried to the row");
assert.strictEqual(q.hint(data, D("2026-11-30 13:30")), "1 event at 14:00", "tz-unresolved events still give the hint");
assert.strictEqual(r("2026-11-12", 0, D("2026-11-12 23:00")).over, false, "all-day events are never faded");
assert.strictEqual(r("2026-11-03", 0, D("2026-11-15 09:53")).over, false, "only today's list fades");

// Hint: the three wordings, started events, the 60-minute edge, midnight.
const hint = (s) => q.hint(data, D(s));
assert.strictEqual(hint("2026-11-24 09:00"), "2 events at 10:00", "same start; 10:20 is past the hour");
assert.strictEqual(hint("2026-11-24 09:30"), "3 events from 10:00");
assert.strictEqual(hint("2026-11-24 09:59"), "3 events from 10:00");
assert.strictEqual(hint("2026-11-24 10:00"), "1 event at 10:20", "started events drop out");
assert.strictEqual(hint("2026-11-24 10:20"), "", "goes when the last has started");
assert.strictEqual(hint("2026-11-24 08:59"), "", "more than an hour away");
assert.strictEqual(hint("2026-11-15 10:00"), "1 event at 11:00");
assert.strictEqual(hint("2026-11-11 23:30"), "", "all-day events never give the hint");
assert.strictEqual(hint("2026-11-27 22:30"), "1 event at 23:00", "an event crossing midnight counts once");
assert.strictEqual(hint("2026-12-31 23:00"), "1 event at 23:30");
assert.strictEqual(hint("2026-12-02 09:30"), "", "multi-day event repeated on a later day is not upcoming");
assert.strictEqual(hint("2027-12-01 09:00"), "", "outside the window");
assert.strictEqual(q.hint(null, D("2026-11-24 09:30")), "", "no export");

// Month borders, weeks, grid.
const md = (d) => q.ymd(d);
assert.strictEqual(md(q.addDays(D("2026-11-30"), 1)), "2026-12-01");
assert.strictEqual(md(q.addDays(D("2026-12-01"), -1)), "2026-11-30");
assert.strictEqual(md(q.addDays(D("2026-11-29"), 7)), "2026-12-06");
assert.strictEqual(md(q.addDays(D("2026-12-29"), 7)), "2027-01-05");
assert.strictEqual(md(q.addDays(D("2026-03-29"), 1)), "2026-03-30", "across the spring DST change");
assert.strictEqual(md(q.addDays(D("2026-10-25"), -1)), "2026-10-24", "across the autumn DST change");
assert.strictEqual(md(q.addMonths(D("2027-01-31"), 1)), "2027-02-28", "clamped");
assert.strictEqual(md(q.addMonths(D("2026-03-31"), -1)), "2026-02-28");
assert.strictEqual(md(q.addMonths(D("2026-12-15"), 1)), "2027-01-15");
assert.strictEqual(md(q.addMonths(D("2027-01-15"), -1)), "2026-12-15");
assert.strictEqual(q.isoWeek(D("2026-11-15")), 46);
assert.strictEqual(q.isoWeek(D("2026-11-16")), 47, "Monday starts the week");
assert.strictEqual(q.isoWeek(D("2027-01-01")), 53);
assert.strictEqual(q.isoWeek(D("2027-01-04")), 1);
assert.strictEqual(q.isoWeek(D("2026-01-01")), 1);
const dec = q.monthGrid(2026, 11);
assert.deepStrictEqual(dec.map((w) => w.week), [49, 50, 51, 52, 53]);
assert.strictEqual(md(dec[0].days[0]), "2026-11-30");
assert.strictEqual(md(dec[4].days[6]), "2027-01-03");
assert.deepStrictEqual(q.monthGrid(2026, 10).map((w) => w.week), [44, 45, 46, 47, 48, 49], "November 2026 needs six rows");
assert.deepStrictEqual(q.monthGrid(2027, 1).map((w) => w.week), [5, 6, 7, 8], "February 2027 starts on a Monday");
assert.strictEqual(q.weekday(D("2026-11-15")), 6);

// Text.
assert.strictEqual(q.longDate(D("2026-11-15")), "Sunday 15 November");
assert.strictEqual(q.monthTitle(2026, 10), "November 2026");
assert.strictEqual(q.dayLine(3, D("2026-11-15"), D("2026-11-15")), "3 events");
assert.strictEqual(q.dayLine(1, D("2026-11-20"), D("2026-11-15")), "1 event · in 5 days");
assert.strictEqual(q.dayLine(0, D("2026-11-18"), D("2026-11-15")), "in 3 days");
assert.strictEqual(q.dayLine(0, D("2026-11-12"), D("2026-11-15")), "3 days ago");
assert.strictEqual(q.dayLine(2, D("2026-11-16"), D("2026-11-15")), "2 events · tomorrow");
assert.strictEqual(q.distance(D("2026-12-25"), D("2026-11-15")), "in 40 days");
assert.strictEqual(q.distance(D("2026-03-30"), D("2026-03-28")), "in 2 days", "across DST");

// Staleness from the header's generated time (fixture: 09:50 UTC = 09:50 London).
assert.strictEqual(q.staleText(data, D("2026-11-15 10:19")), "");
assert.strictEqual(q.staleText(data, D("2026-11-15 10:20")), "Calendar server not reachable. Showing events as of 09:50.");
assert.strictEqual(q.staleText(data, D("2026-11-16 09:50")), "Calendar server not reachable. Showing events as of 15 November 09:50.");
assert.strictEqual(q.staleText(null, D("2026-11-16 09:50")), "");

// Web calendar address.
assert.strictEqual(q.webUrl("https://cloud.example.org/remote.php/dav/\n", D("2026-11-20")), "https://cloud.example.org/index.php/apps/calendar/timeGridDay/2026-11-20");
assert.strictEqual(q.webUrl("https://example.org/nc/remote.php/dav", D("2027-01-05")), "https://example.org/nc/index.php/apps/calendar/timeGridDay/2027-01-05");
assert.strictEqual(q.webUrl("https://example.org/caldav/", D("2027-01-05")), "");

console.log("calendar queries: all assertions passed");
