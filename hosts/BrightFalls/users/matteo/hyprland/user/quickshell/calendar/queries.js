// Questions the calendar panel and the bar ask of the export
// (~/.cache/desk/calendar/events.jsonl): line 1 a header, then one JSON array
// per day from the header's window_start, as khal 0.14.1 prints it with ISO
// formats. Plain script: Calendar.qml imports it, and node runs the fixture
// test on the same file.
"use strict";

var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
var WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

function ymd(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

function hm(d) {
    return pad(d.getHours()) + ":" + pad(d.getMinutes());
}

// "YYYY-MM-DD" or "YYYY-MM-DD HH:MM", in the local zone (khal converts).
function parseLocal(s) {
    var p = s.split(/[- :]/).map(Number);
    return new Date(p[0], p[1] - 1, p[2], p[3] || 0, p[4] || 0);
}

function addDays(d, n) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

function dayStart(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

// Whole days from a to b, both taken at midnight; DST-safe.
function daysBetween(a, b) {
    return Math.round((dayStart(b) - dayStart(a)) / 864e5);
}

// Monday 0 .. Sunday 6, whatever the locale.
function weekday(d) {
    return (d.getDay() + 6) % 7;
}

function isoWeek(d) {
    // The week's Thursday decides its year.
    var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
    t.setUTCDate(t.getUTCDate() + 3 - (t.getUTCDay() + 6) % 7);
    var jan1 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
    return Math.ceil(((t - jan1) / 864e5 + 1) / 7);
}

// The export, parsed: { header, calendars: [{ name, color }], byDay:
// { "YYYY-MM-DD": [event] }, first, last } or null when the text is not one.
// Cancelled entries are dropped; each day is ordered all-day first, then by
// start, then by title.
function parse(text) {
    var lines = text.split("\n");
    var header;
    try {
        header = JSON.parse(lines[0]);
    } catch (e) {
        return null;
    }
    if (!header || typeof header !== "object" || typeof header.window_start !== "string")
        return null;
    var byDay = {};
    var first = parseLocal(header.window_start);
    var d = first;
    var count = 0;
    for (var i = 1; i < lines.length; i++) {
        if (lines[i] === "")
            continue;
        var evs = JSON.parse(lines[i]).filter(function (e) {
            return e.cancelled === "";
        }).map(function (e) {
            return {
                start: parseLocal(e.start),
                end: parseLocal(e.end),
                allDay: e["all-day"] === "True",
                title: e.title,
                calendar: e.calendar,
                color: e["calendar-color"],
                uid: e.uid,
                location: e.location || "",
                // Times read in the local zone because the event's own zone
                // could not be resolved; they may be off.
                tzUnknown: e["tz-unresolved"] === "True"
            };
        });
        evs.sort(function (a, b) {
            return (b.allDay - a.allDay) || (a.start - b.start) || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0);
        });
        if (evs.length)
            byDay[ymd(d)] = evs;
        d = addDays(d, 1);
        count++;
    }
    var calendars = Array.isArray(header.calendars) ? header.calendars.filter(function (c) {
        return c && typeof c.name === "string";
    }) : [];
    return {
        header: header,
        calendars: calendars,
        byDay: byDay,
        first: first,
        last: addDays(first, Math.max(count, Number(header.days) || 0) - 1),
        generated: typeof header.generated === "string" ? new Date(header.generated) : null
    };
}

function dayEvents(data, date) {
    return data ? data.byDay[ymd(date)] || [] : [];
}

function inWindow(data, date) {
    return !!data && dayStart(date) >= data.first && dayStart(date) <= data.last;
}

// The header's order, then any calendar the header does not list in the
// order first seen.
function calendarRank(data, name) {
    for (var i = 0; i < data.calendars.length; i++)
        if (data.calendars[i].name === name)
            return i;
    return data.calendars.length;
}

function colorOf(data, name, fallback) {
    for (var i = 0; i < data.calendars.length; i++)
        if (data.calendars[i].name === name && typeof data.calendars[i].color === "string")
            return data.calendars[i].color;
    return fallback;
}

// Calendars with something on `date`, as [{ name, color }] in header order.
function dayCalendars(data, date) {
    var seen = [];
    var out = [];
    dayEvents(data, date).forEach(function (e) {
        if (seen.indexOf(e.calendar) >= 0)
            return;
        seen.push(e.calendar);
        out.push({ name: e.calendar, color: colorOf(data, e.calendar, e.color) });
    });
    out.sort(function (a, b) {
        return calendarRank(data, a.name) - calendarRank(data, b.name);
    });
    return out;
}

// { dayOfMonth: [{ name, color }] }, at most `max` per day.
function monthDots(data, year, month1, max) {
    var out = {};
    var n = new Date(year, month1, 0).getDate();
    for (var day = 1; day <= n; day++) {
        var cals = dayCalendars(data, new Date(year, month1 - 1, day));
        if (cals.length)
            out[day] = max ? cals.slice(0, max) : cals;
    }
    return out;
}

// Every calendar with an event in the month, in header order, for the legend.
function monthCalendars(data, year, month1) {
    var names = [];
    var out = [];
    var dots = monthDots(data, year, month1, 0);
    for (var day in dots)
        dots[day].forEach(function (c) {
            if (names.indexOf(c.name) < 0) {
                names.push(c.name);
                out.push(c);
            }
        });
    out.sort(function (a, b) {
        return calendarRank(data, a.name) - calendarRank(data, b.name);
    });
    return out;
}

// Timed events starting in (now, now + 60 min], each once although an event
// crossing midnight is on two days' lists.
function upcoming(data, now) {
    var limit = new Date(now.getTime() + 3600e3);
    var keys = [];
    var out = [];
    [now, limit].forEach(function (d) {
        dayEvents(data, d).forEach(function (e) {
            var key = e.uid + "@" + e.start.getTime();
            if (!e.allDay && e.start > now && e.start <= limit && keys.indexOf(key) < 0) {
                keys.push(key);
                out.push(e);
            }
        });
    });
    out.sort(function (a, b) {
        return a.start - b.start;
    });
    return out;
}

// The bar's hint: "1 event at 11:00", "2 events at 11:00" (same start),
// "2 events from 11:00" (different starts), or "" with nothing upcoming.
function hint(data, now) {
    var evs = upcoming(data, now);
    if (!evs.length)
        return "";
    var same = evs.every(function (e) {
        return e.start.getTime() === evs[0].start.getTime();
    });
    return evs.length + (evs.length === 1 ? " event" : " events") + (same ? " at " : " from ") + hm(evs[0].start);
}

// Rows of the month grid, Monday first: [{ week, days: [Date x 7] }].
function monthGrid(year, month0) {
    var firstDay = new Date(year, month0, 1);
    var start = addDays(firstDay, -weekday(firstDay));
    var count = new Date(year, month0 + 1, 0).getDate();
    var rows = Math.ceil((weekday(firstDay) + count) / 7);
    var out = [];
    for (var r = 0; r < rows; r++) {
        var days = [];
        for (var c = 0; c < 7; c++)
            days.push(addDays(start, r * 7 + c));
        out.push({ week: isoWeek(days[0]), days: days });
    }
    return out;
}

// Same day number `delta` months on, clamped to the month's last day.
function addMonths(d, delta) {
    var target = new Date(d.getFullYear(), d.getMonth() + delta, 1);
    var last = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
    return new Date(target.getFullYear(), target.getMonth(), Math.min(d.getDate(), last));
}

function longDate(d) {
    return WEEKDAYS[weekday(d)] + " " + d.getDate() + " " + MONTHS[d.getMonth()];
}

function monthTitle(year, month0) {
    return MONTHS[month0] + " " + year;
}

// "in 5 days", "tomorrow", "3 days ago", or "" for today.
function distance(date, today) {
    var n = daysBetween(today, date);
    if (n === 0)
        return "";
    if (n === 1)
        return "tomorrow";
    if (n === -1)
        return "yesterday";
    return n > 0 ? "in " + n + " days" : -n + " days ago";
}

// "Sunday 15 November" header's right side: "3 events · in 5 days".
function dayLine(count, date, today) {
    var parts = [];
    if (count > 0)
        parts.push(count + (count === 1 ? " event" : " events"));
    var dist = distance(date, today);
    if (dist !== "")
        parts.push(dist);
    return parts.join(" · ");
}

function shortRange(a, b) {
    if (a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth())
        return a.getDate() + " to " + b.getDate() + " " + MONTHS[a.getMonth()];
    return a.getDate() + " " + MONTHS[a.getMonth()].slice(0, 3) + " to " + b.getDate() + " " + MONTHS[b.getMonth()].slice(0, 3);
}

// What a day-list row shows for `e` on `date`: { time, sub, over, tzUnknown }.
// `over` is true for a timed event on today's list that has ended.
function row(e, date, now) {
    var span = daysBetween(e.start, e.end) + 1;
    var time;
    var sub = e.calendar;
    if (span > 1) {
        time = "day " + (daysBetween(e.start, date) + 1) + " of " + span;
        sub += " · " + (e.allDay ? shortRange(e.start, e.end) : shortRange(e.start, e.end) + ", " + hm(e.start) + " – " + hm(e.end));
    } else if (e.allDay) {
        time = "all day";
    } else {
        time = hm(e.start) + " – " + hm(e.end);
    }
    return {
        time: time,
        sub: sub,
        over: ymd(date) === ymd(now) && !e.allDay && e.end <= now,
        tzUnknown: e.tzUnknown
    };
}

// "" while the export is fresh (younger than 30 minutes), otherwise the
// footer's warning.
function staleText(data, now) {
    if (!data || !data.generated || isNaN(data.generated))
        return "";
    var age = now - data.generated;
    if (age < 30 * 60e3)
        return "";
    var g = data.generated;
    var when = age >= 864e5 ? g.getDate() + " " + MONTHS[g.getMonth()] + " " + hm(g) : hm(g);
    return "Calendar server not reachable. Showing events as of " + when + ".";
}

// The Nextcloud web calendar's day view for `date`, from the CalDAV base
// "https://<host>[/<path>]/remote.php/dav/". index.php works with and without
// pretty URLs. "" when the base does not have that form.
function webUrl(davBase, date) {
    var m = /^(https?:\/\/.+?\/)remote\.php\/dav\/?\s*$/.exec(davBase.trim());
    return m ? m[1] + "index.php/apps/calendar/timeGridDay/" + ymd(date) : "";
}

if (typeof module !== "undefined")
    module.exports = {
        parse: parse,
        dayEvents: dayEvents,
        dayCalendars: dayCalendars,
        inWindow: inWindow,
        monthDots: monthDots,
        monthCalendars: monthCalendars,
        upcoming: upcoming,
        hint: hint,
        monthGrid: monthGrid,
        addDays: addDays,
        addMonths: addMonths,
        isoWeek: isoWeek,
        weekday: weekday,
        longDate: longDate,
        monthTitle: monthTitle,
        distance: distance,
        dayLine: dayLine,
        row: row,
        staleText: staleText,
        webUrl: webUrl,
        ymd: ymd,
        hm: hm
    };
