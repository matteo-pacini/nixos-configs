"""Write the calendar panel's export file from a synced vdir.

Usage: calendar-export VDIR WORKDIR KHAL_CONFIG OUT

VDIR is pimsync's vdir and is only read. WORKDIR/vdir becomes a derived copy
of it in which GMT+hhmm-style time zones get a fixed-offset VTIMEZONE; the
khal config must point its calendars at WORKDIR/vdir/* and set
local_timezone, the zone of every time in the export. OUT is replaced
atomically with the export described in the Calendar events section of the
Hyprland README. CALENDAR_NOW (ISO 8601 with offset) overrides the current
time, for tests.
"""

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import icalendar
import pytz
from icalendar.timezone.windows_to_olson import WINDOWS_TO_OLSON

# khal resolves zones through icalendar in pytz mode; checking in the same
# mode is what makes "unresolved" here mean the same as khal's fallback.
icalendar.use_pytz()

KHAL = "@khal@"
FIELDS = [
    "start",
    "end",
    "all-day",
    "title",
    "calendar",
    "calendar-color",
    "uid",
    "cancelled",
    "location",
]
# Bump when the rewrite below changes, so stale derived files are rebuilt.
COPY_FORMAT = "1"

GMT_TZID = re.compile(r"^GMT([+-])(\d\d)(\d\d)$")
TZID_PARAM = re.compile(r';TZID="?([^";:]+)"?[;:]')
VTIMEZONE_TZID = re.compile(r"^TZID:(.*?)\r?$", re.M)
BEGIN_VEVENT = re.compile(r"^BEGIN:VEVENT\r?$", re.M)


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text)


def fixed_offset_vtimezone(tzid, newline):
    """A VTIMEZONE for GMT+hhmm: the sign means east of UTC, as the
    producers of these IDs use it (GMT+0100 in winter, GMT+0200 in summer for
    Central European events)."""
    sign, hh, mm = GMT_TZID.match(tzid).groups()
    offset = f"{sign}{hh}{mm}"
    return newline.join(
        [
            "BEGIN:VTIMEZONE",
            f"TZID:{tzid}",
            "BEGIN:STANDARD",
            "DTSTART:16010101T000000",
            f"TZOFFSETFROM:{offset}",
            f"TZOFFSETTO:{offset}",
            f"TZNAME:{tzid}",
            "END:STANDARD",
            "END:VTIMEZONE",
            "",
        ]
    )


def derive(text):
    """The .ics text with a VTIMEZONE added for every GMT+hhmm TZID that has
    none. Every other byte is kept."""
    unfolded = unfold(text)
    defined = set(VTIMEZONE_TZID.findall(unfolded))
    missing = sorted(
        {t for t in TZID_PARAM.findall(unfolded) if GMT_TZID.match(t)} - defined
    )
    first_event = BEGIN_VEVENT.search(text)
    if not missing or not first_event:
        return text
    newline = "\r\n" if "\r\n" in text else "\n"
    block = "".join(fixed_offset_vtimezone(t, newline) for t in missing)
    at = first_event.start()
    return text[:at] + block + text[at:]


def mirror(src_root, dst_root):
    """Bring dst_root in line with src_root, rewriting .ics files through
    derive(). A file is rewritten only when its source mtime changed, and the
    copy keeps the source mtime, so khal re-indexes only what pimsync changed.

    khal rescans a calendar only when its directory's mtime changes, so a
    rewrite goes through a new file and a rename, which changes it; writing
    in place would leave an edited event stale in khal's kept database.

    An .ics that does not decode as UTF-8 or does not parse as iCalendar is
    left out of dst_root (its old copy removed), so neither khal nor the
    readers below meet it. Returns how many were left out."""
    skipped = 0
    stamp = dst_root / ".format"
    if dst_root.exists() and (
        not stamp.exists() or stamp.read_text() != COPY_FORMAT
    ):
        shutil.rmtree(dst_root)
    dst_root.mkdir(parents=True, exist_ok=True)
    stamp.write_text(COPY_FORMAT)

    src_cals = {p.name for p in src_root.iterdir() if p.is_dir()}
    for p in dst_root.iterdir():
        if p.is_dir() and p.name not in src_cals:
            shutil.rmtree(p)
    for name in src_cals:
        src, dst = src_root / name, dst_root / name
        dst.mkdir(exist_ok=True)
        src_files = {p.name: p for p in src.iterdir() if p.is_file()}
        for p in dst.iterdir():
            if p.name not in src_files:
                p.unlink()
        for fname, sp in src_files.items():
            dp = dst / fname
            st = sp.stat()
            if dp.exists() and dp.stat().st_mtime_ns == st.st_mtime_ns:
                continue
            tmp = dst / f".{fname}.tmp"
            if fname.endswith(".ics"):
                try:
                    text = derive(sp.read_bytes().decode("utf-8"))
                    icalendar.Calendar.from_ical(text)
                except ValueError:
                    dp.unlink(missing_ok=True)
                    skipped += 1
                    continue
                tmp.write_bytes(text.encode("utf-8"))
            else:
                tmp.write_bytes(sp.read_bytes())
            os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))
            os.replace(tmp, dp)
    return skipped


