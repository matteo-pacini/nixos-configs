"""desk-tunes: its pure functions, then the service built for testing against
fakes: an ace-server (HTTP on loopback, plans and WAVs made from the request,
the ggml device lines it prints chosen by the test), vulkaninfo, hyprctl,
/proc/meminfo and the GPU's sysfs memory files, and a local server standing
in for Hugging Face. mpv (audio to the null output), ffmpeg and ffprobe are
the real ones; mpv's MPRIS plugin is driven with playerctl on a private
session bus.

Usage: test-desk-tunes.py <desk-tunes built for testing> <desk-tunes.py>
           <tunes-genres.json> <config json> <work dir>
Needs python3, ffmpeg, ffprobe, mpv, dbus-daemon and playerctl on PATH and
MPV_MPRIS set to mpris.so. Every tune name, file and figure is invented.
"""

import hashlib
import importlib.util
import json
import os
import queue
import random
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EXE, SOURCE, GENRES, CONFIG, WORK = sys.argv[1:6]
HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SCALE = 0.2

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("desk_tunes", SOURCE)
dt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dt)

FAILURES = []
CHECKS = [0]


def check(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILURES.append(name)
        print(f"FAIL {name}: {detail}", flush=True)
    return cond


def eq(name, got, want):
    return check(name, got == want, f"got {got!r}, want {want!r}")


def raises(name, fn, *args, match=None):
    try:
        fn(*args)
    except ValueError as e:
        check(name, match is None or re.search(match, str(e)), f"message {e}")
        return
    check(name, False, "no ValueError")


def fixture(name):
    with open(os.path.join(FIX, name)) as f:
        return f.read()


with open(CONFIG) as f:
    REAL_CONFIG = json.load(f)
with open(GENRES) as f:
    REAL_GENRES_TEXT = f.read()
SILENCE = REAL_CONFIG["model"]["silence_code"]

# ---- pure functions --------------------------------------------------------

print("pure functions", flush=True)

eq("config: the real one validates", dt.validate_config(json.loads(json.dumps(REAL_CONFIG))),
   REAL_CONFIG)
for key, mutate in [
    ("model.base_url", lambda c: c["model"].pop("base_url")),
    ("model.files[1].sha256", lambda c: c["model"]["files"][1].update(sha256="xyz")),
    ("model.files", lambda c: c["model"]["files"].pop()),
    ("device.device", lambda c: c["device"].update(device="1900")),
    ("game_class_regex", lambda c: c.update(game_class_regex="(")),
    ("keep", lambda c: c.update(keep=0)),
]:
    c = json.loads(json.dumps(REAL_CONFIG))
    mutate(c)
    raises(f"config: bad {key} named", dt.validate_config, c, match=re.escape(key))
eq("config: the real game regex matches a Proton game in full",
   dt.game_running([{"class": "steam_app_1245620"}], REAL_CONFIG["game_class_regex"]), True)
eq("config: ... and not the Steam client",
   dt.game_running([{"class": "steam"}, {"class": "kitty"}], REAL_CONFIG["game_class_regex"]), False)
eq("config: ... and not a class that only contains a match",
   dt.game_running([{"class": "notsteam_app_1x"}], REAL_CONFIG["game_class_regex"]), False)

genres = dt.parse_genres(REAL_GENRES_TEXT)
eq("genres: the real file has nine", [g["name"] for g in genres],
   ["Lo-fi", "Ambient", "Synthwave", "Deep house", "Jazz", "Classical", "Downtempo",
    "Post-rock", "Acoustic"])
raises("genres: not JSON", dt.parse_genres, "{", match="JSON")
raises("genres: empty list", dt.parse_genres, '{"genres": []}')
for what, mutate in [
    ("a repeated id", lambda gs: gs[1].update(id=gs[0]["id"])),
    ("a name with a slash", lambda gs: gs[0].update(name="Lo/fi")),
    ("five turns", lambda gs: gs[0].update(turns=gs[0]["turns"][:5])),
    ("seven moods", lambda gs: gs[0].update(moods=gs[0]["moods"][:7])),
    ("bpm upside down", lambda gs: gs[0].update(bpm=[120, 90])),
    ("bpm as floats", lambda gs: gs[0].update(bpm=[80.0, 90])),
    ("an upper-case id", lambda gs: gs[0].update(id="LoFi")),
    ("a NUL in a name", lambda gs: gs[0].update(name="Lo\u0000fi")),
    ("a line break in a name", lambda gs: gs[0].update(name="Lo\nfi")),
]:
    gs = json.loads(REAL_GENRES_TEXT)["genres"]
    mutate(gs)
    raises(f"genres: {what}", dt.parse_genres, json.dumps({"genres": gs}))

g0 = genres[0]
rng = random.Random(7)
for _ in range(50):
    cap = dt.caption_for(g0, rng)
    turns = cap[len(g0["caption"]) + 2:-len(", instrumental")].split(", ")
    if not (cap.startswith(g0["caption"] + ", ") and cap.endswith(", instrumental")
            and len(set(turns)) >= 2):
        check("caption: genre caption, two distinct turns, instrumental", False, cap)
        break
    bpm = dt.bpm_for(g0, rng)
    if not g0["bpm"][0] <= bpm <= g0["bpm"][1]:
        check("bpm: in the genre's range", False, bpm)
        break
    name = dt.name_for(g0, rng)
    if not any(name == f"{m} {t}" for m in g0["moods"] for t in g0["things"]):
        check("name: mood and thing", False, name)
        break
CHECKS[0] += 3

S = SILENCE


def codes(*parts):
    out = []
    for kind, n in parts:
        out += [S] * n if kind == "s" else [1000 + i for i in range(n)]
    return out


eq("silence: a 2 s tail is cut where it starts",
   dt.plan_verdict(codes(("m", 50), ("s", 10)), S), {"cut": 10.0, "rewrite": None})
eq("silence: a 0.8 s tail is left", dt.plan_verdict(codes(("m", 56), ("s", 4)), S),
   {"cut": None, "rewrite": None})
eq("silence: exactly 1 s of tail is cut", dt.plan_verdict(codes(("m", 55), ("s", 5)), S),
   {"cut": 11.0, "rewrite": None})
eq("silence: 5 s in the middle is allowed",
   dt.plan_verdict(codes(("m", 10), ("s", 25), ("m", 25)), S), {"cut": None, "rewrite": None})
eq("silence: 5.2 s in the middle rewrites",
   dt.plan_verdict(codes(("m", 10), ("s", 26), ("m", 24), ("s", 10)), S),
   {"cut": 12.0, "rewrite": 5.2})
eq("silence: the longest bad run is the one reported",
   dt.plan_verdict(codes(("s", 30), ("m", 5), ("s", 40), ("m", 5)), S)["rewrite"], 8.0)
eq("silence: a leading run counts as the middle",
   dt.plan_verdict(codes(("s", 30), ("m", 30)), S)["rewrite"], 6.0)
eq("silence: the real format of codes", dt.parse_codes("12,35847,7,"), [12, 35847, 7])
raises("silence: no codes", dt.parse_codes, ",")

eq("retry: first after 3 s", dt.retry_delay(1), 3.0)
eq("retry: then every 30 s", [dt.retry_delay(n) for n in (2, 3, 9)], [30.0, 30.0, 30.0])
eq("mpv restart: 2 s doubling to 60 s", [dt.mpv_restart_delay(n) for n in (1, 2, 3, 5, 6, 40)],
   [2.0, 4.0, 8.0, 32.0, 60.0, 60.0])

when = datetime(2026, 11, 22, 21, 5, 9)
eq("file name", dt.tune_filename(when, 88, "C# minor"), "20261122-210509-88bpm-C#-minor.mp3")
eq("file name: an empty key", dt.tune_filename(when, 88, ""), "20261122-210509-88bpm-unknown.mp3")
eq("file name parsed", dt.parse_tune_filename("20261122-210509-88bpm-C#-minor.mp3"), (88, "C# minor"))
eq("file name: other files are not ours",
   [dt.parse_tune_filename(n) for n in ("notes.mp3", "20261122-210509-88bpm-C#-minor.mp3.bak",
                                        "x20261122-210509-88bpm-A-major.mp3")], [None, None, None])
names = [f"2026010{d}-000000-80bpm-A-major.mp3" for d in range(1, 8)] + ["mine.mp3", "notes.txt"]
eq("keep: oldest first, only ours", dt.keep_victims(names, 4, set()), names[:3])
eq("keep: protected names are counted, never deleted",
   dt.keep_victims(names, 4, {names[0], names[2]}), [names[1], names[3], names[4]])
eq("keep: under the limit", dt.keep_victims(names[:3] + ["mine.mp3"], 4, set()), [])

loud = [8000, -8000] * 4000
quiet = [0] * 8000
eq("levels: a 0 dB-ish tone and silence", [round(v) for v in dt.levels_db(loud[:800] + quiet[:800])],
   [round(20 * __import__("math").log10(8000 / 32768)), -120])
lv = dt.levels_db(loud + quiet * 6 + loud + quiet * 2)
eq("backstop: 6 s quiet in the middle", round(dt.quiet_mid_run(lv), 1), 6.0)
eq("backstop: a quiet tail does not count",
   round(dt.quiet_mid_run(dt.levels_db(loud + quiet * 7)), 1), 0.0)
eq("backstop: 4.9 s is under the limit",
   dt.quiet_mid_run(dt.levels_db(loud + [0] * 39200 + loud)) <= dt.QUIET_MAX, True)
w = dt.wave_bars([100] * 780 + [50] * 780)
eq("wave: 78 bars", len(w), 78)
eq("wave: normalised to the loudest", (max(w), w[0], w[-1]), (1.0, 1.0, 0.5))
eq("wave: silence is zeros", dt.wave_bars([0] * 1000), [0.0] * 78)
eq("wave: fewer samples than bars", len(dt.wave_bars([5, 9])), 78)

V, D = "0x1002", "0x1900"
eq("device: eGPU first, the 780M is Vulkan1",
   dt.resolve_device(fixture("vulkaninfo-egpu-first.txt"), V, D),
   (1, "AMD Radeon 780M Graphics (RADV PHOENIX)"))
eq("device: llvmpipe first is skipped, the 780M is Vulkan0",
   dt.resolve_device(fixture("vulkaninfo-igpu-first.txt"), V, D)[0], 0)
eq("device: eGPU absent, the 780M is Vulkan0",
   dt.resolve_device(fixture("vulkaninfo-no-egpu.txt"), V, D)[0], 0)
eq("device: one device under two drivers counts once",
   dt.resolve_device(fixture("vulkaninfo-two-drivers.txt"), V, D)[0], 1)
eq("device: the 780M absent, never the other card",
   dt.resolve_device(fixture("vulkaninfo-no-igpu.txt"), V, D),
   (None, "found 1 other Vulkan GPU: AMD Radeon RX 6800 XT (RADV NAVI21)"))
eq("device: no GPU at all", dt.resolve_device("Devices:\n========\n", V, D),
   (None, "found no Vulkan GPU"))
GGML_TWO = ["ggml_vulkan: Found 2 Vulkan devices:",
            "ggml_vulkan: 0 = AMD Radeon RX 6800 XT (RADV NAVI21) (radv) | uma: 0 | fp16: dot2",
            "ggml_vulkan: 1 = AMD Radeon 780M Graphics (RADV PHOENIX) (radv) | uma: 1 | fp16: dot2"]
eq("device: confirmed by the server's line",
   dt.confirm_device(GGML_TWO, 1, "AMD Radeon 780M Graphics (RADV PHOENIX)"), None)
eq("device: the server's index names another card",
   dt.confirm_device(GGML_TWO, 0, "AMD Radeon 780M Graphics (RADV PHOENIX)"),
   "the server's Vulkan0 is AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
eq("device: the server lists no such index",
   dt.confirm_device(GGML_TWO[:2], 1, "AMD Radeon 780M Graphics (RADV PHOENIX)"),
   "the server listed no Vulkan1")
eq("memory: MemAvailable", dt.mem_available("MemTotal: 9 kB\nMemAvailable:    2048 kB\n"), 2097152)
eq("memory: missing", dt.mem_available("MemTotal: 9 kB\n"), None)
body = (b"--ace-batch-boundary\r\nContent-Type: audio/wav\r\n\r\nRIFFxx\r\n--ace-batch-boundary\r\n"
        b"Content-Type: application/octet-stream\r\nContent-Disposition: form-data; name=\"latent\""
        b"\r\n\r\n\x00\x01\r\n--ace-batch-boundary--\r\n")
eq("synth result: the audio part", dt.multipart_audio(body), b"RIFFxx")
raises("synth result: no audio part", dt.multipart_audio,
       b"--b\r\nContent-Type: application/json\r\n\r\n{}\r\n--b--\r\n")
eq("median: odd", dt.median([120, 104, 111]), 111.0)
eq("median: even", dt.median([100, 110, 130, 90]), 105.0)
eq("median: none", dt.median([]), None)
eq("timings: the last five kept", dt.add_timing([1, 2, 3, 4, 5], 6.04), [2, 3, 4, 5, 6.0])
eq("timings: read back", dt.read_timings({"writing": [60.5, 70], "rendering": [40]}),
   {"writing": [60.5, 70], "rendering": [40]})
eq("timings: malformed reads as none", dt.read_timings({"writing": ["x"], "rendering": 4}),
   {"writing": [], "rendering": []})
eq("timings: an old state file", dt.read_timings({"counter": 7}), {"writing": [], "rendering": []})
eq("expect: null until timed", dt.expect_view({"writing": [], "rendering": []}), None)
eq("expect: both medians", dt.expect_view({"writing": [60, 70, 80], "rendering": [40, 50]}),
   {"writing_s": 70.0, "rendering_s": 45.0})
NK = {"name": "k"}
eq("queue: the queued tunes", dt.queue_entries([{"name": "a"}, {"name": "b"}], NK),
   [{"name": "a"}, {"name": "b"}])
eq("queue: else the next kept one", dt.queue_entries([], NK), [NK])
eq("queue: else nothing", dt.queue_entries([], None), [])
M = "/h/Music/Tunes"
eq("scrap: ours in a genre folder", dt.scrappable(f"{M}/Jazz/20260103-100000-120bpm-F-major.mp3", M), True)
for what, p in (("another name", f"{M}/Jazz/my own song.mp3"),
                ("a backup", f"{M}/Jazz/20260103-100000-120bpm-F-major.mp3.bak"),
                ("outside the music folder", "/h/Music/Other/20260103-100000-120bpm-F-major.mp3"),
                ("a nested folder", f"{M}/Jazz/old/20260103-100000-120bpm-F-major.mp3"),
                ("the music folder itself", f"{M}/20260103-100000-120bpm-F-major.mp3")):
    eq(f"scrap: not {what}", dt.scrappable(p, M), False)
files = [{"name": "a", "bytes": 10}, {"name": "b", "bytes": 5}]
eq("need: bytes over the whole set", dt.need_bytes(files, {"a": 10, "b": 2}), 3)
# mpv's stderr and its IPC socket can close in one select() pass: the
# socket's event then finds mpv dropped, or restarted and not yet connected.
for what, mpv in (("dropped", None), ("not connected", {"sock": None})):
    try:
        dt.Service.mpv_readable(type("S", (), {"mpv": mpv})())
        check(f"mpv socket event with mpv {what}: ignored", True)
    except Exception as e:
        check(f"mpv socket event with mpv {what}: ignored", False, repr(e))

# ---- the service against fakes ----------------------------------------------

print("service", flush=True)
HOME = os.path.join(WORK, "home")
RUNTIME = tempfile.mkdtemp(prefix="tunes-")
CTL = os.path.join(WORK, "fake")
FAKES = os.path.join(WORK, "bin")
for d in (HOME, CTL, FAKES):
    os.makedirs(d, exist_ok=True)
os.chmod(RUNTIME, 0o700)
XDG = {"XDG_CONFIG_HOME": f"{HOME}/.config", "XDG_DATA_HOME": f"{HOME}/.local/share",
       "XDG_STATE_HOME": f"{HOME}/.local/state", "XDG_CACHE_HOME": f"{HOME}/.cache"}
MUSIC = os.path.join(HOME, "Music", "Tunes")
MODELS = os.path.join(XDG["XDG_DATA_HOME"], "desk-tunes", "models")
STATE = os.path.join(XDG["XDG_STATE_HOME"], "desk-tunes", "state.json")
LIVE_GENRES = os.path.join(XDG["XDG_CONFIG_HOME"], "desk", "tunes-genres.json")
os.makedirs(os.path.dirname(LIVE_GENRES))
shutil.copy(GENRES, LIVE_GENRES)

FAKE_ACE = r'''
import json, math, os, random, signal, struct, sys, threading, time, wave, io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
CTL = os.environ["FAKE_DIR"]
SILENCE = int(os.environ["FAKE_SILENCE"])
args = sys.argv[1:]
opt = dict(zip(args[::2], args[1::2]))
lock = threading.Lock()

def log(**o):
    with lock, open(os.path.join(CTL, "ace.jsonl"), "a") as f:
        f.write(json.dumps(dict(o, t=time.time(), pid=os.getpid())) + "\n")

def take(kind):
    p = os.path.join(CTL, "scenario.json")
    with lock:
        sc = json.load(open(p))
        q = sc.get(kind, [])
        v = q.pop(0) if q else "ok"
        sc[kind] = q
        with open(p + ".tmp", "w") as f:
            json.dump(sc, f)
        os.replace(p + ".tmp", p)
        return v, sc.get(kind + "_time", 0.3)

def bye(*_):
    log(kind="exit")
    os._exit(0)
signal.signal(signal.SIGTERM, bye)
log(kind="start", argv=args)
for line in open(os.path.join(CTL, "ggml.txt")).read().splitlines():
    print(line, file=sys.stderr, flush=True)

jobs = {}
rng = random.Random()
TONE = b"".join(struct.pack("<hh", int(8000 * math.sin(2 * math.pi * 440 * i / 48000)),
                            int(8000 * math.sin(2 * math.pi * 440 * i / 48000))) for i in range(9600))
QUIET = b"\0" * len(TONE)

def plan(req, kind):
    n = int(req["duration"] * 5)
    c = [rng.randrange(0, 30000) for _ in range(n)]
    for i in range(n - 10, n):
        c[i] = SILENCE
    if kind == "silent":
        for i in range(10, 42):
            c[i] = SILENCE
    return {"caption": "The model's own words for: " + req["caption"], "seed": 12345,
            "lyrics": "[Instrumental]", "audio_codes": ",".join(map(str, c)) + ",",
            "bpm": req.get("bpm") or 80, "duration": float(req["duration"]),
            "keyscale": rng.choice(["C# minor", "F major"]), "timesignature": "4",
            "vocal_language": "unknown", "lm_seed": 678, "solver": "euler",
            "lm_mode": "generate", "output_format": "mp3", "task_type": "text2music"}

def render(req, kind):
    c = [int(x) for x in req["audio_codes"].split(",") if x]
    frames = b"".join(QUIET if (x == SILENCE or (kind == "quiet" and 15 <= i < 48)) else TONE
                      for i, x in enumerate(c))
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000); w.writeframes(frames)
    audio = out.getvalue()
    b = b"--ace-batch-boundary"
    return (b + b"\r\nContent-Type: audio/wav\r\n\r\n" + audio + b"\r\n" + b +
            b"\r\nContent-Type: application/octet-stream\r\nContent-Disposition: form-data; "
            b"name=\"latent\"\r\n\r\n" + b"\0" * 256 + b"\r\n" + b + b"--\r\n")

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def reply(self, code, body, mime="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        path, _, q = self.path.partition("?")
        params = dict(p.split("=", 1) for p in q.split("&") if "=" in p)
        log(kind="req", method="GET", path=self.path)
        if path == "/health":
            return self.reply(200, {"status": "ok"})
        j = jobs.get(params.get("id"))
        if not j:
            return self.reply(404, {"error": "Job not found"})
        if j["status"] == "running" and time.time() >= j["end"]:
            if j["kind"] == "exit":
                print("[VAE] ggml_vulkan: Device lost (simulated)", file=sys.stderr, flush=True)
                log(kind="crash")
                os._exit(1)
            j["status"] = "failed" if j["kind"] == "fail" else "done"
            if j["kind"] == "fail":
                print("[Server] FATAL: simulated failure", file=sys.stderr, flush=True)
        if params.get("result") == "1":
            if j["status"] != "done":
                return self.reply(404, {"error": "Result not ready"})
            return self.reply(200, j["result"], j["mime"])
        return self.reply(200, {"status": j["status"]})
    def do_POST(self):
        path, _, q = self.path.partition("?")
        params = dict(p.split("=", 1) for p in q.split("&") if "=" in p)
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
        summary = None
        if isinstance(body, dict):
            summary = {k: v for k, v in body.items() if k != "audio_codes"}
            if "audio_codes" in body:
                summary["codes_n"] = len([x for x in body["audio_codes"].split(",") if x])
        log(kind="req", method="POST", path=self.path, body=summary)
        if path == "/job":
            j = jobs.get(params.get("id"))
            if not j:
                return self.reply(404, {"error": "Job not found"})
            if j["status"] == "running":
                j["status"] = "cancelled"
            return self.reply(200, {"status": j["status"]})
        jid = "%016x" % rng.getrandbits(64)
        if path == "/lm":
            kind, t = take("lm")
            result, mime = json.dumps([plan(body, kind)]).encode(), "application/json"
        else:
            kind, t = take("synth")
            result = render(body, kind)
            mime = "multipart/mixed; boundary=ace-batch-boundary"
        jobs[jid] = {"status": "running", "end": time.time() + t, "kind": kind,
                     "result": result, "mime": mime}
        self.reply(200, {"id": jid})

srv = ThreadingHTTPServer((opt["--host"], int(opt["--port"])), H)
print(f"[Server] Listening on {opt['--host']}:{opt['--port']}", file=sys.stderr, flush=True)
srv.serve_forever()
'''

FAKE_VULKANINFO = r'''
import os, sys
with open(os.path.join(os.environ["FAKE_DIR"], "vulkaninfo.log"), "a") as f:
    shown = [k for k in ("DISPLAY", "WAYLAND_DISPLAY") if k in os.environ]
    f.write(" ".join(sys.argv[1:] + shown) + "\n")
sys.stdout.write(open(os.path.join(os.environ["FAKE_DIR"], "vulkaninfo.txt")).read())
sys.stdout.flush()
if os.path.exists(os.path.join(os.environ["FAKE_DIR"], "vulkaninfo.crash")):
    os._exit(139)
'''

FAKE_HYPRCTL = r'''
import os, sys
with open(os.path.join(os.environ["FAKE_DIR"], "hyprctl.log"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(open(os.path.join(os.environ["FAKE_DIR"], "clients.json")).read())
'''


def fake(name, code):
    path = os.path.join(FAKES, name)
    with open(path, "w") as f:
        f.write(f"#!{sys.executable} -I\n{code}")
    os.chmod(path, 0o755)
    return path


ACE = fake("ace-server", FAKE_ACE)
VULKANINFO = fake("vulkaninfo", FAKE_VULKANINFO)
fake("hyprctl", FAKE_HYPRCTL)


def put(name, text):
    with open(os.path.join(CTL, name + ".tmp"), "w") as f:
        f.write(text)
    os.replace(os.path.join(CTL, name + ".tmp"), os.path.join(CTL, name))


def scenario(**kw):
    sc = {"lm": [], "synth": [], "lm_time": 0.3, "synth_time": 0.3}
    sc.update(kw)
    put("scenario.json", json.dumps(sc))


GIB = 1 << 30
MEMINFO = os.path.join(CTL, "meminfo")


def meminfo(avail):
    put("meminfo", f"MemTotal:       32000000 kB\nMemAvailable:   {avail // 1024} kB\n")


SYSFS = os.path.join(CTL, "sys")
CARD = os.path.join(SYSFS, "class", "drm", "card1", "device")
os.makedirs(CARD)
for k, v in (("vendor", "0x1002"), ("device", "0x1900"), ("mem_info_vram_used", "100000000"),
             ("mem_info_gtt_used", "50000000")):
    with open(os.path.join(CARD, k), "w") as f:
        f.write(v + "\n")
other = os.path.join(SYSFS, "class", "drm", "card0", "device")
os.makedirs(other)
for k, v in (("vendor", "0x1002"), ("device", "0x73bf"), ("mem_info_vram_used", "4000000000"),
             ("mem_info_gtt_used", "1")):
    with open(os.path.join(other, k), "w") as f:
        f.write(v + "\n")


def ace_log():
    try:
        with open(os.path.join(CTL, "ace.jsonl")) as f:
            return [json.loads(line) for line in f]
    except FileNotFoundError:
        return []


def wait(name, pred, timeout=20.0, step=0.05):
    end = time.time() + timeout
    while time.time() < end:
        v = pred()
        if v:
            return v
        time.sleep(step)
    check(name, False, f"not within {timeout} s")
    return None


# -- the Hugging Face stand-in --
REV = REAL_CONFIG["model"]["revision"]
MODEL_FILES = {}
for f in REAL_CONFIG["model"]["files"]:
    size = {"lm": 400_000, "dit": 300_000, "text": 900_000, "vae": 120_000}[f["role"]]
    MODEL_FILES[f["name"]] = bytes(random.Random(f["name"]).getrandbits(8) for _ in range(size))
DL = {"cut": {}, "corrupt": set(), "slow": set(), "ranges": [], "hits": []}


class HF(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        m = re.match(rf"^/repo/resolve/{REV}/([^/]+)$", self.path)
        if not m or m.group(1) not in MODEL_FILES:
            self.send_response(404)
            self.end_headers()
            return
        name = m.group(1)
        data = MODEL_FILES[name]
        if name in DL["corrupt"]:
            data = bytes(len(data))
        DL["hits"].append(name)
        rng_ = self.headers.get("Range")
        start = 0
        if rng_:
            DL["ranges"].append((name, rng_))
            start = int(re.match(r"bytes=(\d+)-", rng_).group(1))
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{len(data) - 1}/{len(data)}")
        else:
            self.send_response(200)
        self.send_header("Content-Length", str(len(data) - start))
        self.end_headers()
        cut = DL["cut"].pop(name, None)
        body = data[start:]
        try:
            if cut is not None:
                self.wfile.write(body[:cut])
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            step = 16384
            for i in range(0, len(body), step):
                self.wfile.write(body[i:i + step])
                if name in DL["slow"]:
                    time.sleep(0.1)
        except (BrokenPipeError, ConnectionResetError):
            pass


hf = ThreadingHTTPServer(("127.0.0.1", 0), HF)
threading.Thread(target=hf.serve_forever, daemon=True).start()

CFG = json.loads(json.dumps(REAL_CONFIG))
CFG["model"]["base_url"] = f"http://127.0.0.1:{hf.server_address[1]}/repo"
for f in CFG["model"]["files"]:
    f["bytes"] = len(MODEL_FILES[f["name"]])
    f["sha256"] = hashlib.sha256(MODEL_FILES[f["name"]]).hexdigest()
CFG["model"]["ram_bytes"] = 4 * GIB
CFG.update(duration=12, keep=4, ahead=2)
TEST_CONFIG = os.path.join(WORK, "config.json")
with open(TEST_CONFIG, "w") as f:
    json.dump(CFG, f)
FILES = CFG["model"]["files"]
TOTAL = sum(f["bytes"] for f in FILES)

# -- a private session bus for mpv's MPRIS plugin --
BUS_CONF = os.path.join(WORK, "bus.conf")
with open(BUS_CONF, "w") as f:
    f.write(f"""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path={RUNTIME}/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")
bus = subprocess.Popen(["dbus-daemon", "--config-file", BUS_CONF, "--nofork", "--print-address"],
                       stdout=subprocess.PIPE, text=True)
BUS = bus.stdout.readline().strip()
if not BUS:
    raise SystemExit("dbus-daemon did not start")

ENV = {k: v for k, v in os.environ.items() if k not in ("HYPRLAND_INSTANCE_SIGNATURE",)}
ENV.update(XDG, HOME=HOME, XDG_RUNTIME_DIR=RUNTIME, PATH=FAKES + os.pathsep + os.environ["PATH"],
           DBUS_SESSION_BUS_ADDRESS=BUS, FAKE_DIR=CTL, FAKE_SILENCE=str(SILENCE),
           DISPLAY=":97", WAYLAND_DISPLAY="wayland-97")
SOCK = os.path.join(RUNTIME, "desk-tunes", "sock")


class Client:
    """A raw socket client, or `desk-tunes attach` when attach=True."""

    def __init__(self, attach=False):
        self.lines = queue.Queue()
        self.last = None
        if attach:
            self.proc = subprocess.Popen([EXE, "attach"], env=ENV, stdin=subprocess.PIPE,
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.w, r = self.proc.stdin, self.proc.stdout
        else:
            self.proc = None
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.connect(SOCK)
            r = self.sock.makefile("rb")
            self.w = self.sock.makefile("wb")
        threading.Thread(target=self.read, args=(r,), daemon=True).start()

    def read(self, r):
        for line in r:
            self.lines.put(json.loads(line))
        self.lines.put(None)

    def send(self, obj):
        self.w.write((obj if isinstance(obj, str) else json.dumps(obj)).encode() + b"\n")
        self.w.flush()

    def get(self, timeout):
        try:
            ev = self.lines.get(timeout=timeout)
        except queue.Empty:
            return None
        if ev and ev.get("event") == "state":
            self.last = ev
        return ev

    def until(self, name, pred, timeout=20.0):
        """The first state snapshot satisfying pred (the last one already
        received counts)."""
        if self.last and pred(self.last):
            return self.last
        end = time.time() + timeout
        while time.time() < end:
            ev = self.get(end - time.time())
            if ev and ev.get("event") == "state" and pred(ev):
                return ev
        check(name, False, f"not within {timeout} s; last: {json.dumps(self.last)[:600]}")
        return self.last or {}

    def quiet(self, seconds):
        """Events that arrive within `seconds`."""
        out = []
        end = time.time() + seconds
        while time.time() < end:
            ev = self.get(end - time.time())
            if ev:
                out.append(ev)
        return out

    def ask_timers(self):
        self.send({"cmd": "test_timers"})
        while True:
            ev = self.get(10)
            if ev is None or ev.get("event") == "test_timers":
                return ev

    def close(self):
        if self.proc:
            self.proc.stdin.close()
            return self.proc.wait(10)
        self.sock.close()


def model(s):
    return s.get("model", {})


def kept_files(genre):
    try:
        return sorted(n for n in os.listdir(os.path.join(MUSIC, genre)) if dt.TUNE_FILE.match(n))
    except FileNotFoundError:
        return []


def mp3(path, seconds, title):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i",
                    f"sine=frequency=330:duration={seconds}", "-ac", "2", "-c:a", "libmp3lame",
                    "-b:a", "64k", "-metadata", f"title={title}", "-y", path], check=True)


def tags(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags:format=duration",
                          "-of", "json", path], capture_output=True, check=True)
    fmt = json.loads(out.stdout)["format"]
    return {k.lower(): v for k, v in fmt.get("tags", {}).items()}, float(fmt["duration"])


def mpv_pid():
    """The pid of the service's mpv, or None."""
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            with open(f"/proc/{p}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
        except OSError:
            continue
        if f"--input-ipc-server={RUNTIME}/desk-tunes/mpv.sock".encode() in argv:
            return int(p)
    return None


def playerctl(*args):
    return subprocess.run(["playerctl", *args], env=ENV, capture_output=True, text=True, timeout=10)


# Kept tunes made before the service starts, and files that are not ours.
LOFI_KEPT = [os.path.join(MUSIC, "Lo-fi", "20260101-100000-80bpm-A-minor.mp3"),
             os.path.join(MUSIC, "Lo-fi", "20260102-100000-84bpm-D-major.mp3")]
mp3(LOFI_KEPT[0], 90, "Invented Old Morning")
mp3(LOFI_KEPT[1], 90, "Invented Old Evening")
JAZZ_KEPT = [os.path.join(MUSIC, "Jazz", "20260103-100000-120bpm-F-major.mp3"),
             os.path.join(MUSIC, "Jazz", "20260104-100000-110bpm-Bb-minor.mp3")]
mp3(JAZZ_KEPT[0], 90, "Invented Brass Corner")
mp3(JAZZ_KEPT[1], 90, "Invented Late Cellar")
FOREIGN = [os.path.join(MUSIC, "Lo-fi", n) for n in
           ("my own song.mp3", "notes.txt", "20260101-000000-80bpm-C-major.mp3.bak", ".my-notes.part")]
for p in FOREIGN:
    with open(p, "w") as f:
        f.write("not ours")
STALE_PART = os.path.join(MUSIC, "Lo-fi", ".20260101-000000-80bpm-C-major.mp3.part")
with open(STALE_PART, "w") as f:
    f.write("an encode that never finished")

put("vulkaninfo.txt", fixture("vulkaninfo-no-igpu.txt"))
put("ggml.txt", "\n".join(GGML_TWO))
put("clients.json", json.dumps([{"class": "kitty", "title": "a terminal"}]))
meminfo(20 * GIB)
scenario()

# attach before the service exists: exit 3, one short line, no path
p = subprocess.run([EXE, "attach"], env=ENV, stdin=subprocess.DEVNULL, capture_output=True,
                   timeout=10)
eq("attach: no socket exits 3", p.returncode, 3)
eq("attach: one plain line for the user", p.stderr.decode(), "the tunes service is not running\n")

SERVE_LOG = open(os.path.join(WORK, "serve.log"), "w")
serve = subprocess.Popen([EXE, "serve", "--config", TEST_CONFIG, "--ace-server", ACE,
                          "--mpv", shutil.which("mpv"), "--mpris", os.environ["MPV_MPRIS"],
                          "--ffmpeg", shutil.which("ffmpeg"), "--ffprobe", shutil.which("ffprobe"),
                          "--vulkaninfo", VULKANINFO, "--test-scale", str(SCALE), "--test-ao", "null",
                          "--test-meminfo", MEMINFO, "--test-sysfs", SYSFS],
                         env=ENV, stdout=subprocess.DEVNULL, stderr=SERVE_LOG)


def finish():
    for proc in (serve, bus):
        if proc.poll() is None:
            proc.kill()
    hf.shutdown()
    SERVE_LOG.close()
    with open(os.path.join(WORK, "serve.log")) as f:
        tail = f.read()[-3000:]
    if FAILURES:
        print("--- serve.log (end) ---\n" + tail)
    print(f"{CHECKS[0]} checks, {len(FAILURES)} failed")
    shutil.rmtree(RUNTIME, ignore_errors=True)
    sys.exit(1 if FAILURES else 0)


try:
    wait("serve: the socket appears", lambda: os.path.exists(SOCK), 10)
    eq("serve: socket directory is 0700", os.stat(os.path.dirname(SOCK)).st_mode & 0o777, 0o700)
    check("serve: an unfinished encode's file is deleted at start", not os.path.exists(STALE_PART))

    # -- attach and the first snapshot --
    print("  snapshot and protocol", flush=True)
    A = Client(attach=True)
    s = A.until("attach: a snapshot at once", lambda s: True, 5)
    eq("snapshot: v", s.get("v"), 1)
    eq("snapshot: setup missing", s.get("setup"), "missing")
    eq("snapshot: no download", s.get("download"), None)
    eq("snapshot: need", s.get("need", {}).get("download_bytes"), TOTAL)
    eq("snapshot: ram need", s.get("need", {}).get("ram_bytes"), 4 * GIB)
    check("snapshot: disk free", isinstance(s.get("need", {}).get("disk_free_bytes"), int))
    eq("snapshot: genres in file order with kept counts",
       [(g["id"], g["name"], g["kept"]) for g in s.get("genres", [])][:5],
       [(g["id"], g["name"], {"Lo-fi": 2, "Jazz": 2}.get(g["name"], 0)) for g in genres][:5])
    eq("snapshot: all nine", len(s.get("genres", [])), 9)
    eq("snapshot: nothing picked, nothing plays", (s.get("genre"), s.get("player"), s.get("tune")),
       (None, "none", None))
    eq("snapshot: no tune, no next", s.get("can_next"), False)
    eq("snapshot: the composer is off at start, nothing queued, no job, nothing to undo",
       {k: s.get(k) for k in ("composing", "queue", "job", "undo", "kept_total", "expect",
                              "ahead", "stopped")},
       {"composing": False, "queue": [], "job": None, "undo": None, "kept_total": 0,
        "expect": None, "ahead": 2, "stopped": False})
    eq("snapshot: model", {k: model(s).get(k) for k in ("name", "variant", "device", "state",
                                                         "ram_used_bytes", "ram_free_bytes")},
       {"name": "ACE-Step 1.5 Turbo", "variant": "4B Q8", "device": "Radeon 780M",
        "state": "unloaded", "ram_used_bytes": None, "ram_free_bytes": 20 * GIB})
    eq("snapshot: no error", s.get("error"), None)
    t = A.ask_timers()
    eq("idle: no timer armed at start", t and t.get("timers"), [])
    eq("idle: one thread", t and t.get("threads"), 1)

    B = Client()
    sb = B.until("second client: a snapshot on attach", lambda s: True, 5)
    eq("second client: the same state", sb.get("setup"), "missing")
    A.send("this is not json")
    ev = A.get(5)
    eq("malformed: an error to the sender", ev and ev.get("event"), "error")
    for bad in ('{"cmd":"bogus"}', '{"cmd":"seek","t":"soon"}', '{"cmd":"genre"}', '[1]',
                '{"cmd":"compose"}', '{"cmd":"compose","on":1}', '{"cmd":"play"}',
                '{"cmd":"play","i":-1}', '{"cmd":"scrap","i":"1"}', '{"cmd":"scrap","job":false}',
                '{"cmd":"load"}', '{"cmd":"unload"}'):
        A.send(bad)
        ev = A.get(5)
        eq(f"malformed or gone: {bad}", ev and ev.get("event"), "error")
    for cmd in ("next", "toggle", "retry", "cancel_download", "undo", "scrap"):
        A.send({"cmd": cmd})
    A.send({"cmd": "seek", "t": 10})
    A.send({"cmd": "genre", "id": "no-such-genre"})
    A.send({"cmd": "compose", "on": True})
    A.send({"cmd": "compose", "on": False})
    A.send({"cmd": "play", "i": 0})
    A.send({"cmd": "scrap", "i": 0})
    A.send({"cmd": "scrap", "job": True})
    got = B.quiet(1.0)
    eq("malformed and inapplicable: nothing to the other client", got, [])
    A.send({"cmd": "refresh"})
    check("refresh: a snapshot to both", A.until("refresh A", lambda s: True, 5)
          and B.until("refresh B", lambda s: True, 5))
    for c in (A, B):
        c.quiet(0.3)

    # -- download --
    print("  download", flush=True)
    names = [f["name"] for f in FILES]
    DL["cut"][names[1]] = 100_000
    A.send({"cmd": "download"})
    s = A.until("download: running", lambda s: s["setup"] == "downloading")
    eq("download: totals over the whole set", (s["download"]["total"], s["download"]["files"]),
       (TOTAL, 4))
    s = A.until("download: a broken connection fails", lambda s: s["setup"] == "failed")
    check("download: the error names the file", names[1] in (s.get("download") or {}).get("error", ""),
          json.dumps(s.get("download")))
    check("download: the first file is in place", os.path.exists(os.path.join(MODELS, names[0])))
    part = os.path.join(MODELS, names[1] + ".part")
    check("download: the partial file is kept", os.path.exists(part) and os.path.getsize(part) > 0)
    got_part = os.path.getsize(part) if os.path.exists(part) else 0
    eq("download: need counts the partial file", s["need"]["download_bytes"],
       TOTAL - len(MODEL_FILES[names[0]]) - got_part)

    DL["corrupt"].add(names[2])
    A.send({"cmd": "download"})
    s = A.until("download: a bad checksum fails", lambda s: s["setup"] == "failed" and
                "checksum" in (s.get("download") or {}).get("error", ""), 30)
    eq("download: resumed with Range", (names[1], f"bytes={got_part}-") in DL["ranges"], True)
    with open(os.path.join(MODELS, names[1]), "rb") as f:
        eq("download: the resumed file is whole", hashlib.sha256(f.read()).hexdigest(),
           FILES[1]["sha256"])
    check("download: the bad file is not kept", not os.path.exists(os.path.join(MODELS, names[2]))
          and not os.path.exists(os.path.join(MODELS, names[2] + ".part")))
    check("download: the error names the file", names[2] in s["download"]["error"])

    DL["corrupt"].clear()
    DL["slow"].add(names[2])
    A.send({"cmd": "download"})
    stamps = []
    before = len(MODEL_FILES[names[0]]) + len(MODEL_FILES[names[1]])
    end = time.time() + 30
    while time.time() < end:
        ev = A.get(1)
        if ev and ev.get("event") == "state" and ev["setup"] == "downloading":
            stamps.append(time.monotonic())
            if ev["download"]["done"] > before + 500_000:
                eq("download: progress names the file", (ev["download"]["file"],
                                                        ev["download"]["name"]), (3, "text encoder"))
                check("download: a rate", ev["download"]["rate"] > 0)
                break
    gaps = [b - a for a, b in zip(stamps[1:], stamps[2:])]
    check("download: progress at most twice a second", gaps and min(gaps) > 0.4, f"{gaps}")
    A.send({"cmd": "cancel_download"})
    s = A.until("download: cancelled", lambda s: s["setup"] == "missing" and s["download"] is None)
    check("download: cancel keeps finished files",
          all(os.path.exists(os.path.join(MODELS, n)) for n in names[:2]))
    A.send({"cmd": "download"})
    A.until("download: resumed slowly", lambda s: s["setup"] == "downloading"
            and s["download"]["done"] > before + 600_000, 30)
    # Both lines in one write: the second download starts while the
    # cancelled one may still be blocked reading its next block.
    A.send('{"cmd":"cancel_download"}\n{"cmd":"download"}')

    DL["slow"].clear()
    A.send({"cmd": "download"})
    A.until("download: running again", lambda s: s["setup"] == "downloading")
    eq("attach: stdin closing exits 0", A.close(), 0)
    B.close()
    wait("download: finishes with no client attached",
         lambda: all(os.path.exists(os.path.join(MODELS, n)) for n in names), 30)
    A = Client(attach=True)
    s = A.until("download: ready", lambda s: s["setup"] == "ready")
    eq("download: done and nothing left to fetch", (s["download"], s["need"]["download_bytes"]),
       (None, 0))
    check("download: only the four files", sorted(os.listdir(MODELS)) == sorted(names),
          os.listdir(MODELS))
    for f in FILES:
        with open(os.path.join(MODELS, f["name"]), "rb") as fh:
            eq(f"download: {f['name']} on disk is the checked file",
               hashlib.sha256(fh.read()).hexdigest(), f["sha256"])

    # -- the device --
    print("  device", flush=True)
    scenario(lm_time=1.0)
    A.send({"cmd": "genre", "id": "ambient"})
    s = A.until("empty genre: picked", lambda s: s["genre"] == "ambient")
    eq("empty genre: nothing plays, nothing queued, the composer off",
       (s["player"], s["queue"], s["kept_total"], s["composing"], model(s)["state"]),
       ("none", [], 0, False, "unloaded"))
    eq("empty genre: nothing composed by itself", [e for e in A.quiet(1.0)
                                                   if e.get("composing") or e.get("job")], [])
    eq("empty genre: no device looked up", os.path.exists(os.path.join(CTL, "vulkaninfo.log")), False)
    put("vulkaninfo.crash", "")
    A.send({"cmd": "compose", "on": True})
    s = A.until("device: absent is no_device", lambda s: model(s)["state"] == "no_device")
    eq("device: what was found", model(s)["detail"],
       "found 1 other Vulkan GPU: AMD Radeon RX 6800 XT (RADV NAVI21)")
    eq("device: no server started", [e for e in ace_log() if e["kind"] == "start"], [])
    eq("device: the genre is picked, the switch stays on", (s["genre"], s["composing"]),
       ("ambient", True))
    with open(os.path.join(CTL, "vulkaninfo.log")) as f:
        eq("device: vulkaninfo runs without DISPLAY or WAYLAND_DISPLAY",
           f.read().splitlines(), ["--summary"])
    t = A.ask_timers()
    eq("device: no retry armed", [n for n in t["timers"] if n == "retry"], [])

    put("vulkaninfo.txt", fixture("vulkaninfo-igpu-first.txt"))
    put("ggml.txt", "ggml_vulkan: Found 2 Vulkan devices:\nggml_vulkan: 0 = AMD Radeon 780M Graphics "
        "(RADV PHOENIX) (radv) | uma: 1\nggml_vulkan: 1 = AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
    A.send({"cmd": "retry"})
    A.until("device: llvmpipe first, writing on Vulkan0 (vulkaninfo crashing after its output)",
            lambda s: model(s)["state"] == "writing")
    os.unlink(os.path.join(CTL, "vulkaninfo.crash"))
    starts = [e for e in ace_log() if e["kind"] == "start"]
    argv = starts[-1]["argv"] if starts else []
    eq("device: --device Vulkan0", argv[argv.index("--device") + 1] if "--device" in argv else None,
       "Vulkan0")
    eq("server: on loopback", argv[argv.index("--host") + 1] if "--host" in argv else None,
       "127.0.0.1")
    eq("server: the models directory", argv[argv.index("--models") + 1] if "--models" in argv else None,
       MODELS)
    check("server: never --keep-loaded", "--keep-loaded" not in argv)
    pid = starts[-1]["pid"] if starts else 0
    try:
        def nice_of(p):
            with open(f"/proc/{p}/stat") as f:
                return int(f.read().rsplit(")", 1)[1].split()[16])
        eq("server: niced by 10", nice_of(pid), min(19, nice_of(serve.pid) + 10))
    except FileNotFoundError:
        check("server: niced", False, "no process")
    s = A.until("server: memory in use is reported", lambda s: model(s)["ram_used_bytes"] is not None, 5)
    check("server: memory figure is the RSS at least", model(s)["ram_used_bytes"] > 1_000_000)

    s = A.until("job: writing", lambda s: s["job"] and s["job"]["stage"] == "writing", 5)
    j = s["job"]
    check("job: started now, nothing timed yet, nothing written",
          abs(j["started"] - time.time()) < 3 and j["expect_s"] is None and j["written_s"] is None, j)
    eq("job: no medians yet", s["expect"], None)
    A.send({"cmd": "compose", "on": False})
    s = A.until("switch off: unloaded", lambda s: model(s)["state"] == "unloaded")
    eq("switch off: no job, the switch off", (s["job"], s["composing"]), (None, False))
    log = ace_log()
    check("switch off: the job is cancelled", any(e.get("path", "").endswith("&cancel=1") for e in log))
    wait("switch off: the server is stopped", lambda: any(e["kind"] == "exit" for e in ace_log()), 5)

    put("vulkaninfo.txt", fixture("vulkaninfo-egpu-first.txt"))
    put("ggml.txt", "ggml_vulkan: Found 2 Vulkan devices:\nggml_vulkan: 0 = AMD Radeon RX 6800 XT "
        "(RADV NAVI21) (radv)\nggml_vulkan: 1 = AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
    A.send({"cmd": "compose", "on": True})
    s = A.until("device: the server's card is not the 780M", lambda s: model(s)["state"] == "no_device")
    eq("device: what the server said", model(s)["detail"],
       "the server's Vulkan1 is AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
    put("ggml.txt", "\n".join(GGML_TWO))
    A.send({"cmd": "retry"})
    A.until("device: eGPU first, writing on Vulkan1", lambda s: model(s)["state"] == "writing")
    argv = [e for e in ace_log() if e["kind"] == "start"][-1]["argv"]
    eq("device: --device Vulkan1", argv[argv.index("--device") + 1], "Vulkan1")

    # -- genre change, kept tunes first, the two-step job and the queue --
    print("  queue", flush=True)
    scenario(lm_time=0.4, synth_time=0.4)
    n_lm = len([e for e in ace_log() if e.get("path") == "/lm"])
    ambient_job = [e for e in ace_log() if e.get("path") == "/lm"][-1]
    A.send({"cmd": "genre", "id": "lofi"})
    s = A.until("genre: a kept tune plays at once", lambda s: s["player"] == "playing" and s["tune"])
    eq("genre: it is kept", (s["tune"]["kept"], s["kept_playing"]), (True, True))
    check("genre: one of this genre's kept tunes",
          (s["tune"]["bpm"], s["tune"]["key"]) in ((80, "A minor"), (84, "D major")), s["tune"])
    check("genre: the previous job is cancelled",
          any(e.get("path", "").endswith("&cancel=1") and e["t"] > ambient_job["t"] for e in ace_log()))
    eq("genre: the switch goes off", (s["composing"], model(s)["state"], s["job"]),
       (False, "unloaded", None))
    wait("genre: the server is stopped", lambda: ace_log()[-1]["kind"] == "exit", 5)
    s = A.until("kept mode: the other kept tune is next", lambda s: len(s["queue"]) == 1)
    q = s["queue"][0]
    eq("kept mode: one kept entry", (q["kept"], s["kept_total"], s["ready"], s["can_next"]),
       (True, 2, 0, True))
    check("kept mode: the other kept tune", {(q["bpm"], q["key"]), (s["tune"]["bpm"], s["tune"]["key"])}
          == {(80, "A minor"), (84, "D major")}, (q, s["tune"]))
    n_lm = len([e for e in ace_log() if e.get("path") == "/lm"])
    A.quiet(1.0)
    eq("kept mode: nothing composed", len([e for e in ace_log() if e.get("path") == "/lm"]), n_lm)
    s = A.until("kept tune: its title and wave from the file",
                lambda s: s["tune"] and s["tune"]["name"].startswith("Invented Old") and
                len(s["tune"]["wave"]) == 78)
    check("kept tune: its length", abs((s["tune"]["length"] or 0) - 90) < 0.5, s["tune"])
    A.send({"cmd": "compose", "on": True})
    s = A.until("switch on: composing", lambda s: s["composing"] and s["job"], 10)
    s = A.until("job: rendering, with how long writing took",
                lambda s: s["job"] and s["job"]["stage"] == "rendering", 10)
    check("job: written_s set while rendering", s["job"]["written_s"] is not None
          and 0 < s["job"]["written_s"] < 5, s["job"])
    s = A.until("job: the second tune has an expectation",
                lambda s: s["job"] and s["job"]["expect_s"] is not None, 20)
    check("expect: both medians once one tune is timed", s["expect"] and
          set(s["expect"]) == {"writing_s", "rendering_s"}, s["expect"])
    eq("expect: job.expect_s is the writing median while writing",
       s["job"]["expect_s"], s["expect"][s["job"]["stage"] + "_s"])
    s = A.until("job: the second tune rendering", lambda s: s["job"] and s["job"]["stage"] == "rendering"
                and s["job"]["expect_s"] is not None, 20)
    eq("expect: job.expect_s is the rendering median while rendering",
       s["job"]["expect_s"], s["expect"]["rendering_s"])
    check("expect: the two medians differ here, so the stage matters",
          s["expect"]["rendering_s"] != s["expect"]["writing_s"], s["expect"])
    s = A.until("queue: two new tunes", lambda s: s["ready"] == 2 and model(s)["state"] == "idle", 40)
    eq("queue: next offered, no job while resting", (s["can_next"], s["job"]), (True, None))
    eq("queue: the queued new tunes, named", [(e["kept"], bool(e["name"]), isinstance(e["bpm"], int),
                                               isinstance(e["length"], float)) for e in s["queue"]],
       [(False, True, True, True)] * 2)
    check("expect: kept outside a job", s["expect"] is not None, s["expect"])
    log = ace_log()
    reqs = [e for e in log if e["kind"] == "req"][n_lm:]
    lm = [e for e in log if e.get("path") == "/lm"][n_lm:]
    synth = [e for e in log if e.get("path") == "/synth"]
    check("job: two plans written", len(lm) >= 2, len(lm))
    body = lm[0]["body"]
    check("job: the caption", body["caption"].startswith(genres[0]["caption"] + ", ")
          and body["caption"].endswith(", instrumental"), body["caption"])
    eq("job: instrumental, the duration", (body["lyrics"], body["duration"]), ("[Instrumental]", 12))
    check("job: bpm in the genre's range", genres[0]["bpm"][0] <= body["bpm"] <= genres[0]["bpm"][1])
    sb = synth[-1]["body"]
    eq("job: the plan goes to /synth as WAV", (sb["output_format"], sb["codes_n"], sb["lyrics"]),
       ("wav16", 60, "[Instrumental]"))
    check("job: the plan is sent unchanged", sb["caption"].startswith("The model's own words"))
    paths = [e["path"] for e in reqs]
    i_lm = paths.index("/lm")
    polls = 0
    for pth in paths[i_lm + 1:]:
        if pth.endswith("&result=1"):
            break
        polls += pth.startswith("/job?id=")
    check("job: polled before the result", polls >= 2, paths[:12])
    eq("job: then synth", paths[paths.index(next(p for p in paths if p.endswith("&result=1"))) + 1],
       "/synth")
    gaps = []
    poll_t = [e["t"] for e in reqs if e["path"].startswith("/job?id=") and "result" not in e["path"]]
    gaps = [b - a for a, b in zip(poll_t, poll_t[1:]) if b - a < 1]
    check("job: polled every 0.5 s (scaled)", gaps and min(gaps) > 0.5 * SCALE * 0.8, gaps[:5])
    new = [n for n in kept_files("Lo-fi") if os.path.join(MUSIC, "Lo-fi", n) not in LOFI_KEPT]
    eq("files: two new tunes on disk", len(new), 2)
    if new:
        tg, length = tags(os.path.join(MUSIC, "Lo-fi", new[-1]))
        check("files: tagged", tg.get("genre") == "Lo-fi" and tg.get("title")
              and tg.get("tbpm", "").isdigit(), tg)
        check("files: the silent tail cut (12 s plan, 2 s tail)", abs(length - 10.0) < 0.2, length)
        check("files: wave cached", os.path.exists(os.path.join(
            XDG["XDG_CACHE_HOME"], "desk-tunes", "wave", "lofi", new[-1] + ".json")))
    n_lm = len([e for e in ace_log() if e.get("path") == "/lm"])
    time.sleep(1.5)
    eq("queue: nothing composed beyond two", len([e for e in ace_log() if e.get("path") == "/lm"]), n_lm)
    t = A.ask_timers()
    eq("queue: idle while playing, no timer", t["timers"], [])
    n_start = len([e for e in ace_log() if e["kind"] == "start"])
    A.send({"cmd": "compose", "on": False})
    A.until("full queue: switched off", lambda s: model(s)["state"] == "unloaded")
    A.send({"cmd": "compose", "on": True})
    s = A.until("full queue: on says idle, not unloaded", lambda s: model(s)["state"] == "idle", 5)
    eq("full queue: no server for a full queue", (len([e for e in ace_log() if e["kind"] == "start"]),
                                                 s["ready"]), (n_start, 2))

    first_queued = s["queue"][0]["name"]
    A.send({"cmd": "next"})
    s = A.until("next: a new tune", lambda s: s["tune"] and not s["tune"]["kept"])
    eq("next: the head of the queue, not kept", (s["tune"]["name"], s["kept_playing"]),
       (first_queued, False))
    check("next: its length is the cut one", abs(s["tune"]["length"] - 10.0) < 0.2, s["tune"]["length"])
    eq("next: a 78-bar wave scaled to 1", (len(s["tune"]["wave"]), max(s["tune"]["wave"])), (78, 1.0))
    tg, _ = tags(os.path.join(MUSIC, "Lo-fi", new[0]))
    eq("next: the name is the file's title", s["tune"]["name"], tg.get("title"))
    A.until("next: composing again", lambda s: model(s)["state"] in ("writing", "rendering"), 5)
    A.send({"cmd": "toggle"})
    s = A.until("toggle: paused", lambda s: s["player"] == "paused")
    pos = s["pos"]
    s = A.until("paused: the queue is filled", lambda s: s["ready"] == 2 and model(s)["state"] == "idle", 30)
    n_lm = len([e for e in ace_log() if e.get("path") == "/lm"])
    time.sleep(1.5)
    eq("paused: no more than the queue", len([e for e in ace_log() if e.get("path") == "/lm"]), n_lm)
    A.send({"cmd": "refresh"})
    s = A.until("paused: position holds", lambda s: s["player"] == "paused", 5)
    check("paused: position holds", abs(s["pos"] - pos) < 0.3, (pos, s["pos"]))
    A.send({"cmd": "seek", "t": 4.0})
    s = A.until("seek: the position", lambda s: abs(s["pos"] - 4.0) < 0.3, 5)
    A.send({"cmd": "toggle"})
    A.until("toggle: playing", lambda s: s["player"] == "playing")

    # -- keep: 4 per genre in this config --
    files_now = kept_files("Lo-fi")
    eq("keep: four of ours per genre", len(files_now), 4)
    check("keep: other files untouched", all(os.path.exists(p) for p in FOREIGN))
    check("keep: the oldest kept tune went first", not os.path.exists(LOFI_KEPT[0])
          or not os.path.exists(LOFI_KEPT[1]) or len(files_now) == 4)

    # -- state.json --
    with open(STATE) as f:
        st = json.load(f)
    eq("state: only the timings", sorted(st), ["rendering", "writing"])
    check("state: one entry per finished tune", len(st["writing"]) == len(st["rendering"]) >= 3, st)
    s = A.until("state: the medians reported are the file's",
                lambda s: s["expect"] == dt.expect_view(dt.read_timings(st)), 5)
    ino = os.stat(STATE).st_ino
    mtime = os.stat(STATE).st_mtime_ns
    A.send({"cmd": "toggle"})
    A.send({"cmd": "toggle"})
    A.send({"cmd": "refresh"})
    A.quiet(0.5)
    eq("state: not written without a change", (os.stat(STATE).st_ino, os.stat(STATE).st_mtime_ns),
       (ino, mtime))

    # -- MPRIS --
    print("  MPRIS", flush=True)
    players = playerctl("-l").stdout.split()
    name = next((p for p in players if "desk-tunes" in p), None)
    check("mpris: the player is on the bus", name, players)
    if name:
        s = A.until("mpris: playing", lambda s: s["player"] == "playing", 5)
        eq("mpris: Identity is desk-tunes", playerctl("-p", name, "metadata", "--format",
                                                      "{{playerName}}").returncode, 0)
        eq("mpris: the title", playerctl("-p", name, "metadata", "title").stdout.strip(),
           s["tune"]["name"])
        playerctl("-p", name, "pause")
        A.until("mpris: pause", lambda s: s["player"] == "paused", 5)
        playerctl("-p", name, "play")
        A.until("mpris: play", lambda s: s["player"] == "playing", 5)
        s = A.until("mpris: a tune is next", lambda s: s["ready"] >= 1, 30)
        nxt = s["queue"][0]["name"]
        playerctl("-p", name, "next")
        s = A.until("mpris: next", lambda s: s["tune"] and s["tune"]["name"] == nxt, 5)
        A.send({"cmd": "toggle"})
        A.until("mpris: paused for what follows", lambda s: s["player"] == "paused", 5)

    # -- next on kept tunes, unloaded; same genre ignored; idle --
    print("  kept tunes and idle", flush=True)
    lofi_before = kept_files("Lo-fi")
    A.until("paused before a pick", lambda s: s["player"] == "paused", 5)
    A.send({"cmd": "genre", "id": "jazz"})
    s = A.until("pick after a pause: kept tunes play, not paused", lambda s: s["genre"] == "jazz"
                and s["tune"] and s["tune"]["kept"] and s["player"] == "playing")
    eq("pick after a pause: not stopped, the composer off", (s["stopped"], s["composing"]),
       (False, False))
    eq("genre change: the old queue is dropped", s["ready"], 0)
    eq("genre change: the old genre's files stay", kept_files("Lo-fi"), lofi_before)
    first = s["tune"]["bpm"]
    eq("next: offered with another kept tune", s["can_next"], True)
    A.send({"cmd": "next"})
    s = A.until("next: the next kept tune", lambda s: s["tune"] and s["tune"]["bpm"] != first, 5)
    eq("next: still kept", (s["tune"]["kept"], s["kept_playing"]), (True, True))
    A.send({"cmd": "next"})
    A.until("next: and round again", lambda s: s["tune"] and s["tune"]["bpm"] == first, 5)
    A.until("kept tune: its title read", lambda s: s["tune"]["name"].startswith("Invented"), 10)
    A.quiet(0.3)
    A.send({"cmd": "genre", "id": "jazz"})
    eq("genre: the one already picked is ignored", A.quiet(0.8), [])
    t = wait("idle while playing, unloaded: no timer",
             lambda: (lambda t: t if t["timers"] == [] else None)(A.ask_timers()), 10)
    A.send({"cmd": "toggle"})
    A.until("paused", lambda s: s["player"] == "paused")
    t = wait("idle, unloaded and paused: no timer",
             lambda: (lambda t: t if t["timers"] == [] and t["threads"] == 1 else None)(A.ask_timers()), 10)
    check("idle: no timer, one thread", t, t)
    A.send({"cmd": "toggle"})
    A.until("playing", lambda s: s["player"] == "playing")
    mp3(os.path.join(MUSIC, "Classical", "20260105-100000-70bpm-G-major.mp3"), 90, "Invented Lone Hall")
    A.send({"cmd": "genre", "id": "classical"})
    s = A.until("one kept tune: its title read", lambda s: s["genre"] == "classical" and s["tune"]
                and s["tune"]["name"] == "Invented Lone Hall" and s["player"] == "playing", 10)
    eq("one kept tune: next not offered", s["can_next"], False)
    A.send({"cmd": "next"})
    eq("one kept tune: next does nothing", A.quiet(0.8), [])

    # -- silence: rewrite, three in a row; retry timing --
    print("  silence and failures", flush=True)
    A.send({"cmd": "genre", "id": "ambient"})
    s = A.until("pick of a genre with nothing kept: the old tune leaves the player",
                lambda s: s["genre"] == "ambient" and s["player"] == "none")
    eq("pick of a genre with nothing kept: nothing queued, not stopped", (s["queue"], s["stopped"]),
       ([], False))
    scenario(lm=["silent", "ok"], lm_time=0.3, synth_time=0.3)
    A.send({"cmd": "compose", "on": True})
    s = A.until("silence: writing again", lambda s: model(s)["state"] == "writing"
                and model(s)["silence_s"] == 6)
    s = A.until("switch on: the first finished tune starts by itself",
                lambda s: s["tune"] and not s["tune"]["kept"] and s["player"] == "playing")
    eq("silence: cleared after", model(s)["silence_s"], None)
    A.until("ambient: two ready", lambda s: s["ready"] == 1 and model(s)["state"] == "idle"
            or s["ready"] == 2, 30)
    A.send({"cmd": "next"})
    scenario(lm=["silent", "silent", "silent"], lm_time=0.2)
    s = A.until("silence: three plans fail", lambda s: model(s)["state"] == "failed", 30)
    eq("failure: the detail", model(s)["detail"], "3 plans in a row had long silences")
    eq("failure: counted", model(s)["failures"], 1)
    check("failure: first retry after 3 s (scaled)",
          abs(model(s)["retry_at"] - model(s)["since"] - 3 * SCALE) < 0.15, model(s))
    eq("failure: the player is unaffected", s["player"], "playing")
    scenario(lm=["fail", "fail"], lm_time=0.2)
    s = A.until("failure: retried and failed again", lambda s: model(s)["failures"] == 2, 10)
    eq("failure: the server's own message", model(s)["detail"],
       "the song job failed: [Server] FATAL: simulated failure")
    check("failure: then every 30 s (scaled)",
          abs(model(s)["retry_at"] - model(s)["since"] - 30 * SCALE) < 0.15, model(s))
    A.send({"cmd": "retry"})
    s = A.until("retry: tries now", lambda s: model(s)["failures"] == 3, 5)
    scenario(synth=["quiet"], lm_time=0.2, synth_time=0.2)
    count = len(kept_files("Ambient"))
    A.send({"cmd": "retry"})
    s = A.until("backstop: a quiet render fails", lambda s: model(s)["state"] == "failed"
                and model(s)["failures"] == 4, 10)
    check("backstop: the detail", "silent for 7 s in the middle" in (model(s)["detail"] or ""),
          model(s)["detail"])
    eq("backstop: the file is discarded", len(kept_files("Ambient")), count)
    scenario(synth=["exit"], synth_time=0.2, lm_time=0.2)
    A.send({"cmd": "retry"})
    s = A.until("crash: the server dies", lambda s: model(s)["failures"] == 5, 10)
    check("crash: its last message", "Device lost" in (model(s)["detail"] or ""), model(s)["detail"])
    scenario(lm_time=0.2, synth_time=0.2)
    A.send({"cmd": "retry"})
    s = A.until("failure: a finished tune resets the count", lambda s: model(s)["failures"] == 0
                and model(s)["retry_at"] is None, 15)

    # -- holds --
    print("  holds", flush=True)
    A.send({"cmd": "next"})
    scenario(lm_time=3.0, synth_time=0.2)
    A.until("hold: a job runs", lambda s: model(s)["state"] == "writing", 15)
    n_hypr = len(open(os.path.join(CTL, "hyprctl.log")).read().splitlines())
    put("clients.json", json.dumps([{"class": "kitty"}, {"class": "steam_app_1245620"}]))
    t0 = time.time()
    s = A.until("hold: a game during a job", lambda s: model(s)["state"] == "held_game", 5)
    check("hold: within 10 s (scaled)", time.time() - t0 < 10 * SCALE + 0.5, time.time() - t0)
    lm_ids = [e for e in ace_log() if e.get("path", "").endswith("&cancel=1")]
    check("hold: the job is cancelled", lm_ids and lm_ids[-1]["t"] >= t0 - 0.1)
    wait("hold: the server is stopped", lambda: ace_log()[-1]["kind"] == "exit", 5)
    eq("hold: no server memory", model(s)["ram_used_bytes"], None)
    eq("hold: the switch stays on, no job", (s["composing"], s["job"]), (True, None))
    eq("hold: the player is unaffected", s["player"], "playing")
    lines = open(os.path.join(CTL, "hyprctl.log")).read().splitlines()
    eq("hold: hyprctl -i 0 with no instance signature", lines[-1], "-i 0 -j clients")
    check("hold: hyprctl polled while running", len(lines) > n_hypr)
    eq("hold: a hold check armed", "hold_check" in A.ask_timers()["timers"], True)
    put("clients.json", json.dumps([{"class": "kitty"}]))
    t0 = time.time()
    s = A.until("hold: released by itself", lambda s: model(s)["state"] in ("starting", "writing", "idle"),
                10)
    check("hold: within 30 s (scaled)", time.time() - t0 < 30 * SCALE + 0.5, time.time() - t0)
    scenario(lm_time=0.3, synth_time=0.3)
    put("clients.json", json.dumps([{"class": "Witcher3.exe"}]))
    A.until("hold: a game before a job", lambda s: model(s)["state"] == "held_game", 15)
    put("clients.json", json.dumps([{"class": "kitty"}]))
    A.until("hold: game gone", lambda s: model(s)["state"] != "held_game", 10)
    meminfo(3 * GIB)
    A.send({"cmd": "next"})
    s = A.until("hold: memory short before a job", lambda s: model(s)["state"] == "held_memory", 15)
    eq("hold: the free memory shown", model(s)["ram_free_bytes"], 3 * GIB)
    meminfo(20 * GIB)
    A.until("hold: memory back", lambda s: model(s)["state"] in ("starting", "writing", "rendering", "idle"),
            10)
    put("clients.json", "hyprctl: no instance")
    A.send({"cmd": "next"})
    s = A.until("hold: hyprctl failing is said", lambda s: s["error"] and "hyprctl" in s["error"], 15)
    eq("hold: in plain words", s["error"], "hyprctl cannot list the windows, so a game would not hold composing")
    put("clients.json", json.dumps([{"class": "kitty"}]))
    A.send({"cmd": "next"})
    A.until("hold: cleared when hyprctl works again", lambda s: s["error"] is None, 15)
    A.send({"cmd": "compose", "on": False})
    A.until("switch off", lambda s: model(s)["state"] == "unloaded")
    put("clients.json", json.dumps([{"class": "steam_app_1245620"}]))
    meminfo(3 * GIB)
    n_hypr = len(open(os.path.join(CTL, "hyprctl.log")).read().splitlines())
    A.send({"cmd": "next"})
    A.send({"cmd": "retry"})
    got = [model(e).get("state") for e in A.quiet(1.0) if e.get("event") == "state"]
    eq("holds only while on: no hold with the switch off", [x for x in got if x != "unloaded"], [])
    eq("holds only while on: hyprctl not asked", len(open(os.path.join(CTL, "hyprctl.log"))
                                                     .read().splitlines()), n_hypr)
    put("clients.json", json.dumps([{"class": "kitty"}]))
    meminfo(20 * GIB)

    # -- the genres file --
    print("  genres file", flush=True)
    data = json.loads(REAL_GENRES_TEXT)
    data["genres"][0]["name"] = "Invented Lo-fi Two"
    with open(LIVE_GENRES + ".tmp", "w") as f:
        json.dump(data, f)
    os.replace(LIVE_GENRES + ".tmp", LIVE_GENRES)
    A.send({"cmd": "refresh"})
    s = A.until("genres: a change on disk is read", lambda s: s["genres"][0]["name"] == "Invented Lo-fi Two", 5)
    with open(LIVE_GENRES, "w") as f:
        f.write('{"genres": [')
    A.send({"cmd": "refresh"})
    s = A.until("genres: a broken file is reported", lambda s: s["error"], 5)
    check("genres: the error says which file", "tunes-genres.json" in s["error"], s["error"])
    eq("genres: the last good list stays", s["genres"][0]["name"], "Invented Lo-fi Two")
    shutil.copy(GENRES, LIVE_GENRES)
    A.send({"cmd": "refresh"})
    s = A.until("genres: fixed", lambda s: s["error"] is None and s["genres"][0]["name"] == "Lo-fi", 5)
    A.send({"cmd": "genre", "id": "synthwave"})
    A.until("genre", lambda s: s["genre"] == "synthwave")

    # -- MPRIS stop --
    if name:
        A.send({"cmd": "genre", "id": "jazz"})
        A.until("jazz again", lambda s: s["genre"] == "jazz" and s["player"] == "playing")
        playerctl("-p", name, "stop")
        A.until("mpris: stop", lambda s: s["player"] == "none", 5)
        eq("mpris: nothing plays by itself after stop", [e for e in A.quiet(1.0)
                                                         if e.get("player") == "playing"], [])
        eq("mpris: stop is reported as stopped", A.last["stopped"], True)
        A.send({"cmd": "toggle"})
        A.until("toggle: plays again after a stop", lambda s: s["player"] == "playing", 5)
        eq("toggle: no longer stopped", A.last["stopped"], False)

        # A pick starts clean: neither a stop nor a pause carries to the new genre.
        for how, kept_genre, empty_genre in (("stopped", "lofi", "deephouse"),
                                             ("paused", "classical", "acoustic")):
            for target, has_kept in ((kept_genre, True), ("jazz", True), (empty_genre, False)):
                A.until(f"{how}: something plays", lambda s: s["player"] == "playing", 5)
                if how == "stopped":
                    playerctl("-p", name, "stop")
                    A.until(f"{how}: stopped", lambda s: s["stopped"] and s["player"] == "none", 5)
                else:
                    A.send({"cmd": "toggle"})
                    A.until(f"{how}: paused", lambda s: s["player"] == "paused", 5)
                A.send({"cmd": "genre", "id": target})
                want = "playing" if has_kept else "none"
                s = A.until(f"{how} then a pick of {target}: {want}, not stopped",
                            lambda s: s["genre"] == target and s["player"] == want
                            and s["stopped"] is False, 5)
                if not has_kept:
                    eq(f"{how} then a pick of {target}: stays clean",
                       [(e["player"], e["stopped"]) for e in A.quiet(0.8) if e.get("event") == "state"
                        and (e["player"], e["stopped"]) != ("none", False)], [])
                    A.send({"cmd": "genre", "id": "jazz"})

    # -- keep: the playing and the next kept tune are never deleted --
    print("  keep and mpv", flush=True)
    DT = os.path.join(MUSIC, "Downtempo")
    DT_OLD = [os.path.join(DT, "20260101-090000-90bpm-A-minor.mp3"),
              os.path.join(DT, "20260102-090000-92bpm-D-minor.mp3")]
    for p in DT_OLD:
        mp3(p, 90, "Invented Slow Hour")
    A.send({"cmd": "genre", "id": "downtempo"})
    A.until("keep: an old kept tune plays, the other is next",
            lambda s: s["genre"] == "downtempo" and s["tune"] and s["tune"]["kept"]
            and s["player"] == "playing" and s["can_next"])
    DT_NEWER = [os.path.join(DT, "20260601-090000-90bpm-A-minor.mp3"),
                os.path.join(DT, "20260602-090000-90bpm-A-minor.mp3")]
    for p in DT_NEWER:
        mp3(p, 5, "Invented Short Hour")
    ino = os.stat(STATE).st_ino
    scenario(lm_time=0.3, synth_time=0.3)
    A.send({"cmd": "compose", "on": True})
    A.until("keep: a new tune finishes", lambda s: s["ready"] >= 1, 30)
    A.send({"cmd": "compose", "on": False})
    eq("keep: the playing and the next kept tune survive, the oldest other goes",
       [os.path.exists(p) for p in DT_OLD + DT_NEWER], [True, True, False, True])
    eq("keep: four of ours", len(kept_files("Downtempo")), 4)
    check("state: replaced, not rewritten in place", os.stat(STATE).st_ino != ino)
    eq("state: no temporary left", os.listdir(os.path.dirname(STATE)), ["state.json"])
    A.until("keep: unloaded", lambda s: model(s)["state"] == "unloaded")

    # -- scrap, undo and play --
    print("  scrap and play", flush=True)
    SCR = os.path.join(XDG["XDG_CACHE_HOME"], "desk-tunes", "scrapped")

    def scrapped():
        try:
            return sorted(os.listdir(SCR))
        except FileNotFoundError:
            return []

    def names(s):
        return [e["name"] for e in s["queue"]]

    A.send({"cmd": "genre", "id": "jazz"})
    s = A.until("scrap kept: jazz plays with its other kept tune next",
                lambda s: s["genre"] == "jazz" and s["player"] == "playing" and len(s["queue"]) == 1
                and s["queue"][0]["kept"] and s["kept_total"] == 2, 10)
    A.send({"cmd": "scrap", "i": 0})
    s = A.until("scrap kept: the queue entry leaves", lambda s: s["undo"], 5)
    eq("scrap kept: one kept left, the file set aside", (s["kept_total"], len(scrapped())), (1, 1))
    check("scrap kept: undo for 10 s (scaled)",
          abs(s["undo"]["until"] - time.time() - 10 * SCALE) < 0.5, s["undo"])
    A.send({"cmd": "undo"})
    s = A.until("undo kept: back at the head of the queue", lambda s: s["undo"] is None, 5)
    eq("undo kept: the file is back", (s["kept_total"], scrapped(), s["queue"][0]["kept"]), (2, [], True))

    A.send({"cmd": "genre", "id": "downtempo"})
    scenario(lm_time=0.3, synth_time=0.3)
    A.until("scrap: downtempo", lambda s: s["genre"] == "downtempo" and s["player"] == "playing", 5)
    A.send({"cmd": "compose", "on": True})
    s = A.until("scrap: two ready", lambda s: s["ready"] == 2 and model(s)["state"] == "idle", 30)
    q = names(s)
    A.send({"cmd": "play", "i": 1})
    s = A.until("play i: queue entry 1 plays now", lambda s: s["tune"] and s["tune"]["name"] == q[1], 5)
    eq("play i: the rest keeps its order", names(s)[:1], q[:1])
    # Paused, so a 10 s tune cannot end and shift the queue under the scraps below.
    A.send({"cmd": "toggle"})
    A.until("scrap: paused", lambda s: s["player"] == "paused", 5)

    s = A.until("scrap: two ready again", lambda s: s["ready"] == 2 and model(s)["state"] == "idle", 30)
    # Slow plans from here, so no tune finishes (and prunes) between a scrap and its checks.
    scenario(lm_time=3.0, synth_time=0.3)
    q, playing, count = names(s), s["tune"]["name"], len(kept_files("Downtempo"))
    A.send({"cmd": "scrap", "i": 1})
    s = A.until("scrap i: the entry leaves the queue at once", lambda s: s["undo"], 5)
    eq("scrap i: undo names it, the rest stays", (s["undo"]["name"], names(s)[:1]), (q[1], q[:1]))
    check("scrap i: gone from the queue", q[1] not in names(s), names(s))
    eq("scrap i: the file moved aside", (len(kept_files("Downtempo")), len(scrapped())), (count - 1, 1))
    A.send({"cmd": "undo"})
    s = A.until("undo: back at the head of the queue", lambda s: s["undo"] is None
                and names(s) and names(s)[0] == q[1], 5)
    eq("undo: the file is back, what plays is unchanged",
       (len(kept_files("Downtempo")), scrapped(), s["tune"]["name"]), (count, [], playing))

    s = A.until("scrap: resting", lambda s: model(s)["state"] == "idle", 30)
    scenario(lm_time=0.3, synth_time=0.3)
    q = names(s)
    A.send({"cmd": "scrap", "i": 0})
    s = A.until("finalise: scrapped", lambda s: s["undo"], 5)
    gone = scrapped()
    wave = os.path.join(XDG["XDG_CACHE_HOME"], "desk-tunes", "wave", "downtempo", gone[0] + ".json") \
        if gone else ""
    check("finalise: the wave cache is there while undo is possible", os.path.exists(wave), wave)
    t0 = time.time()
    s = A.until("finalise: the undo lapses", lambda s: s["undo"] is None, 10)
    check("finalise: after 10 s (scaled)", 10 * SCALE - 0.3 < time.time() - t0 < 10 * SCALE + 1,
          time.time() - t0)
    eq("finalise: the file and its wave cache are deleted", (scrapped(), os.path.exists(wave)), ([], False))
    check("finalise: not in the genre folder either", gone and gone[0] not in kept_files("Downtempo"))
    eq("finalise: no scrap timer left", "scrap" in A.ask_timers()["timers"], False)

    s = A.until("second scrap: two queued", lambda s: len(s["queue"]) >= 2, 30)
    q = names(s)
    A.send({"cmd": "scrap", "i": 0})
    A.until("second scrap: the first", lambda s: s["undo"] and s["undo"]["name"] == q[0], 5)
    first = scrapped()
    A.send({"cmd": "scrap", "i": 0})
    s = A.until("second scrap: the second", lambda s: s["undo"] and s["undo"]["name"] == q[1], 5)
    check("second scrap: the first is deleted at once", len(scrapped()) == 1 and scrapped() != first,
          (first, scrapped()))
    A.send({"cmd": "undo"})
    s = A.until("second scrap: undo brings back the second", lambda s: s["undo"] is None
                and names(s)[0] == q[1], 5)

    playing, nxt = s["tune"]["name"], names(s)[0]
    A.send({"cmd": "scrap"})
    s = A.until("scrap playing: the next starts at once", lambda s: s["tune"]
                and s["tune"]["name"] == nxt and s["player"] == "playing", 5)
    eq("scrap playing: undo names it", s["undo"]["name"], playing)
    A.send({"cmd": "undo"})
    s = A.until("undo playing: at the head of the queue, not interrupting",
                lambda s: s["undo"] is None and names(s)[0] == playing, 5)
    eq("undo playing: what plays is unchanged", (s["tune"]["name"], s["player"]), (nxt, "playing"))

    scenario(lm_time=2.0, synth_time=0.3)
    for _ in range(4):
        if A.last["job"]:
            break
        A.send({"cmd": "scrap", "i": 0})
        A.quiet(0.4)
    s = A.until("scrap job: a job runs", lambda s: s["job"] and s["job"]["stage"] == "writing", 10)
    undo = s["undo"]
    t0 = time.time()
    n_lm = len([e for e in ace_log() if e.get("path") == "/lm"])
    A.send({"cmd": "scrap", "job": True})
    wait("scrap job: cancelled and another started",
         lambda: any(e.get("path", "").endswith("&cancel=1") and e["t"] >= t0 for e in ace_log())
         and len([e for e in ace_log() if e.get("path") == "/lm"]) > n_lm, 5)
    s = A.until("scrap job: writing again", lambda s: s["job"] and s["job"]["stage"] == "writing", 5)
    check("scrap job: no undo of its own", s["undo"] is None if undo is None
          else s["undo"] is None or s["undo"]["name"] == undo["name"], (undo, s["undo"]))
    A.send({"cmd": "compose", "on": False})
    A.until("scrap: switched off", lambda s: not s["composing"] and s["job"] is None, 5)
    A.until("scrap: undo lapsed", lambda s: s["undo"] is None, 10)

    # -- mpv exiting: restarted after a pause, the service lives on --
    for i in range(3):
        A.until(f"mpv {i}: playing", lambda s: s["player"] == "playing", 15)
        pid = wait(f"mpv {i}: running", mpv_pid, 5)
        t0 = time.time()
        os.kill(pid, signal.SIGKILL)
        A.until(f"mpv {i}: nothing plays once it is gone", lambda s: s["player"] == "none", 5)
        if i == 0:
            eq("mpv: a restart is armed", "mpv_restart" in A.ask_timers()["timers"], True)
        new = wait(f"mpv {i}: started again", lambda: (lambda p: p if p and p != pid else None)(mpv_pid()), 10)
        check(f"mpv {i}: not before 2 s (scaled)", time.time() - t0 >= 2 * SCALE - 0.05, time.time() - t0)
        check(f"mpv {i}: the service lives on", serve.poll() is None)
        A.until(f"mpv {i}: playing again", lambda s: s["player"] == "playing", 10)

    # -- a tune mpv cannot play: said, nothing more tried, cleared by a tune that plays --
    BAD = os.path.join(MUSIC, "Post-rock", "20260106-100000-90bpm-E-minor.mp3")
    os.makedirs(os.path.dirname(BAD), exist_ok=True)
    with open(BAD, "w") as f:
        f.write("this is not audio")
    A.send({"cmd": "genre", "id": "postrock"})
    s = A.until("mpv error: said in error, and nothing plays", lambda s: s["genre"] == "postrock"
                and s["error"] and s["player"] == "none", 10)
    eq("mpv error: mpv's reason", s["error"], "mpv could not play the tune: unrecognized file format")
    eq("mpv error: nothing more tried", [e for e in A.quiet(1.0) if e.get("player") == "playing"], [])
    A.send({"cmd": "genre", "id": "jazz"})
    A.until("mpv error: cleared once a tune plays", lambda s: s["player"] == "playing" and s["error"] is None, 10)

    # -- writes stay inside the unit's directories --
    allowed = [os.path.join(XDG["XDG_STATE_HOME"], "desk-tunes"),
               os.path.join(XDG["XDG_CACHE_HOME"], "desk-tunes"),
               os.path.join(XDG["XDG_DATA_HOME"], "desk-tunes"), MUSIC, LIVE_GENRES]
    stray = []
    for root, dirs, fs in os.walk(HOME):
        for n in fs:
            p = os.path.join(root, n)
            if not any(p == a or p.startswith(a + "/") for a in allowed):
                stray.append(p)
    eq("sandbox: nothing written outside the unit's directories", stray, [])
    rt = sorted(os.listdir(RUNTIME))
    eq("sandbox: the runtime directory holds desk-tunes and the test's bus", rt, ["bus", "desk-tunes"])

    # -- shutdown --
    print("  shutdown", flush=True)
    B = Client()
    B.until("B", lambda s: True, 5)
    serve.send_signal(signal.SIGTERM)
    eq("serve: exits 0 on SIGTERM", serve.wait(15), 0)
    eq("attach: the socket closing exits 1", A.proc.wait(10), 1)
    eq("attach: says so", A.proc.stderr.read().decode(), "the tunes service closed the connection\n")
    check("serve: the socket is removed", not os.path.exists(SOCK))
    out = subprocess.run(["playerctl", "-l"], env=ENV, capture_output=True, text=True)
    check("serve: mpv is gone", "desk-tunes" not in out.stdout, out.stdout)

    # -- a restart: nothing plays by itself, the state is read back --
    print("  restart", flush=True)
    with open(STATE) as f:
        st = json.load(f)
    ino, mtime = os.stat(STATE).st_ino, os.stat(STATE).st_mtime_ns
    os.makedirs(SCR, exist_ok=True)
    LEFT = os.path.join(SCR, "20260101-000000-80bpm-C-major.mp3")
    with open(LEFT, "w") as f:
        f.write("a scrap the last run never finalised")
    serve = subprocess.Popen(serve.args, env=ENV, stdout=subprocess.DEVNULL, stderr=SERVE_LOG)
    wait("restart: the socket appears", lambda: os.path.exists(SOCK), 10)
    A = Client(attach=True)
    s = A.until("restart: a snapshot", lambda s: True, 5)
    eq("restart: nothing plays by itself, the composer off",
       (s["genre"], s["player"], model(s)["state"], s["composing"], s["undo"]),
       (None, "none", "unloaded", False, None))
    eq("restart: scrapped/ is emptied", scrapped(), [])
    eq("restart: the medians are read back", s["expect"], dt.expect_view(dt.read_timings(st)))
    check("restart: ... and there are some", s["expect"] is not None, s["expect"])
    A.send({"cmd": "genre", "id": "jazz"})
    A.until("restart: a genre picked", lambda s: s["genre"] == "jazz")
    A.quiet(0.5)
    eq("state: not written for a pick",
       (os.stat(STATE).st_ino, os.stat(STATE).st_mtime_ns), (ino, mtime))
    serve.send_signal(signal.SIGTERM)
    eq("restart: exits 0", serve.wait(15), 0)
except Exception:
    import traceback
    traceback.print_exc()
    FAILURES.append("exception")
finish()
