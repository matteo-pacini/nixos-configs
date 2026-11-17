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

// The DST cases below prove nothing unless the zone has daylight saving.
assert.strictEqual(D("2026-01-15").getTimezoneOffset(), 0, "January is at UTC: run with TZ=Europe/London");
assert.strictEqual(D("2026-07-15").getTimezoneOffset(), -60, "July is an hour ahead of UTC: run with TZ=Europe/London");

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

// Reminders and the digest, against fixture-reminders.jsonl (invented, with
// Amendment 2's alarms; written by make-reminders-fixture.js). The week of
// Monday 16 November 2026.
const rdata = q.parse(fs.readFileSync(path.join(__dirname, "fixture-reminders.jsonl"), "utf8"));
const ev = (title) => {
    for (const day in rdata.byDay)
        for (const e of rdata.byDay[day])
            if (e.title === title)
                return e;
    throw new Error("no fixture event " + title);
};
const stamps = (ds) => ds.map((d) => q.ymd(d) + " " + q.hm(d));
const due = (s, fired) => q.dueReminders(rdata, D(s), fired || {}).map((r) => r.event.title + " @" + q.hm(r.at));

// Reminder times.
assert.deepStrictEqual(stamps(q.reminderTimes(ev("T one alarm"))), ["2026-11-16 09:30"]);
assert.deepStrictEqual(stamps(q.reminderTimes(ev("T two alarms"))), ["2026-11-16 11:00", "2026-11-16 11:45"]);
// The defaults mirror Nextcloud's: an hour before; 09:00 on a full-day
// event's first day.
assert.strictEqual(q.DEFAULT_LEAD_MIN, 60);
assert.strictEqual(q.DEFAULT_ALL_DAY_TIME, "09:00");
assert.deepStrictEqual(stamps(q.reminderTimes(ev("T default lead"))), ["2026-11-16 13:00"], "no alarms field: the default lead");
assert.deepStrictEqual(stamps(q.reminderTimes(ev("T empty alarms"))), ["2026-11-16 14:00"], "empty alarms: the default lead");
assert.deepStrictEqual(stamps(q.reminderTimes(ev("T all-day alarms"))), ["2026-11-15 23:50"], "an all-day event's alarms on its own days are left to the digest");
assert.deepStrictEqual(q.reminderTimes(ev("T all-day plain")), [], "all-day without alarms: its default 09:00 falls on its own day, so the digest stands in");
assert.deepStrictEqual(q.reminderTimes(ev("T all-day same day")), [], "an alarm on the all-day event's own day is dropped");

// Firing.
assert.deepStrictEqual(due("2026-11-16 09:29"), []);
assert.deepStrictEqual(due("2026-11-16 09:30"), ["T one alarm @09:30"]);
assert.deepStrictEqual(due("2026-11-16 09:56"), ["T one alarm @09:30"], "late start: a passed reminder fires while the event is ahead");
assert.deepStrictEqual(due("2026-11-16 09:56", { "t-one 2026-11-16 10:00|2026-11-16 09:30": "x" }), [], "fired once only");
assert.deepStrictEqual(due("2026-11-16 11:50"), ["T two alarms @11:45"], "several past alarms: once, for the latest");
assert.deepStrictEqual(due("2026-11-16 12:01"), [], "unfired reminders go when the event starts");
assert.deepStrictEqual(due("2026-11-16 17:04"), []);
assert.deepStrictEqual(due("2026-11-16 17:05"), ["T alarm after start @17:05"], "an alarm after the start fires while the event runs");
assert.deepStrictEqual(due("2026-11-16 17:59"), ["T alarm after start @17:05"]);
assert.deepStrictEqual(due("2026-11-16 18:00"), ["T zone & <unknown> @18:00"], "not once the event is over; the next event's default lead");
assert.deepStrictEqual(due("2026-11-15 23:50"), ["T all-day alarms @23:50"], "all-day alarm before its first day");
assert.deepStrictEqual(due("2026-11-16 09:00"), [], "all-day alarm on its own day: the digest covers it");