def known_tzid(tzid):
    return tzid in pytz.all_timezones_set or tzid in WINDOWS_TO_OLSON


def unresolved_uids(root):
    """UIDs of events whose DTSTART or DTEND khal will read in the local zone
    because their TZID resolves to nothing."""
    uids = set()
    for f in root.glob("*/*.ics"):
        text = f.read_bytes().decode("utf-8")
        unfolded = unfold(text)
        defined = set(VTIMEZONE_TZID.findall(unfolded))
        if all(
            t in defined or known_tzid(t) for t in TZID_PARAM.findall(unfolded)
        ):
            continue
        for ev in icalendar.Calendar.from_ical(text).walk("VEVENT"):
            for prop in ("DTSTART", "DTEND"):
                v = ev.get(prop)
                if (
                    v is not None
                    and isinstance(v.dt, dt.datetime)
                    and v.dt.tzinfo is None
                    and "TZID" in v.params
                ):
                    uids.add(str(ev.get("UID")))
    return uids


def local_zone(khal_config):
    """The zone khal prints times in: its config's local_timezone."""
    m = re.search(r"^\s*local_timezone\s*=\s*(\S+)", khal_config.read_text(), re.M)
    if not m:
        sys.exit("calendar-export: the khal config has no local_timezone")
    return pytz.timezone(m.group(1))


def khal_time(prop, tz):
    """A DTSTART as khal prints it: local wall clock, or the date if all-day.
    A naive time (floating, or a TZID khal cannot resolve) is printed as is."""
    v = prop.dt
    if not isinstance(v, dt.datetime):
        return v.isoformat()
    if v.tzinfo is not None:
        v = v.astimezone(tz)
    return v.strftime("%Y-%m-%d %H:%M")


def alarm_specs(event):
    """The event's own DISPLAY and AUDIO alarms as (kind, base, interval,
    repeat): kind "start" or "end" with a timedelta base, or "absolute" with
    an aware UTC datetime."""
    specs = []
    for alarm in event.subcomponents:
        if alarm.name != "VALARM":
            continue
        if str(alarm.get("ACTION", "")).upper() not in ("DISPLAY", "AUDIO"):
            continue
        trigger = alarm.get("TRIGGER")
        if trigger is None:
            continue
        repeat, interval = int(alarm.get("REPEAT", 0)), alarm.get("DURATION")
        interval = interval.dt if interval is not None and repeat else None
        base = trigger.dt
        if isinstance(base, dt.datetime):
            # RFC 5545 requires UTC here; a time without one is read as UTC.
            if base.tzinfo is None:
                base = base.replace(tzinfo=dt.timezone.utc)
            specs.append(("absolute", base, interval, repeat if interval else 0))
        elif isinstance(base, dt.timedelta):
            kind = "end" if trigger.params.get("RELATED", "START").upper() == "END" else "start"
            specs.append((kind, base, interval, repeat if interval else 0))
    return specs


def alarm_index(root, tz):
    """{(calendar name, UID): (master specs, {override start: specs})}, for
    files that contain a VALARM. Overrides are keyed by their own DTSTART as
    khal prints it, which is what identifies them among khal's occurrences."""
    index = {}
    for d in root.iterdir():
        if not d.is_dir():
            continue
        name_file = d / "displayname"
        cal = name_file.read_text().strip() if name_file.exists() else d.name
        for f in d.glob("*.ics"):
            text = f.read_bytes().decode("utf-8")
            if "BEGIN:VALARM" not in text:
                continue
            for ev in icalendar.Calendar.from_ical(text).walk("VEVENT"):
                master, overrides = index.setdefault((cal, str(ev.get("UID"))), ([], {}))
                if ev.get("RECURRENCE-ID") is None:
                    master.extend(alarm_specs(ev))
                elif ev.get("DTSTART") is not None:
                    overrides[khal_time(ev["DTSTART"], tz)] = alarm_specs(ev)
    return index


