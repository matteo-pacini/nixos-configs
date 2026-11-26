#!/usr/bin/env python3
"""Fakes and stubs for desk-nest: every command the shell runs that would
reach outside the nest, as one program chosen by the name it is run as
(bin/ holds one symlink here per name).

Fakes answer in the protocol their panel expects, replaying the fixtures
the panel tests already use (tests/<panel>-panel/fixtures) or nest's own
(nest/fixtures; the demo-* ones in nest/fixtures/<panel>/, invented data
for a recorded tour). Stubs append the call to the log and act on nothing.
Wrappers (gdbus, hyprctl, ip) answer some calls themselves and hand the
rest to the real tool, which inside the nest reaches only the nest.
Nothing here opens a network connection or talks to a system service.

Environment:
  NEST_STATE     the nest's state directory: control/<panel> (the fixture
                 name chosen for a panel), fakes.log (every call, every
                 switch), home/ (the private XDG homes)
  NEST_FIXTURES  nest/fixtures of the checkout; tests/ is found beside
                 nest/ (NEST_FIXTURES/../../tests). Default: this file's
                 ../fixtures

Fixture names, and each panel's default (its first line), are in
nest/fixtures/index. A running fake reads control/<panel> twice a second
and replays a new fixture over the panel's state, as a real helper's
events would arrive; a fake started later (every reload starts the
helpers again) begins with it.

Two names are commands for the launcher, not for the shell:
  nest-place <panel> <name>   on the host: writes the data file the shell
                              reads itself (calendar export, plan-limit
                              file, a demo tailnet's mesh hosts) into
                              NEST_STATE/home, times moved to now
  nest-notify <name>          inside the nest: sends that sample's
                              notifications over the session bus
"""
import calendar
import json
import os
import re
import subprocess
import sys
import threading
import time

NAME = os.path.basename(sys.argv[0])
ARGS = sys.argv[1:]
SELF = os.path.realpath(__file__)
STATE = os.environ.get("NEST_STATE") or "/nonexistent"
FIXTURES = os.path.realpath(os.environ.get("NEST_FIXTURES") or os.path.join(os.path.dirname(SELF), "..", "fixtures"))
TESTS = os.path.join(os.path.dirname(os.path.dirname(FIXTURES)), "tests")
out_lock = threading.Lock()


def log(msg):
    try:
        with open(os.path.join(STATE, "fakes.log"), "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {NAME} {msg}\n")
    except OSError:
        pass


