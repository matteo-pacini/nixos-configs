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
files = [{"name": "a", "bytes": 10}, {"name": "b", "bytes": 5}]
eq("need: bytes over the whole set", dt.need_bytes(files, {"a": 10, "b": 2}), 3)

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
    f.write(" ".join(sys.argv[1:]) + "\n")
sys.stdout.write(open(os.path.join(os.environ["FAKE_DIR"], "vulkaninfo.txt")).read())
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
           DBUS_SESSION_BUS_ADDRESS=BUS, FAKE_DIR=CTL, FAKE_SILENCE=str(SILENCE))
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
           ("my own song.mp3", "notes.txt", "20260101-000000-80bpm-C-major.mp3.bak")]
for p in FOREIGN:
    with open(p, "w") as f:
        f.write("not ours")

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
    for bad in ('{"cmd":"bogus"}', '{"cmd":"seek","t":"soon"}', '{"cmd":"genre"}', '[1]'):
        A.send(bad)
        ev = A.get(5)
        eq(f"malformed: {bad}", ev and ev.get("event"), "error")
    for cmd in ("next", "toggle", "unload", "retry", "cancel_download"):
        A.send({"cmd": cmd})
    A.send({"cmd": "seek", "t": 10})
    A.send({"cmd": "genre", "id": "no-such-genre"})
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

    # -- the device --
    print("  device", flush=True)
    scenario(lm_time=1.0)
    A.send({"cmd": "genre", "id": "ambient"})
    s = A.until("device: absent is no_device", lambda s: model(s)["state"] == "no_device")
    eq("device: what was found", model(s)["detail"],
       "found 1 other Vulkan GPU: AMD Radeon RX 6800 XT (RADV NAVI21)")
    eq("device: no server started", [e for e in ace_log() if e["kind"] == "start"], [])
    eq("device: the genre is picked", s["genre"], "ambient")
    t = A.ask_timers()
    eq("device: no retry armed", [n for n in t["timers"] if n == "retry"], [])

    put("vulkaninfo.txt", fixture("vulkaninfo-igpu-first.txt"))
    put("ggml.txt", "ggml_vulkan: Found 2 Vulkan devices:\nggml_vulkan: 0 = AMD Radeon 780M Graphics "
        "(RADV PHOENIX) (radv) | uma: 1\nggml_vulkan: 1 = AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
    A.send({"cmd": "retry"})
    A.until("device: llvmpipe first, writing on Vulkan0", lambda s: model(s)["state"] == "writing")
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

    A.send({"cmd": "unload"})
    s = A.until("unload: unloaded", lambda s: model(s)["state"] == "unloaded")
    log = ace_log()
    check("unload: the job is cancelled", any(e.get("path", "").endswith("&cancel=1") for e in log))
    wait("unload: the server is stopped", lambda: any(e["kind"] == "exit" for e in ace_log()), 5)

    put("vulkaninfo.txt", fixture("vulkaninfo-egpu-first.txt"))
    put("ggml.txt", "ggml_vulkan: Found 2 Vulkan devices:\nggml_vulkan: 0 = AMD Radeon RX 6800 XT "
        "(RADV NAVI21) (radv)\nggml_vulkan: 1 = AMD Radeon RX 6800 XT (RADV NAVI21) (radv)")
    A.send({"cmd": "load"})
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
    eq("genre: it is kept", (s["tune"]["kept"], s["tune"]["n"], s["kept_playing"]), (True, None, True))
    check("genre: one of this genre's kept tunes",
          (s["tune"]["bpm"], s["tune"]["key"]) in ((80, "A minor"), (84, "D major")), s["tune"])
    check("genre: the previous job is cancelled",
          any(e.get("path", "").endswith("&cancel=1") and e["t"] > ambient_job["t"] for e in ace_log()))
    s = A.until("kept tune: its title and wave from the file",
                lambda s: s["tune"] and s["tune"]["name"].startswith("Invented Old") and
                len(s["tune"]["wave"]) == 78)
    check("kept tune: its length", abs((s["tune"]["length"] or 0) - 90) < 0.5, s["tune"])
    s = A.until("queue: two new tunes", lambda s: s["ready"] == 2 and model(s)["state"] == "idle", 40)
    eq("queue: next offered", s["can_next"], True)
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

    A.send({"cmd": "next"})
    s = A.until("next: a new tune", lambda s: s["tune"] and not s["tune"]["kept"])
    eq("next: numbered, not kept", (s["tune"]["n"], s["kept_playing"]), (1, False))
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
    eq("state: last genre and counter", st, {"last_genre": "lofi", "counter": st.get("counter")})
    check("state: the counter counts the tunes", st["counter"] >= 3, st)
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
        before = A.last["tune"]["n"]
        A.until("mpris: a tune is next", lambda s: s["ready"] >= 1, 30)
        playerctl("-p", name, "next")
        s = A.until("mpris: next", lambda s: s["tune"] and s["tune"]["n"] != before, 5)
        A.send({"cmd": "toggle"})
        A.until("mpris: paused for what follows", lambda s: s["player"] == "paused", 5)

    # -- next on kept tunes, unloaded; same genre ignored; idle --
    print("  kept tunes and idle", flush=True)
    lofi_before = kept_files("Lo-fi")
    A.send({"cmd": "unload"})
    A.until("unload", lambda s: model(s)["state"] == "unloaded")
    A.send({"cmd": "genre", "id": "jazz"})
    s = A.until("unloaded: kept tunes still play", lambda s: s["genre"] == "jazz" and s["tune"]
                and s["tune"]["kept"] and s["player"] == "playing")
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
    scenario(lm=["silent", "ok"], lm_time=0.3, synth_time=0.3)
    A.send({"cmd": "load"})
    s = A.until("silence: writing again", lambda s: model(s)["state"] == "writing"
                and model(s)["silence_s"] == 6)
    s = A.until("silence: then a tune", lambda s: s["ready"] >= 1 or (s["tune"] and not s["tune"]["kept"]))
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
    A.send({"cmd": "unload"})
    A.until("unload", lambda s: model(s)["state"] == "unloaded")

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
    ino = os.stat(STATE).st_ino
    A.send({"cmd": "genre", "id": "synthwave"})
    A.until("genre", lambda s: s["genre"] == "synthwave")
    check("state: replaced, not rewritten in place", os.stat(STATE).st_ino != ino)
    eq("state: no temporary left", os.listdir(os.path.dirname(STATE)), ["state.json"])

    # -- MPRIS stop --
    if name:
        A.send({"cmd": "genre", "id": "jazz"})
        A.until("jazz again", lambda s: s["genre"] == "jazz" and s["player"] == "playing")
        playerctl("-p", name, "stop")
        A.until("mpris: stop", lambda s: s["player"] == "none", 5)
        eq("mpris: nothing plays by itself after stop", [e for e in A.quiet(1.0)
                                                         if e.get("player") == "playing"], [])

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
    serve = subprocess.Popen(serve.args, env=ENV, stdout=subprocess.DEVNULL, stderr=SERVE_LOG)
    wait("restart: the socket appears", lambda: os.path.exists(SOCK), 10)
    A = Client(attach=True)
    s = A.until("restart: a snapshot", lambda s: True, 5)
    eq("restart: nothing plays by itself", (s["genre"], s["player"], model(s)["state"]),
       (None, "none", "unloaded"))
    A.send({"cmd": "genre", "id": st["last_genre"]})
    A.until("restart: the last genre picked again", lambda s: s["genre"] == st["last_genre"])
    A.quiet(0.5)
    eq("state: not written when the pick is the saved one",
       (os.stat(STATE).st_ino, os.stat(STATE).st_mtime_ns), (ino, mtime))
    serve.send_signal(signal.SIGTERM)
    eq("restart: exits 0", serve.wait(15), 0)
except Exception:
    import traceback
    traceback.print_exc()
    FAILURES.append("exception")
finish()
