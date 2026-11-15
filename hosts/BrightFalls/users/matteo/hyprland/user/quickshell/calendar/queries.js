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
                tzUnknown: e["tz-unresolved"] === "True",
                // The occurrence's own reminder moments; older exports
                // have no such field.
                alarms: (Array.isArray(e.alarms) ? e.alarms : []).map(parseLocal)
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

// Reminders and the morning digest. Reminders.qml calls plan() once a minute
// and does what it returns; everything below is decided here.

// Reminders for events without alarms of their own. These two copy the
// Nextcloud Calendar settings "Default reminder for part-day events" and
// "Default reminder for full-day events", which the sync cannot read; change
// them together with those.
// Part-day: minutes before the start.
var DEFAULT_LEAD_MIN = 60;
// Full-day: time of day on the event's first day.
var DEFAULT_ALL_DAY_TIME = "09:00";
// A reminder card stays this long after its event has started.
var CARD_AFTER_START_MIN = 5;
// Held items beyond this many arrive as one summary.
var MAX_SEPARATE = 3;
// Event lines in the digest or a summary before "and N more".
var MAX_LINES = 6;
// The digest is sent at the first minute at or after this hour, or at shell
// start when that is earlier.
var DIGEST_HOUR = 6;
// Fired entries are kept this long after their event has ended.
var PRUNE_DAYS = 3;

var SHORT_DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// "YYYY-MM-DD HH:MM", the export's own form.
function stamp(d) {
    return ymd(d) + " " + hm(d);
}

function shortDay(d) {
    return SHORT_DAYS[weekday(d)] + " " + d.getDate() + " " + MONTHS[d.getMonth()].slice(0, 3);
}

// Body text goes out as notification markup.
function escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// The moment the occurrence is over; an all-day end is its last day.
function endOf(e) {
    return e.allDay ? addDays(e.end, 1) : e.end;
}

// One occurrence of one event: the same on every day a multi-day event is
// listed, different once its start moves.
function occurrenceKey(e) {
    return e.uid + " " + stamp(e.start);
}

// A reminder of one occurrence at one moment; a changed alarm is a new one.
function fireId(key, at) {
    return key + "|" + stamp(at);
}

// Its own alarms when it has any, otherwise the default for its kind. An
// all-day event reminds only at alarms before its first day: on the days it
// covers the digest stands in for them. Its default, DEFAULT_ALL_DAY_TIME on
// its first day, is such an alarm, so an all-day event without alarms of its
// own is announced by the digest alone.
function reminderTimes(e) {
    if (e.allDay) {
        var own = e.alarms && e.alarms.length ? e.alarms : [parseLocal(ymd(e.start) + " " + DEFAULT_ALL_DAY_TIME)];
        return own.filter(function (t) {
            return t < e.start;
        });
    }
    if (e.alarms && e.alarms.length)
        return e.alarms;
    return [new Date(e.start.getTime() - DEFAULT_LEAD_MIN * 60e3)];
}

// Each occurrence listed on `now`'s day or later, once. Running events are
// on today's list, so nothing that can still remind is missed.
function occurrences(data, now) {
    var out = [];
    if (!data)
        return out;
    var seen = {};
    var from = ymd(now);
    for (var day in data.byDay) {
        if (day < from)
            continue;
        data.byDay[day].forEach(function (e) {
            var key = occurrenceKey(e);
            if (!seen[key]) {
                seen[key] = true;
                out.push(e);
            }
        });
    }
    return out;
}

function findOccurrence(data, key, now) {
    var all = occurrences(data, now);
    for (var i = 0; i < all.length; i++)
        if (occurrenceKey(all[i]) === key)
            return all[i];
    return null;
}

// Reminders due at `now` that `fired` (fireId -> anything) has not seen:
// [{ key, at, event }], by start. Per occurrence only the latest past
// moment counts. A moment before the start counts until the start, one at
// or after the start until the end.
function dueReminders(data, now, fired) {
    var out = [];
    occurrences(data, now).forEach(function (e) {
        var end = endOf(e);
        var at = null;
        reminderTimes(e).forEach(function (t) {
            if (t > now)
                return;
            var live = t < e.start ? now < e.start : now < end;
            if (live && (!at || t > at))
                at = t;
        });
        var key = occurrenceKey(e);
        if (at && !fired[fireId(key, at)])
            out.push({ key: key, at: at, event: e });
    });
    out.sort(function (a, b) {
        return (a.event.start - b.event.start) || (a.event.title < b.event.title ? -1 : a.event.title > b.event.title ? 1 : 0);
    });
    return out;
}

function span(minutes) {
    if (minutes < 60)
        return minutes + " min";
    var h = Math.floor(minutes / 60);
    var m = minutes % 60;
    return h + " h" + (m ? " " + m + " min" : "");
}

// "11:00 – 12:00", with the day in front when it is not today's.
function rangeText(e, now) {
    var sameDay = function (a, b) {
        return ymd(a) === ymd(b);
    };
    var lastMinute = new Date(e.end.getTime() - 1);
    return (sameDay(e.start, now) ? "" : shortDay(e.start) + ", ") + hm(e.start) + " – " + (sameDay(e.start, lastMinute) ? "" : shortDay(e.end) + ", ") + hm(e.end);
}

// How far a timed event's start is: "in 10 min" ("starts in 3 min" when
// `late`), "in 2 h 5 min", "tomorrow", "starts now", or "started at 11:00,
// 25 min ago".
function whenText(e, now, late) {
    if (now < e.start) {
        var ahead = Math.ceil((e.start - now) / 60e3);
        if (ahead >= 24 * 60)
            return distance(e.start, now);
        return (late ? "starts in " : "in ") + span(ahead);
    }
    var ago = Math.floor((now - e.start) / 60e3);
    return ago === 0 ? "starts now" : "started at " + hm(e.start) + ", " + span(ago) + " ago";
}