def occurrence_alarms(entry, specs, tz):
    """Firing times, local "YYYY-MM-DD HH:MM", of specs for the occurrence
    khal printed as entry, sorted and without duplicates.

    Relative triggers are added to the occurrence's local wall-clock start or
    end, so "1 day before" keeps its hour across a DST change. An all-day
    occurrence starts at local midnight of its first day and ends at
    midnight after its last (khal's all-day end is inclusive)."""
    if entry["all-day"] == "True":
        start = dt.datetime.fromisoformat(entry["start"])
        end = dt.datetime.fromisoformat(entry["end"]) + dt.timedelta(days=1)
    else:
        start = dt.datetime.strptime(entry["start"], "%Y-%m-%d %H:%M")
        end = dt.datetime.strptime(entry["end"], "%Y-%m-%d %H:%M")
    times = set()
    for kind, base, interval, repeat in specs:
        for k in range(repeat + 1):
            step = interval * k if interval else dt.timedelta(0)
            if kind == "absolute":
                t = (base + step).astimezone(tz)
            else:
                t = (start if kind == "start" else end) + base + step
            times.add(t.strftime("%Y-%m-%d %H:%M"))
    return sorted(times)


def window(today):
    """First day of the month three months back to the last day of the month
    twelve months ahead."""
    m = today.year * 12 + today.month - 1
    start_m, end_m = m - 3, m + 13
    start = dt.date(start_m // 12, start_m % 12 + 1, 1)
    end = dt.date(end_m // 12, end_m % 12 + 1, 1) - dt.timedelta(days=1)
    return start, end


def calendar_order(root):
    """Display names in the server's order (pimsync's `order` file), then by
    directory name for calendars without one."""
    cals = []
    for d in root.iterdir():
        if not d.is_dir():
            continue
        name_file, order_file = d / "displayname", d / "order"
        name = name_file.read_text().strip() if name_file.exists() else d.name
        try:
            order = int(order_file.read_text().strip())
        except (FileNotFoundError, ValueError):
            order = None
        cals.append((order is None, order or 0, d.name, name))
    return [name for *_, name in sorted(cals)]


def main():
    vdir, workdir, khal_config, out = map(Path, sys.argv[1:5])
    now_env = os.environ.get("CALENDAR_NOW")
    now = (
        dt.datetime.fromisoformat(now_env)
        if now_env
        else dt.datetime.now().astimezone()
    ).replace(microsecond=0)

    derived = workdir / "vdir"
    skipped = mirror(vdir, derived)
    if skipped:
        # A count only: a file's name or text can carry event details.
        print(f"calendar-export: .ics files skipped (not UTF-8 or not iCalendar): {skipped}",
              file=sys.stderr)
    bad = unresolved_uids(derived)
    tz = local_zone(khal_config)
    alarms = alarm_index(derived, tz)

    start, end = window(now.date())
    days = (end - start).days + 1
    cmd = [KHAL, "-c", str(khal_config), "list"]
    for f in FIELDS:
        cmd += ["--json", f]
    cmd += [start.isoformat(), end.isoformat()]
    lines = subprocess.run(
        cmd, check=True, stdout=subprocess.PIPE, text=True
    ).stdout.splitlines()
    if len(lines) != days:
        sys.exit(f"calendar-export: khal printed {len(lines)} days, expected {days}")

    day_lists = [json.loads(line) for line in lines]
    colors = {}
    for events in day_lists:
        for e in events:
            e["tz-unresolved"] = "True" if e["uid"] in bad else "False"
            master, overrides = alarms.get((e["calendar"], e["uid"]), ([], {}))
            specs = overrides.get(e["start"], master)
            e["alarms"] = occurrence_alarms(e, specs, tz)
            colors.setdefault(e["calendar"], e["calendar-color"])

    header = {
        "version": 1,
        "window_start": start.isoformat(),
        "days": days,
        "generated": now.isoformat(),
        "calendars": [
            {"name": n, "color": colors[n]}
            for n in calendar_order(derived)
            if n in colors
        ],
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(f".{out.name}.tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        fh.write(json.dumps(header, ensure_ascii=False) + "\n")
        for events in day_lists:
            fh.write(json.dumps(events, ensure_ascii=False) + "\n")
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