// A day minute by minute: what goes out, and each occurrence once.
function simulate(from, to, fullscreenAt) {
    let state = {};
    const out = [];
    for (let t = D(from); t <= D(to); t = new Date(t.getTime() + 60e3)) {
        const r = q.plan(rdata, state, t, fullscreenAt ? fullscreenAt(t) : false, t.getTime() === D(from).getTime());
        state = r.state;
        r.send.forEach((n) => out.push(q.hm(t) + " " + n.summary));
    }
    return { out, state };
}
const week = simulate("2026-11-15 20:00", "2026-11-20 23:59").out;
assert.deepStrictEqual(week.filter((s) => s.includes("T cancelled")), [], "cancelled entries never remind");
assert.deepStrictEqual(week.filter((s) => s.includes("T multi-day")), ["09:00 T multi-day"], "a multi-day event reminds once");
assert.deepStrictEqual(week.filter((s) => s.startsWith("09:30 ") || s.includes("T two") || s.includes("T all-day")), [
    "23:50 T all-day alarms",
    "09:30 T one alarm",
    "11:00 T two alarms",
    "11:45 T two alarms",
    "09:30 T busy 6",
], "each alarm at its own time while the shell runs; no card for an all-day event on its own day");
assert.deepStrictEqual(week.filter((s) => s.includes("Today")), [
    "06:00 Today · Monday 16 November",
    "06:00 Today · Tuesday 17 November",
    "06:00 Today · Wednesday 18 November",
    "06:00 Today · Thursday 19 November",
    "06:00 Today · Friday 20 November",
], "a digest a day at 06:00; the start on an empty Sunday sent none");

// Wording.
const note = (title, s, late) => q.reminderNote(ev(title), D(s), late);
assert.strictEqual(note("T one alarm", "2026-11-16 09:50").body, "10:00 – 11:00 · in 10 min · Work");
assert.strictEqual(note("T one alarm", "2026-11-16 09:56", true).body, "10:00 – 11:00 · starts in 4 min · Work");
assert.strictEqual(note("T one alarm", "2026-11-16 10:00").body, "10:00 – 11:00 · starts now · Work");
assert.strictEqual(note("T one alarm", "2026-11-16 08:55").body, "10:00 – 11:00 · in 1 h 5 min · Work");
assert.strictEqual(note("T one alarm", "2026-11-15 09:00").body, "Mon 16 Nov, 10:00 – 11:00 · tomorrow · Work");
assert.strictEqual(note("T alarm after start", "2026-11-16 17:25", true).body, "17:00 – 18:00 · started at 17:00, 25 min ago · Home");
assert.strictEqual(note("T zone & <unknown>", "2026-11-16 18:50").body, "19:00 – 20:00 · in 10 min · Work · time zone unknown");
assert.strictEqual(note("T zone & <unknown>", "2026-11-16 18:50").summary, "T zone & <unknown>", "summary is plain text");
assert.strictEqual(note("T all-day alarms", "2026-11-15 23:50").body, "tomorrow, all day · Home");
assert.strictEqual(note("T multi-day", "2026-11-18 09:50").body, "10:00 – Fri 20 Nov, 16:00 · in 10 min · Family", "the end's day when it is another");
assert.strictEqual(note("T one alarm", "2026-11-16 09:50").day, "2026-11-16");
assert.strictEqual(q.hm(note("T one alarm", "2026-11-16 09:50").closeAt), "10:05", "the card goes 5 min after the start");
assert.strictEqual(q.hm(note("T alarm after start", "2026-11-16 17:25").closeAt), "17:30");

// Digest content and limits.
const dg = (day, at) => q.digest(rdata, D(day), D(at));
assert.deepStrictEqual(dg("2026-11-17", "2026-11-17 06:00"), {
    key: "",
    day: "2026-11-17",
    summary: "Today · Tuesday 17 November",
    body: "all day · T all-day plain\nall day · T all-day same day\n08:00 · T busy 1\n08:30 · T busy 2\n09:00 · T busy 3\n09:30 · T busy 4\nand 3 more",
    closeAt: null,
}, "all-day first, six lines, then the rest counted");
assert.strictEqual(dg("2026-11-17", "2026-11-17 10:15").body, "all day · T all-day plain\nall day · T all-day same day\n08:30 · T busy 2\n09:00 · T busy 3\n09:30 · T busy 4\n10:00 · T busy 5\nand 2 more", "events already over are left out");
assert.strictEqual(dg("2026-11-19", "2026-11-19 06:00").body, "until 16:00 · T multi-day", "a timed event begun on an earlier day");
assert.strictEqual(dg("2026-11-21", "2026-11-21 06:00"), null, "no events, no digest");
assert.strictEqual(dg("2026-11-16", "2026-11-17 00:00"), null, "held past midnight: all over, no digest");
assert.strictEqual(dg("2026-11-16", "2026-11-16 21:00").body, "all day · T all-day alarms");