// "tomorrow, all day", "in 3 days, 20 to 22 November", or "all day" once it
// has begun.
function allDayText(e, now) {
    var days = ymd(e.start) === ymd(e.end) ? "all day" : shortRange(e.start, e.end);
    var dist = distance(e.start, now);
    return (now < e.start && dist !== "" ? dist + ", " : "") + days;
}

// A reminder card: { key, day, summary, body, closeAt }. `late` when it goes
// out a minute or more after its reminder moment.
function reminderNote(e, now, late) {
    var parts = e.allDay ? [allDayText(e, now), e.calendar] : [rangeText(e, now), whenText(e, now, late), e.calendar];
    if (e.tzUnknown)
        parts.push("time zone unknown");
    var after = new Date(Math.max(e.start.getTime(), now.getTime()) + CARD_AFTER_START_MIN * 60e3);
    return {
        key: occurrenceKey(e),
        day: ymd(e.start < now ? now : e.start),
        summary: e.title,
        body: escape(parts.join(" · ")),
        closeAt: after
    };
}

function capped(lines) {
    if (lines.length <= MAX_LINES)
        return lines;
    return lines.slice(0, MAX_LINES).concat(["and " + (lines.length - MAX_LINES) + " more"]);
}

// The digest for `day` as sent at `now`, or null when nothing on it is left:
// all-day events first, then timed ones by start, leaving out what is over.
function digest(data, day, now) {
    var evs = dayEvents(data, day).filter(function (e) {
        return endOf(e) > now;
    });
    if (!evs.length)
        return null;
    var lines = evs.map(function (e) {
        var time = e.allDay ? "all day" : e.start < dayStart(day) ? "until " + hm(e.end) : hm(e.start);
        return escape(time + " · " + e.title);
    });
    return {
        key: "",
        day: ymd(day),
        summary: (ymd(day) === ymd(now) ? "Today · " : "") + longDate(day),
        body: capped(lines).join("\n"),
        closeAt: null
    };
}

// What `held` ([{ key, at }]) becomes at `now`: one card each, earliest
// start first, or one summary when there are more than MAX_SEPARATE. Events
// that are over or gone from the export are dropped.
function heldNotes(data, held, now) {
    var items = [];
    held.forEach(function (h) {
        var e = findOccurrence(data, h.key, now);
        if (e && now < endOf(e))
            items.push({ event: e, late: now - parseLocal(h.at) >= 60e3 });
    });
    items.sort(function (a, b) {
        return a.event.start - b.event.start;
    });
    if (items.length <= MAX_SEPARATE)
        return items.map(function (i) {
            return reminderNote(i.event, now, i.late);
        });
    var closeAt = new Date(Math.max.apply(null, items.map(function (i) {
        return Math.max(i.event.start.getTime(), now.getTime());
    })) + CARD_AFTER_START_MIN * 60e3);
    return [{
        key: "",
        day: ymd(items[0].event.start < now ? now : items[0].event.start),
        summary: items.length + " calendar reminders",
        body: capped(items.map(function (i) {
            return escape(i.event.title + " · " + (i.event.allDay ? allDayText(i.event, now) : whenText(i.event, now, true)));
        })).join("\n"),
        closeAt: closeAt
    }];
}

// One minute's work. `state` is what the last call returned (or {}):
// { fired: { fireId: end stamp }, held: [{ key, at }], digest: day done,
// digestPending: day waiting }. `fullscreen` holds everything; `startup` is
// true on the first call after the shell started. Returns { state, send },
// `send` being cards in the order to send them, the digest first.
function plan(data, state, now, fullscreen, startup) {
    var s = {
        fired: {},
        held: (state.held || []).slice(),
        digest: state.digest || "",
        digestPending: state.digestPending || ""
    };
    var horizon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - PRUNE_DAYS, now.getHours(), now.getMinutes());
    var fired = state.fired || {};
    for (var id in fired)
        if (parseLocal(fired[id]) >= horizon)
            s.fired[id] = fired[id];

    var today = ymd(now);
    if (s.digest !== today && (startup || now.getHours() >= DIGEST_HOUR)) {
        s.digest = today;
        s.digestPending = today;
    }

    dueReminders(data, now, s.fired).forEach(function (r) {
        s.fired[fireId(r.key, r.at)] = stamp(endOf(r.event));
        s.held = s.held.filter(function (h) {
            return h.key !== r.key;
        }).concat([{ key: r.key, at: stamp(r.at) }]);
    });

    var send = [];
    if (!fullscreen) {
        if (s.digestPending !== "") {
            var d = digest(data, parseLocal(s.digestPending), now);
            if (d)
                send.push(d);
            s.digestPending = "";
        }
        send = send.concat(heldNotes(data, s.held, now));
        s.held = [];
    }
    return { state: s, send: send };
}

if (typeof module !== "undefined")
    module.exports = {
        DEFAULT_LEAD_MIN: DEFAULT_LEAD_MIN,
        DEFAULT_ALL_DAY_TIME: DEFAULT_ALL_DAY_TIME,
        reminderTimes: reminderTimes,
        occurrenceKey: occurrenceKey,
        dueReminders: dueReminders,
        reminderNote: reminderNote,
        digest: digest,
        heldNotes: heldNotes,
        plan: plan,
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
