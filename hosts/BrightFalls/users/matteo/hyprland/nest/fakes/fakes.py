#!/usr/bin/env python3
"""Fakes and stubs for desk-nest: every command the shell runs that would
reach outside the nest, as one program chosen by the name it is run as
(bin/ holds one symlink here per name).

Fakes answer in the protocol their panel expects, replaying the fixtures
the panel tests already use (tests/<panel>-panel/fixtures) or nest's own
(nest/fixtures). Stubs append the call to the log and act on nothing.
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
                              file) into NEST_STATE/home, times moved to now
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


# ---- weather (desk-weather) -------------------------------------------------

# The day the weather-panel fixtures' "date" fields were written for.
WEATHER_DAY = (2026, 11, 22)


def weather_lines(names, only=None):
    now = int(time.time())
    shift = days_to_today(*WEATHER_DAY)
    out = []
    for n in names.split("+"):
        for l in read_lines(f"{TESTS}/weather-panel/fixtures/{n}.jsonl"):
            m = re.search(r'"event":"([a-z_]+)"', l)
            if only and not (m and m.group(1) in only):
                continue
            l = re.sub(r'"@([+-]\d+)"', lambda m: str(now + int(m.group(1))), l)
            l = re.sub(r'"date":"(\d{4}-\d\d-\d\d)"', lambda m: '"date":"%s"' % shift_date(m.group(1), shift), l)
            out.append(l)
    return out


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
        for l in read_lines(f"{TESTS}/office-panel/fixtures/{name}.jsonl"):
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
        delta = time.time() - FLEET_BASE

        def shift(m):
            t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) + float("0" + (m.group(2) or ""))
            return iso(t + delta)
        for l in read_lines(f"{TESTS}/fleet-panel/fixtures/{name}.jsonl"):
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
}


def token_answer(name):
    with open(f"{TESTS}/tokens-panel/fixtures/{name}.json") as f:
        return json.load(f)


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
    if "binds" in ARGS and control("cheatsheet") == "host":
        with open(f"{FIXTURES}/binds.json") as f:
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
    with open(f"{TESTS}/calendar/panel/fixture-events.jsonl") as f:
        text = f.read()
    if name == "today":
        days = days_to_today(*CALENDAR_DAY)
        text = re.sub(r"(?<!\d)(\d{4}-\d\d-\d\d)(?!\d)", lambda m: shift_date(m.group(1), days), text)
    put(path, text)


def place_limits(name, home):
    with open(f"{TESTS}/tokens-panel/fixtures/limits-{name}.json") as f:
        d = json.load(f)
    delta = int(time.time()) - 60 - d["written_at"]

    def mv(x):
        if isinstance(x, dict):
            return {k: v + delta if k in ("written_at", "resets_at", "evidence_at") and isinstance(v, int) else mv(v)
                    for k, v in x.items()}
        return x
    put(f"{home}/runtime/desk/claude-limits.json", json.dumps(mv(d)) + "\n")


PLACE = {"calendar": place_calendar, "limits": place_limits}


def known(panel, name, flag):
    if (name, flag) not in index().get(panel, []):
        print(f"{NAME}: no {flag} fixture {panel} {name} in {FIXTURES}/index", file=sys.stderr)
        sys.exit(2)


def nest_place():
    if len(ARGS) != 2 or ARGS[0] not in PLACE or STATE == "/nonexistent":
        print("usage: NEST_STATE=<dir> nest-place calendar|limits <name>", file=sys.stderr)
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
         "comin-deploy", "desk-sync", "wpctl", "pactl", "ghostty", "ssh", "gh", "tmux", "sudo", "reboot",
         "poweroff")
# Called often and logged by their own code paths when it matters.
QUIET = ("gdbus", "hyprctl", "ip", "systemctl", "systemd-run", "systemd-inhibit", "nest-place", "nest-notify")

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