def emit(obj_or_line):
    line = obj_or_line if isinstance(obj_or_line, str) else json.dumps(obj_or_line)
    with out_lock:
        try:
            sys.stdout.write(line.rstrip("\n") + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            os._exit(0)


def index():
    """{panel: [(name, flag)]} from nest/fixtures/index, defaults first."""
    panels = {}
    with open(os.path.join(FIXTURES, "index")) as f:
        for line in f:
            words = line.split("#", 1)[0].split()
            if len(words) >= 2:
                flag = words[2] if len(words) > 2 and words[2] in ("place", "inside") else None
                panels.setdefault(words[0], []).append((words[1], flag))
    return panels


def default(panel):
    return index()[panel][0][0]


def control(panel):
    try:
        with open(os.path.join(STATE, "control", panel)) as f:
            return f.read().strip() or default(panel)
    except OSError:
        return default(panel)


def watch(panel, on_change):
    """Calls on_change(name) whenever control/<panel> names a new fixture."""
    def loop():
        cur = control(panel)
        while True:
            time.sleep(0.5)
            new = control(panel)
            if new != cur:
                cur = new
                log(f"fixture {panel} -> {new}")
                on_change(new)
    threading.Thread(target=loop, daemon=True).start()


def read_lines(path):
    with open(path) as f:
        return [l for l in f.read().splitlines() if l.strip()]


def stdin_lines(handle):
    for line in sys.stdin:
        line = line.rstrip("\n")
        log(f"stdin {line}")
        handle(line)
    log("stdin closed, exiting")


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


def real(cmd):
    """The first `cmd` on PATH that is not this program."""
    for d in os.environ.get("PATH", "").split(":"):
        p = os.path.join(d, cmd)
        if d and os.access(p, os.X_OK) and os.path.realpath(p) != SELF:
            return p
    print(f"{NAME}: no real {cmd} on PATH", file=sys.stderr)
    sys.exit(127)


def days_to_today(y, m, d):
    """Whole days from that date to today, local time."""
    t = time.localtime()
    return (calendar.timegm((t.tm_year, t.tm_mon, t.tm_mday, 12, 0, 0)) -
            calendar.timegm((y, m, d, 12, 0, 0))) // 86400


def shift_date(text, days):
    y, m, d = map(int, text.split("-"))
    return time.strftime("%Y-%m-%d", time.gmtime(calendar.timegm((y, m, d, 12, 0, 0)) + 86400 * days))


# Demo fixtures, named demo-*, are nest's own (nest/fixtures/<panel>/), with
# invented data written for this moment: Wednesday 25 November 2026, 09:41
# in London (GMT, so also UTC). Their times move by now - DEMO_AT, as the
# test fixtures' do from their own moments.
DEMO_DAY = (2026, 11, 25)
DEMO_AT = calendar.timegm(DEMO_DAY + (9, 41, 0))


def fixture_file(panel, name, ext):
    """A fixture's file: nest/fixtures/<panel>/ for a demo-* name, else the
    panel test's own fixtures (tests/<panel>-panel/fixtures)."""
    if name.startswith("demo-"):
        return f"{FIXTURES}/{panel}/{name}{ext}"
    return f"{TESTS}/{panel}-panel/fixtures/{name}{ext}"


def shift_iso(text, delta):
    """Every ISO time of this century in `text` (2026-11-25T09:41:00Z, with
    or without fraction) moved by `delta` seconds."""
    def shift(m):
        t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) + float("0" + (m.group(2) or ""))
        return iso(t + delta)
    return re.sub(r'(20\d\d-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?Z', shift, text)


# ---- weather (desk-weather) -------------------------------------------------

# The day the weather-panel fixtures' "date" fields were written for.
WEATHER_DAY = (2026, 11, 22)


def weather_lines(names, only=None):
    now = int(time.time())
    out = []
    for n in names.split("+"):
        shift = days_to_today(*(DEMO_DAY if n.startswith("demo-") else WEATHER_DAY))
        for l in read_lines(fixture_file("weather", n, ".jsonl")):
            m = re.search(r'"event":"([a-z_]+)"', l)
            if only and not (m and m.group(1) in only):
                continue
            l = re.sub(r'"@([+-]\d+)"', lambda m: str(now + int(m.group(1))), l)
            l = re.sub(r'"date":"(\d{4}-\d\d-\d\d)"', lambda m: '"date":"%s"' % shift_date(m.group(1), shift), l)
            if '"@radar/' in l:
                l = demo_radar(n, l)
            out.append(l)
    return out


# ---- demo radar frames ------------------------------------------------------
# A demo radar line names its frames "@radar/fNN". The tiles are drawn here
# from nest/fixtures/weather/<fixture>.radar.json (rain cells in the block's
# pixels at the newest frame, moving `motion` pixels a frame), in RainViewer's
# colour scheme 2 as the helper fetches it, into the private cache once per
# fixture. The frames' "dry" is worked out as the helper does: any echo in
# the panel's 390 x 250 view around the centre.

RADAR_COLOURS = [  # (lowest dBZ, RGBA)
    (12, (136, 221, 238, 200)), (18, (0, 153, 204, 210)), (24, (0, 119, 170, 220)), (30, (0, 85, 136, 225)),
    (36, (255, 238, 0, 230)), (42, (255, 170, 0, 235)), (48, (255, 112, 0, 240)), (54, (255, 68, 0, 240)),
]