// Digest timing.
const pl = (s, state, fs, start) => q.plan(rdata, state, D(s), fs, start);
assert.deepStrictEqual(pl("2026-11-17 05:00", {}, false, true).send.map((n) => n.summary), ["Today · Tuesday 17 November"], "at shell start, even before 06:00");
assert.deepStrictEqual(pl("2026-11-17 05:59", { digest: "2026-11-16" }, false, false).send, []);
assert.deepStrictEqual(pl("2026-11-17 06:00", { digest: "2026-11-16" }, false, false).send.map((n) => n.summary), ["Today · Tuesday 17 November"]);
assert.deepStrictEqual(pl("2026-11-17 12:00", { digest: "2026-11-17" }, false, true).send, [], "once per day, restarts included");

// Holding while fullscreen, and what comes out after.
const held = simulate("2026-11-16 09:00", "2026-11-16 09:56", (t) => t >= D("2026-11-16 09:00"));
assert.deepStrictEqual(held.out, [], "nothing goes out while fullscreen");
assert.deepStrictEqual(held.state.held, [{ key: "t-one 2026-11-16 10:00", at: "2026-11-16 09:30" }]);
assert.strictEqual(held.state.digestPending, "2026-11-16");
const released = (s, state) => q.plan(rdata, state, D(s), false, false).send.map((n) => n.summary + ": " + n.body);
assert.deepStrictEqual(released("2026-11-16 09:57", held.state), [
    "Today · Monday 16 November: all day · T all-day alarms\n10:00 · T one alarm\n12:00 · T two alarms\n14:00 · T default lead\n15:00 · T empty alarms\n17:00 · T alarm after start\nand 1 more",
    "T one alarm: 10:00 – 11:00 · starts in 3 min · Work",
], "digest first, then reminders, worded for the moment");
assert.deepStrictEqual(released("2026-11-16 10:25", held.state).slice(1), ["T one alarm: 10:00 – 11:00 · started at 10:00, 25 min ago · Work"]);
assert.deepStrictEqual(released("2026-11-16 11:00", held.state).filter((s) => s.startsWith("T one")), [], "an event over by release is dropped");
const busy = simulate("2026-11-17 07:00", "2026-11-17 08:55", () => true).state;
assert.strictEqual(busy.held.length, 4);
assert.deepStrictEqual(released("2026-11-17 08:56", busy).slice(1), [
    "4 calendar reminders: T busy 1 · started at 08:00, 56 min ago\nT busy 2 · started at 08:30, 26 min ago\nT busy 3 · starts in 4 min\nT busy 4 · starts in 34 min",
], "more than three held: one summary, earliest first");
const three = simulate("2026-11-17 07:00", "2026-11-17 08:00", () => true).state;
assert.deepStrictEqual(released("2026-11-17 08:01", three).slice(1).map((s) => s.split(":")[0]), ["T busy 1", "T busy 2", "T busy 3"], "three or fewer: separate, earliest first");
const replaced = simulate("2026-11-16 10:55", "2026-11-16 11:50", () => true).state;
assert.deepStrictEqual(replaced.held, [{ key: "t-two 2026-11-16 12:00", at: "2026-11-16 11:45" }], "a later reminder replaces the held one");

// Pruning: fired entries go 3 days after their event's end.
const pruned = q.plan(rdata, { fired: { "a|2026-11-10 09:00": "2026-11-13 09:59", "b|2026-11-10 09:00": "2026-11-13 10:00", "c|2026-11-01 09:00": "2026-11-20 10:00" } }, D("2026-11-16 10:00"), true, false).state.fired;
assert.deepStrictEqual(Object.keys(pruned), ["b|2026-11-10 09:00", "c|2026-11-01 09:00"]);