def png(width, rows):
    import struct
    import zlib

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\0" + bytes(r) for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, len(rows), 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def demo_radar(name, line):
    import math
    import random
    ev = json.loads(line)
    with open(f"{FIXTURES}/weather/{name}.radar.json") as f:
        spec = json.load(f)
    root = os.path.join(STATE, "home", "cache", "desk-weather", "demo-radar", name)
    tile, cols, rows, x0, y0 = ev["tile"], ev["cols"], ev["rows"], ev["x0"], ev["y0"]
    cx, cy = ev["centre"]
    vl = max(0, min(cx - 195, cols * tile - 390))
    vt = max(0, min(cy - 125, rows * tile - 250))
    rnd = random.Random(spec.get("seed", 1))
    lattice = [[rnd.random() for _ in range(80)] for _ in range(80)]

    def value(x, y, cell):  # value noise on a `cell` px lattice, in 0..1
        gx, gy = x / cell + 1000, y / cell + 1000
        ix, iy = int(gx) % 79, int(gy) % 79
        fx, fy = gx - int(gx), gy - int(gy)
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = lattice[iy][ix] * (1 - fx) + lattice[iy][ix + 1] * fx
        b = lattice[iy + 1][ix] * (1 - fx) + lattice[iy + 1][ix + 1] * fx
        return a * (1 - fy) + b * fy

    def noise(x, y):  # three octaves: banks, cells, speckle
        return 0.5 * value(x, y, 24) + 0.3 * value(x + 37, y + 11, 10) + 0.2 * value(x + 5, y + 71, 4)

    blank = None
    frames = ev["frames"]
    for k, fr in enumerate(frames):
        d = os.path.join(root, fr["dir"].split("/", 1)[1])
        fr["dir"] = d
        if os.path.isfile(d + ".dry"):
            with open(d + ".dry") as f:
                fr["dry"] = f.read() == "true"
            continue
        back = len(frames) - 1 - k
        mx, my = -spec["motion"][0] * back, -spec["motion"][1] * back
        px = {}
        for c in spec["cells"]:
            ccx, ccy = c["x"] + mx, c["y"] + my
            r = max(c["rx"], c["ry"]) * 1.6
            cos, sin = math.cos(math.radians(c.get("angle", 0))), math.sin(math.radians(c.get("angle", 0)))
            peak = c["peak"] + c.get("grow", 0) * -back
            for by in range(int(ccy - r) // 2 * 2, int(ccy + r) + 2, 2):
                for bx in range(int(ccx - r) // 2 * 2, int(ccx + r) + 2, 2):
                    dx, dy = bx - ccx, by - ccy
                    u, v = (dx * cos + dy * sin) / c["rx"], (-dx * sin + dy * cos) / c["ry"]
                    q = u * u + v * v
                    if q < 2.6:
                        px[(bx, by)] = max(px.get((bx, by), 0), peak * math.exp(-q) * (0.2 + 1.5 * noise(bx - mx, by - my)))
        os.makedirs(d, exist_ok=True)
        dry = True
        for tx in range(x0, x0 + cols):
            for ty in range(y0, y0 + rows):
                ox, oy = (tx - x0) * tile, (ty - y0) * tile
                grid = None
                for (bx, by), v in px.items():
                    if v < 12 or not (ox <= bx < ox + tile and oy <= by < oy + tile):
                        continue
                    if grid is None:
                        grid = [bytearray(tile * 4) for _ in range(tile)]
                    rgba = [c for lo, c in RADAR_COLOURS if v >= lo][-1]
                    if vl <= bx < vl + 390 and vt <= by < vt + 250:
                        dry = False
                    for yy in (by - oy, by - oy + 1):
                        for xx in (bx - ox, bx - ox + 1):
                            if yy < tile and xx < tile:
                                grid[yy][xx * 4:xx * 4 + 4] = bytes(rgba)
                if grid is None:
                    blank = blank or png(tile, [bytearray(tile * 4)] * tile)
                    data = blank
                else:
                    data = png(tile, grid)
                with open(os.path.join(d, f"{tx}_{ty}.png"), "wb") as f:
                    f.write(data)
        fr["dry"] = dry
        # Written last: a frame cut short by an exit is drawn again.
        put(d + ".dry", "true" if dry else "false")
    return json.dumps(ev)


def desk_weather():
    state = {"names": control("weather")}

    def play(names):
        state["names"] = names
        for l in weather_lines(names):
            emit(l)

    play(state["names"])
    watch("weather", play)

    def handle(line):
        try:
            c = json.loads(line)
        except ValueError:
            return
        if c.get("cmd") == "refresh":
            for l in weather_lines(state["names"], {"forecast", "air", "warnings"}):
                emit(l)
        elif c.get("cmd") == "radar" and c.get("on"):
            radar = weather_lines(state["names"], {"radar", "radar_error"})
            for l in radar or [json.dumps({"event": "radar_error", "at": int(time.time()), "reason": "network"})]:
                emit(l)
    stdin_lines(handle)


# ---- office (desk-mqtt) -----------------------------------------------------

def desk_mqtt():
    devices = {}

    def play(name):
        now = time.time()
        for l in read_lines(fixture_file("office", name, ".jsonl")):
            l = re.sub(r'"@-(\d+)"', lambda m: json.dumps(iso(now - int(m.group(1)))), l)
            try:
                ev = json.loads(l)
                if ev.get("event") == "device":
                    devices[ev["id"]] = ev
            except ValueError:
                pass
            emit(l)

    play(control("office"))
    watch("office", play)

    # A command is confirmed after 0.8 s and the device's values follow it,
    # so keys and clicks show their effect.
    def handle(line):
        try:
            c = json.loads(line)
        except ValueError:
            emit({"event": "bad-input", "line": line})
            return
        dev = devices.get(c.get("device"))
        emit({"event": "command", "id": c.get("id"), "state": "pending", "device": c.get("device"),
              "action": c.get("action"), **({"value": c["value"]} if "value" in c else {}), "at": iso(time.time())})

        def later():
            time.sleep(0.8)
            if dev and isinstance(dev.get("values"), dict):
                v = dict(dev["values"])
                a = c.get("action")
                if a in ("on", "off"):
                    v["state"] = a.upper()
                elif a == "brightness":
                    v["state"], v["brightness"] = "ON", c.get("value")
                elif a == "position":
                    v["position"] = c.get("value")
                elif a in ("open", "close"):
                    v["position"] = 100 if a == "open" else 0
                dev["values"] = v
                dev["received"] = iso(time.time())
                dev["retained"] = False
                emit(dev)
            emit({"event": "command", "id": c.get("id"), "state": "confirmed"})
        threading.Thread(target=later, daemon=True).start()
    stdin_lines(handle)
    emit({"event": "exit"})


# ---- fleet (desk-fleet) -----------------------------------------------------

# The moment the fleet-panel fixtures' times were written for.
FLEET_BASE = calendar.timegm((2026, 11, 16, 12, 0, 20))


def desk_fleet():
    def play(name):
        delta = time.time() - (DEMO_AT if name.startswith("demo-") else FLEET_BASE)

        def shift(m):
            t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) + float("0" + (m.group(2) or ""))
            return iso(t + delta)
        for l in read_lines(fixture_file("fleet", name, ".jsonl")):
            emit(re.sub(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?Z', shift, l))

    play(control("fleet"))
    watch("fleet", play)

    def handle(line):
        try:
            c = json.loads(line)
        except ValueError:
            emit({"event": "bad-input", "line": line})
            return
        cmd = c.get("cmd")
        if cmd == "refresh":
            play(control("fleet"))
        elif cmd in ("switch", "boot", "mode", "reboot", "diff", "ssh", "attach"):
            emit({"event": "action", "id": c.get("id"), "host": c.get("host"), "action": cmd,
                  "state": "refused", "reason": "read-only", "why": "desk-nest: nothing runs"})
    stdin_lines(handle)
    emit({"event": "exit"})


# ---- tokens (desk-tokens) ---------------------------------------------------

TOKEN_SETS = {
    "full": {"overview": "overview-full", "projects:today": "projects-today", "projects:7d": "projects-7d",
             "projects:30d": "projects-30d-not-ready", "project": "project-alpha-7d", "days": "days"},
    "partial": {"overview": "overview-partial", "projects:today": "projects-today-empty",
                "projects:7d": "projects-7d", "projects:30d": "projects-30d-not-ready",
                "project": "project-alpha-7d", "days": "days-dst"},
    "demo-week": {"overview": "demo-overview", "projects:today": "demo-projects-today", "projects:7d": "demo-projects-7d",
                  "projects:30d": "demo-projects-30d", "project": "demo-project-7d", "days": "demo-days"},
}


def token_answer(name):
    with open(fixture_file("tokens", name, ".json")) as f:
        a = json.load(f)
    if not name.startswith("demo-"):
        return a
    # Whole days, so the helper's day bounds stay on their hour.
    days = days_to_today(*DEMO_DAY) * 86400

    def mv(x):
        if isinstance(x, dict):
            return {k: mv(v) for k, v in x.items()}
        if isinstance(x, list):
            return [mv(v) for v in x]
        return x + days if isinstance(x, int) and not isinstance(x, bool) and 1.7e9 < x < 1.9e9 else x
    return mv(a)


def desk_tokens():
    def progress():
        o = token_answer(TOKEN_SETS[control("tokens")]["overview"])
        p = o.get("progress") or {"state": "done", "files_read": 3, "files_total": 3, "bytes_read": 1, "bytes_total": 1,
                                  "ready": {"today": True, "7d": True, "14d": True, "30d": True, "all": True}}
        emit(dict(p, event="progress", now=o.get("now")))

    progress()
    watch("tokens", lambda name: progress())

    def handle(line):
        try:
            r = json.loads(line)
        except ValueError:
            emit({"event": "bad-input"})
            return
        req = r.get("req")
        s = TOKEN_SETS[control("tokens")]
        if req == "refresh":
            emit({"answer": "refresh", "id": r.get("id")})
            progress()
            return
        key = f"projects:{r.get('period')}" if req == "projects" else req
        if key not in s:
            emit({"event": "bad-input"})
            return
        a = token_answer(s[key])
        a["id"] = r.get("id")
        emit(a)
    stdin_lines(handle)


# ---- tailscale --------------------------------------------------------------

def tailscale():
    name = control("tailscale")
    fx = f"{TESTS}/tailscale-panel/fixtures"
    if name.startswith("demo-"):
        with open(fixture_file("tailscale", name, ".json")) as f:
            status = json.loads(shift_iso(f.read(), time.time() - DEMO_AT))
        if "--peers=false" in ARGS:
            status.pop("Peer", None)
        print(json.dumps(status))
        return

    def load(n):
        with open(f"{fx}/{n}.json") as f:
            return json.load(f)
    if name.startswith("call:"):
        c = load("calls")[name[5:]]
        if c.get("timedOut"):
            time.sleep(60)
        sys.stdout.write(c["stdout"] if isinstance(c["stdout"], str) else json.dumps(c["stdout"]))
        sys.stderr.write(c.get("stderr", ""))
        sys.exit(c.get("exit", 0))
    if name.startswith("overlay:"):
        status = load("running")
        for k, v in load("overlays")[name[8:]].items():
            status[k] = dict(status["Self"], **v["Self"]) if k == "Self" else v
    elif name.startswith("state:"):
        status = load("states")[name[6:]]
    else:
        status = load(name)
    if "--peers=false" in ARGS:
        status.pop("Peer", None)
    print(json.dumps(status))


# ---- network: nmcli and ip --------------------------------------------------

def nmcli():
    if control("network") == "wired":
        with open(f"{FIXTURES}/network/nmcli-device-show.txt") as f:
            sys.stdout.write(f.read())


def ip():
    if ARGS == ["-j", "route", "show", "default"]:
        if control("network") == "wired":
            with open(f"{FIXTURES}/network/route-default.json") as f:
                sys.stdout.write(f.read())
        else:
            print("[]")
        return
    p = real("ip")
    os.execv(p, [p] + ARGS)


# ---- bluetooth agent --------------------------------------------------------

def desk_bt_agent():
    # No BlueZ in the nest: the agent says it is ready, then only logs what
    # the panel answers.
    emit({"event": "ready", "capability": "KeyboardDisplay"})
    stdin_lines(lambda line: None)
    emit({"event": "exit"})


# ---- wrappers ---------------------------------------------------------------

SLEEP_LINE = "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (%s,)"


def gdbus():
    if "--system" not in ARGS:
        p = real("gdbus")
        os.execv(p, [p] + ARGS)
    # No system bus in the nest. The logind monitor stays quiet, or says
    # PrepareForSleep while the lock fixture is "sleep", instead of failing
    # and being restarted every 5 s.
    log("system bus call held: " + " ".join(ARGS))
    if "monitor" not in ARGS:
        sys.exit(1)
    said = False
    while True:
        s = control("lock") == "sleep"
        if s != said:
            emit(SLEEP_LINE % ("true" if s else "false"))
            said = s
        time.sleep(0.5)


def hyprctl():
    sheet = control("cheatsheet")
    if "binds" in ARGS and (sheet == "host" or sheet.startswith("demo-")):
        with open(f"{FIXTURES}/cheatsheet/{sheet}.json" if sheet != "host" else f"{FIXTURES}/binds.json") as f:
            sys.stdout.write(f.read())
        return
    p = real("hyprctl")
    os.execv(p, [p] + ARGS)


# ---- stubs ------------------------------------------------------------------

def systemctl():
    log("stub: " + " ".join(ARGS))
    if "is-active" in ARGS:
        print("inactive")
        sys.exit(3)


def systemd_run():
    # The lock is the launcher's (`desk-nest lock`); the shell's own start
    # of it is refused as a second lock would be.
    log("stub: " + " ".join(ARGS))
    print("desk-nest: systemd-run is a stub; the lock starts with `desk-nest lock`", file=sys.stderr)
    sys.exit(1)


def systemd_inhibit():
    # Keeps the shell's contract (runs the trailing command, `cat`, whose
    # stdin the shell holds open) without asking logind for anything.
    log("stub: " + " ".join(ARGS))
    rest = [a for a in ARGS if not a.startswith("--")]
    if rest:
        os.execvp(rest[0], rest)


def speed():
    log("stub: " + " ".join(ARGS))
    print("desk-nest: no network in the nest", file=sys.stderr)
    sys.exit(1)


def pw_dump():
    log("stub: " + " ".join(ARGS))
    print("[]")


def plain_stub():
    log("stub: " + " ".join(ARGS))


# ---- launcher commands ------------------------------------------------------

def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


# The day tests/calendar/panel/fixture-events.jsonl was generated on.
CALENDAR_DAY = (2026, 11, 15)


def place_calendar(name, home):
    path = f"{home}/cache/desk/calendar/events.jsonl"
    put(f"{home}/data/desk/calendar/url", "https://dav.example.org/remote.php/dav/\n")
    put(f"{home}/data/desk/calendar/source.json", json.dumps({"url_file": f"{home}/data/desk/calendar/url"}) + "\n")
    if name == "none":
        if os.path.exists(path):
            os.remove(path)
        return
    demo = name.startswith("demo-")
    with open(f"{FIXTURES}/calendar/{name}.jsonl" if demo else f"{TESTS}/calendar/panel/fixture-events.jsonl") as f:
        text = f.read()
    if name == "today" or demo:
        days = days_to_today(*(DEMO_DAY if demo else CALENDAR_DAY))
        text = re.sub(r"(?<!\d)(\d{4}-\d\d-\d\d)(?!\d)", lambda m: shift_date(m.group(1), days), text)
    put(path, text)


def place_limits(name, home):
    with open(f"{FIXTURES}/limits/{name}.json" if name.startswith("demo-")
              else f"{TESTS}/tokens-panel/fixtures/limits-{name}.json") as f:
        d = json.load(f)
    delta = int(time.time()) - 60 - d["written_at"]

    def mv(x):
        if isinstance(x, dict):
            return {k: v + delta if k in ("written_at", "resets_at", "evidence_at") and isinstance(v, int) else mv(v)
                    for k, v in x.items()}
        return x
    put(f"{home}/runtime/desk/claude-limits.json", json.dumps(mv(d)) + "\n")


def place_tailscale(name, home):
    # A demo tailnet's mesh hosts (Tailscale.qml reads them on every open);
    # the status itself is the tailscale fake's, from control/tailscale.
    with open(f"{FIXTURES}/tailscale/demo-mesh-hosts.json") as f:
        put(f"{home}/data/desk/tailscale/hosts.json", f.read())


PLACE = {"calendar": place_calendar, "limits": place_limits, "tailscale": place_tailscale}


def known(panel, name, flag):
    if (name, flag) not in index().get(panel, []):
        print(f"{NAME}: no {flag} fixture {panel} {name} in {FIXTURES}/index", file=sys.stderr)
        sys.exit(2)


def nest_place():
    if len(ARGS) != 2 or ARGS[0] not in PLACE or STATE == "/nonexistent":
        print("usage: NEST_STATE=<dir> nest-place calendar|limits|tailscale <name>", file=sys.stderr)
        sys.exit(2)
    known(ARGS[0], ARGS[1], "place")
    PLACE[ARGS[0]](ARGS[1], os.path.join(STATE, "home"))
    log(f"placed {ARGS[0]} {ARGS[1]}")


def nest_notify():
    if len(ARGS) != 1:
        print("usage: nest-notify <name>", file=sys.stderr)
        sys.exit(2)
    known("notifications", ARGS[0], "inside")
    with open(f"{FIXTURES}/notifications/{ARGS[0]}.json") as f:
        notes = json.load(f)
    for n in notes:
        subprocess.run([real("gdbus"), "call", "--session", "--dest", "org.freedesktop.Notifications",
                        "--object-path", "/org/freedesktop/Notifications", "--method",
                        "org.freedesktop.Notifications.Notify", n["app"], "0", n["icon"], n["summary"], n["body"],
                        "[]", "{'urgency': <byte %d>}" % n["urgency"], "int32 -1"], check=True)
    log(f"sent {len(notes)} notifications ({ARGS[0]})")


FAKES = {
    "desk-weather": desk_weather, "desk-mqtt": desk_mqtt, "desk-fleet": desk_fleet,
    "desk-tokens": desk_tokens, "tailscale": tailscale, "nmcli": nmcli, "ip": ip,
    "desk-bt-agent": desk_bt_agent, "gdbus": gdbus, "hyprctl": hyprctl,
    "systemctl": systemctl, "systemd-run": systemd_run, "systemd-inhibit": systemd_inhibit,
    "cfspeedtest": speed, "speedtest": speed, "pw-dump": pw_dump,
    "nest-place": nest_place, "nest-notify": nest_notify,
}
# Started by the shell, or by what it starts (`uwsm app -- xdg-open`,
# ghostty's ssh), or by the helpers it replaces.
STUBS = ("uwsm", "xdg-open", "loginctl", "playerctl", "audio-output-cycle", "pw-top", "notify-send",
         "comin-deploy", "wpctl", "pactl", "ghostty", "ssh", "gh", "tmux", "sudo", "reboot",
         "poweroff")
# Called often and logged by their own code paths when it matters.
QUIET = ("gdbus", "hyprctl", "ip", "systemctl", "systemd-run", "systemd-inhibit", "nest-place", "nest-notify")

# ---- demo stand-ins (desk-nest up --demo; nest/services) ------------------------

# The system panel's free-space call, answered for the invented machine
# whose sysfs and procfs a demo binds in: one filesystem, so /home and
# /mnt/games report / as df does for a path that is no mount point, and the
# panel shows one row (three do not fit at 1600x900). Anything else, and
# any df outside a demo, is the real df.
DF_CALL = ["-B1", "--output=target,size,used", "/", "/home", "/mnt/games"]


def df():
    if os.environ.get("NEST_DEMO") and ARGS == DF_CALL:
        sys.stdout.write("Mounted on     1B-blocks         Used\n" + "/          1999843033088 812896526336\n" * 3)
        return
    p = real("df")
    os.execv(p, [p] + ARGS)


FAKES["df"] = df


# The audio panel's PipeWire tools: in a demo they reach the nest's own
# PipeWire (nest/services), outside one they stay stubs.
def pipewire_tool():
    if os.environ.get("NEST_DEMO"):
        p = real(NAME)
        os.execv(p, [p] + ARGS)
    if NAME == "pw-dump":
        pw_dump()
    else:
        plain_stub()


for _name in ("pw-dump", "pw-top", "wpctl"):
    FAKES[_name] = pipewire_tool

# The network panel's speed test (network/SpeedTest.qml), played in a demo:
# about nine seconds, latency, then download, then upload, in the tool's own
# output, ending 941 / 512 Mb/s and 7 ms. The panel stores the result itself.
# Outside a demo the stub's refusal. Nothing here touches the network.
SPEED_DOWN = [(p, r) for p, rates in (("100kB", (212.4, 268.9, 301.7, 286.2)), ("1MB", (511.8, 577.3, 602.6, 588.1)),
                                      ("10MB", (781.5, 826.9, 849.3, 860.2)), ("25MB", (902.7, 917.4, 925.8)),
                                      ("100MB", (938.6, 943.9, 941.2))) for r in rates]
SPEED_UP = [(p, r) for p, rates in (("100kB", (98.2, 131.6, 154.3, 147.9)), ("1MB", (288.4, 331.2, 352.7, 344.6)),
                                    ("10MB", (461.3, 488.5, 497.0)), ("25MB", (509.8, 514.1, 512.3))) for r in rates]
SPEED_PING = 7.12


def cloudflare_demo():
    out = sys.stdout
    time.sleep(0.6)
    out.write(f"Avg GET request latency {SPEED_PING:.2f} ms (RTT excluding server processing time)\n\n")
    out.flush()
    summary = []
    for direction, samples, step in (("Download", SPEED_DOWN, 0.2), ("Upload", SPEED_UP, 0.25)):
        for i, (payload, rate) in enumerate(samples):
            done = round(40 * (i + 1) / len(samples))
            out.write(f"{direction} {payload:>6} [{'=' * done}{'-' * (40 - done)}] {rate:.2f} mbit/s\r")
            out.flush()
            time.sleep(step)
        out.write("\n")
        for payload in dict.fromkeys(p for p, _ in samples):
            rates = [r for p, r in samples if p == payload]
            summary.append(f"{direction} {payload:>6} | min {min(rates):.2f} max {max(rates):.2f} "
                           f"avg {sum(rates) / len(rates):.2f} mbit/s")
    out.write("\n" + "\n".join(summary) + "\n")
    out.flush()


def ookla_demo():
    def line(o):
        sys.stdout.write(json.dumps(o) + "\n")
        sys.stdout.flush()
    def bps(mbps):
        return int(mbps * 1e6 / 8)
    for i in range(1, 5):
        line({"type": "ping", "ping": {"jitter": 0.4, "latency": SPEED_PING + 0.3 * (4 - i), "progress": i / 4}})
        time.sleep(0.2)
    for direction, samples, step in (("download", SPEED_DOWN, 0.2), ("upload", SPEED_UP, 0.25)):
        mean = 0.0
        for i, (_, rate) in enumerate(samples):
            mean += (rate - mean) / (i + 1) if i < 3 else (rate - mean) / 3
            line({"type": direction, direction: {"bandwidth": bps(mean), "bytes": 0, "elapsed": 0,
                                                 "progress": (i + 1) / (len(samples) + 1)}})
            time.sleep(step)
        final = samples[-1][1]
        line({"type": direction, direction: {"bandwidth": bps(final), "progress": 1}})
    line({"type": "result", "ping": {"jitter": 0.4, "latency": SPEED_PING},
          "download": {"bandwidth": bps(SPEED_DOWN[-1][1])}, "upload": {"bandwidth": bps(SPEED_UP[-1][1])}})


def speed_test():
    if not os.environ.get("NEST_DEMO"):
        speed()
        return
    log("demo run: " + " ".join(ARGS))
    (cloudflare_demo if NAME == "cfspeedtest" else ookla_demo)()


FAKES["cfspeedtest"] = FAKES["speedtest"] = speed_test
# Each name once in `--names`: these were stubs.
STUBS = tuple(n for n in STUBS if n not in FAKES)

if __name__ == "__main__":
    if NAME in FAKES:
        if NAME not in QUIET:
            log("start " + " ".join(ARGS))
        FAKES[NAME]()
    elif NAME in STUBS:
        plain_stub()
    elif ARGS == ["--names"]:
        print("\n".join(sorted(list(FAKES) + list(STUBS))))
    else:
        print(f"fakes.py: run as an unknown name {NAME}", file=sys.stderr)
        sys.exit(127)