// Markup in titles and calendar names, calendars the header does not list,
// long digests and summaries, wording edges. Invented export, built here.
{
    const ev = (start, end, title, cal, extra) => Object.assign({ start, end, title, "all-day": "False", uid: title.replace(/\W/g, ""), "calendar-color": cal === "Listed & Co" ? "#111111" : "#222222", calendar: cal, cancelled: "", location: "", "tz-unresolved": "False", alarms: [] }, extra || {});
    const day1 = [ev("2026-11-16 10:00", "2026-11-16 11:00", "Tea <b>& cake</b>", "Listed & Co")];
    for (let i = 2; i <= 8; i++)
        day1.push(ev(`2026-11-16 ${9 + i}:00`, `2026-11-16 ${9 + i}:30`, `E${i}`, i === 2 ? "Unlisted" : "Listed & Co"));
    const day3 = [ev("2026-11-18", "2026-11-20", "Trip", "Listed & Co", { "all-day": "True" })];
    const mdata = q.parse([JSON.stringify({ version: 1, window_start: "2026-11-16", days: 5, generated: "2026-11-16T06:00:00+00:00", calendars: [{ name: "Listed & Co", color: "#111111" }] }), JSON.stringify(day1), "[]", JSON.stringify(day3)].join("\n"));
    const now = D("2026-11-16 09:00");
    const evs = q.dayEvents(mdata, D("2026-11-16"));

    assert.strictEqual(q.ymd(mdata.last), "2026-11-20", "header days beyond the lines given extend the window");
    assert.deepStrictEqual(q.dayCalendars(mdata, D("2026-11-16")), [{ name: "Listed & Co", color: "#111111" }, { name: "Unlisted", color: "#222222" }], "an unlisted calendar comes last, in its events' colour");

    const note = q.reminderNote(evs[0], now, false);
    assert.strictEqual(note.summary, "Tea <b>& cake</b>", "the summary is plain text");
    assert.strictEqual(note.body, "10:00 – 11:00 · in 1 h · Listed &amp; Co", "the body is markup: calendar escaped");
    assert.strictEqual(q.digest(mdata, D("2026-11-16"), D("2026-11-16 07:00")).body,
        "10:00 · Tea &lt;b&gt;&amp; cake&lt;/b&gt;\n11:00 · E2\n12:00 · E3\n13:00 · E4\n14:00 · E5\n15:00 · E6\nand 2 more", "digest: titles escaped, six lines then a count");
    const many = q.heldNotes(mdata, evs.map((e) => ({ key: q.occurrenceKey(e), at: "2026-11-16 08:00" })), now);
    assert.strictEqual(many.length, 1);
    assert.strictEqual(many[0].summary, "8 calendar reminders");
    assert.strictEqual(many[0].body, "Tea &lt;b&gt;&amp; cake&lt;/b&gt; · starts in 1 h\nE2 · starts in 2 h\nE3 · starts in 3 h\nE4 · starts in 4 h\nE5 · starts in 5 h\nE6 · starts in 6 h\nand 2 more", "held summary: titles escaped, capped");
    assert.strictEqual(q.ymd(many[0].closeAt) + " " + q.hm(many[0].closeAt), "2026-11-16 17:05", "held summary stays until 5 min after the last start");

    assert.strictEqual(q.reminderNote(q.dayEvents(mdata, D("2026-11-18"))[0], now, false).body, "in 2 days, 18 to 20 November · Listed &amp; Co", "multi-day all-day");
    assert.strictEqual(q.reminderNote(evs[3], D("2026-11-16 11:00"), false).body, "13:00 – 13:30 · in 2 h · Listed &amp; Co", "whole hours: no 0 min");
    assert.strictEqual(q.reminderNote(evs[3], D("2026-11-16 10:55"), false).body, "13:00 – 13:30 · in 2 h 5 min · Listed &amp; Co");
    assert.strictEqual(q.reminderNote(Object.assign({}, evs[0], { start: D("2026-11-19 10:00"), end: D("2026-11-19 11:00") }), now, false).body, "Thu 19 Nov, 10:00 – 11:00 · in 3 days · Listed &amp; Co", "days ahead");
    assert.strictEqual(q.distance(D("2026-11-15"), D("2026-11-16")), "yesterday");
    assert.strictEqual(q.distance(D("2026-11-13"), D("2026-11-16")), "3 days ago");

    assert.deepStrictEqual(q.plan(null, {}, now, false, false).send, [], "no export: nothing to send");
    assert.strictEqual(q.parse('{"version":1}\n[]'), null, "a header without window_start");
    assert.strictEqual(q.staleText(q.parse('{"window_start":"2026-11-16","generated":5}\n[]'), now), "", "generated not a string");
    assert.strictEqual(q.staleText(q.parse('{"window_start":"2026-11-16","generated":"garbage"}\n[]'), now), "", "generated not a date");
    // KNOWN BUG (latent): parse is documented to give null for text that is
    // not an export, but a broken day line throws. The export is written in
    // one rename, so a half-written file is not expected. When fixed, expect
    // null here.
    assert.throws(() => q.parse('{"window_start":"2026-11-16"}\n[{"start":'), SyntaxError);
}

// The big view: day cells, the header note, keys. Invented export, built here.
{
    const ev = (start, end, title, cal, extra) => Object.assign({ start, end, title, "all-day": "False", uid: title.replace(/\W/g, ""), "calendar-color": "#999999", calendar: cal, cancelled: "", location: "", "tz-unresolved": "False", alarms: [] }, extra || {});
    const kiln = ev("2026-11-16", "2026-11-18", "Kiln day", "Pottery", { "all-day": "True" });
    const ferry = ev("2026-11-16 23:00", "2026-11-17 01:00", "Ferry", "Garden");
    const day16 = [
        ferry,
        ev("2026-11-16 10:00", "2026-11-16 10:30", "Seed swap", "Garden"),
        ev("2026-11-15 22:00", "2026-11-16 02:00", "Owl watch", "Garden"),
        ev("2026-11-16 10:00", "2026-11-16 11:00", "Glaze talk", "Pottery"),
        kiln,
    ];
    const day19 = [ev("2026-11-19 19:30", "2026-11-19 21:00", "Choir practice", "Choir", { "calendar-color": "#5555cc" })];
    const bdata = q.parse([
        JSON.stringify({ version: 1, window_start: "2026-11-16", days: 5, calendars: [{ name: "Pottery", color: "#aa3366" }, { name: "Garden", color: "#33aa66" }] }),
        JSON.stringify(day16), JSON.stringify([kiln, ferry]), JSON.stringify([kiln]), JSON.stringify(day19), "[]",
    ].join("\n"));
    const cell = (s, max) => q.cellView(bdata, D(s), max);
    const all16 = [
        { title: "Kiln day", color: "#aa3366", time: "", filled: true },
        { title: "Owl watch", color: "#33aa66", time: "", filled: true },
        { title: "Glaze talk", color: "#aa3366", time: "10:00", filled: false },
        { title: "Seed swap", color: "#33aa66", time: "10:00", filled: false },
        { title: "Ferry", color: "#33aa66", time: "23:00", filled: false },
    ];
    assert.deepStrictEqual(cell("2026-11-16", 6), { chips: all16, more: 0 }, "fits: all-day, begun the day before, by start, then title; header colours");
    assert.deepStrictEqual(cell("2026-11-16", 5), { chips: all16, more: 0 }, "fits exactly");
    assert.deepStrictEqual(cell("2026-11-16", 4), { chips: all16.slice(0, 3), more: 2 }, "does not fit: the more line takes a row");
    assert.deepStrictEqual(cell("2026-11-16", 1), { chips: [], more: 5 }, "one row, too many: only the more line");
    assert.deepStrictEqual(cell("2026-11-16", 0), { chips: [], more: 5 });
    assert.deepStrictEqual(cell("2026-11-16", -3), { chips: [], more: 5 });
    assert.deepStrictEqual(cell("2026-11-19", 1), { chips: [{ title: "Choir practice", color: "#5555cc", time: "19:30", filled: false }], more: 0 }, "one row, one event; an unlisted calendar keeps its event's colour");
    assert.deepStrictEqual(cell("2026-11-17", 3), { chips: [
        { title: "Kiln day", color: "#aa3366", time: "", filled: true },
        { title: "Ferry", color: "#33aa66", time: "", filled: true },
    ], more: 0 }, "a timed event crossing midnight, on its second day, is filled");
    assert.deepStrictEqual(cell("2026-11-18", 3), { chips: [{ title: "Kiln day", color: "#aa3366", time: "", filled: true }], more: 0 }, "a several-day all-day event on its last day");
    assert.deepStrictEqual(cell("2026-11-20", 3), { chips: [], more: 0 }, "empty day");
    assert.deepStrictEqual(q.cellView(null, D("2026-11-16"), 3), { chips: [], more: 0 }, "no export");
    assert.deepStrictEqual(q.cellView(null, D("2026-11-16"), 0), { chips: [], more: 0 });

    assert.strictEqual(q.moreText(3), "3 more");
    assert.strictEqual(q.moreText(1), "1 more");

    assert.strictEqual(q.fitRows(68, 20, 4), 3, "three rows and two gaps exactly");
    assert.strictEqual(q.fitRows(67, 20, 4), 2);
    assert.strictEqual(q.fitRows(20, 20, 4), 1, "one row needs no gap");
    assert.strictEqual(q.fitRows(19, 20, 4), 0);
    assert.strictEqual(q.fitRows(0, 20, 4), 0);
    assert.strictEqual(q.fitRows(-10, 20, 4), 0, "never negative");
    assert.strictEqual(q.fitRows(100, 25, 0), 4);

    const today = D("2026-11-17 09:00");
    assert.strictEqual(q.headerNote(true, D("2026-11-20"), today), "syncing…");
    assert.strictEqual(q.headerNote(true, D("2027-03-10"), today), "syncing…", "syncing wins in any month");
    assert.strictEqual(q.headerNote(false, D("2026-11-20"), today), "week 47", "this month: the selected day's week");
    assert.strictEqual(q.headerNote(false, D("2026-11-01"), today), "week 44");
    assert.strictEqual(q.headerNote(false, D("2026-12-05"), today), "weeks 49 to 53");
    assert.strictEqual(q.headerNote(false, D("2027-01-10"), today), "weeks 53 to 4", "the grid's first row is in the old year's last week");
    assert.strictEqual(q.headerNote(false, D("2027-01-01"), D("2027-01-03 12:00")), "week 53", "this month, a day in the old year's week");
    assert.strictEqual(q.headerNote(false, D("2025-11-20"), today), "weeks 44 to 48", "same month a year earlier is not this month");

    const act = (name, plain) => q.bigViewKey(name, plain === undefined ? true : plain);
    assert.deepStrictEqual(act("Esc"), { do: "close" });
    assert.deepStrictEqual(act("Left"), { do: "move", days: -1 });
    assert.deepStrictEqual(act("Right"), { do: "move", days: 1 });
    assert.deepStrictEqual(act("Up"), { do: "move", days: -7 });
    assert.deepStrictEqual(act("Down"), { do: "move", days: 7 });
    assert.deepStrictEqual(act("PgUp"), { do: "move", months: -1 });
    assert.deepStrictEqual(act("PgDn"), { do: "move", months: 1 });
    assert.deepStrictEqual(act("T"), { do: "today" });
    assert.deepStrictEqual(act("R"), { do: "sync" });
    assert.deepStrictEqual(act("Enter"), { do: "web" });
    assert.deepStrictEqual(act("O"), { do: "web" });
    assert.deepStrictEqual(act("F"), { do: "dropdown" });
    for (const k of ["T", "R", "O", "F"])
        assert.deepStrictEqual(act(k, false), { do: "none" }, "a letter with a modifier does nothing: " + k);
    for (const k of ["Esc", "Left", "Right", "Up", "Down", "PgUp", "PgDn", "Enter"])
        assert.notDeepStrictEqual(act(k, false), { do: "none" }, "a non-letter key acts with modifiers too: " + k);
    for (const k of ["Tab", "Home", "S", "D", "", undefined])
        assert.deepStrictEqual(act(k), { do: "none" }, "not used: " + k);

    const mv = (sel, name, at) => md(q.bigViewMove(D(sel), act(name), D(at || "2026-11-17 09:00")));
    assert.strictEqual(mv("2026-11-30", "Right"), "2026-12-01");
    assert.strictEqual(mv("2026-12-01", "Left"), "2026-11-30");
    assert.strictEqual(mv("2026-12-29", "Down"), "2027-01-05");
    assert.strictEqual(mv("2027-01-05", "Up"), "2026-12-29");
    assert.strictEqual(mv("2027-01-31", "PgDn"), "2027-02-28", "31 January + 1 month is clamped");
    assert.strictEqual(mv("2026-03-31", "PgUp"), "2026-02-28");
    assert.strictEqual(mv("2027-05-03", "T", "2026-11-17 09:00"), "2026-11-17", "today");
    assert.strictEqual(q.hm(q.bigViewMove(D("2027-05-03"), act("T"), D("2026-11-17 09:00"))), "00:00", "today at midnight, like every selected day");
    assert.strictEqual(mv("2026-03-28", "Right"), "2026-03-29", "across the spring DST change");
    for (const k of ["Esc", "R", "Enter", "F", "Tab"])
        assert.strictEqual(mv("2026-11-20", k), "2026-11-20", "a key that does not move keeps the day: " + k);

    for (const k of ["Left", "Right", "Up", "Down", "PgUp", "PgDn"])
        assert.strictEqual(q.bigViewRepeats(k), true, "a held moving key repeats: " + k);
    for (const k of ["Esc", "Enter", "T", "R", "O", "F", "Tab"])
        assert.strictEqual(q.bigViewRepeats(k), false, "a held key acts once: " + k);
}

console.log("calendar queries: all assertions passed");
