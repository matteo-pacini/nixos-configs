"""desk-weather: its pure functions against hand-written fixtures, then the
built helper against a Mosquitto on loopback (this script plays
Zigbee2MQTT) and a local HTTP server standing in for Open-Meteo, the Met
Office and RainViewer.

Usage: test-desk-weather.py <desk-weather built for testing> <desk-weather.py>
           <mosquitto> <fixtures dir> <work dir>

The helper under test is the build with testing = true, which alone has
--test-origin (every request goes to this script's server, path and query
unchanged) and --test-scale (every timer multiplied). Every name, place and
figure here is invented. A spy subscribed to "#" records every message on
the broker; the test fails if one appears that this script did not publish.
"""

import atexit
import hashlib
import importlib.util
import json
import math
import os
import queue
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
import zlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import paho.mqtt.client as mqtt

HELPER, SOURCE, MOSQUITTO, FIXTURES, WORK = sys.argv[1:6]

spec = importlib.util.spec_from_file_location("desk_weather", SOURCE)
dw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dw)

FAILURES = []
CHECKS = [0]


def check(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILURES.append(name)
        print(f"FAIL {name}: {detail}")


def eq(name, got, want):
    check(name, got == want, f"got {got!r}, want {want!r}")


def raises(name, fn, *args):
    try:
        fn(*args)
    except ValueError:
        CHECKS[0] += 1
        return
    check(name, False, "no ValueError")


def fixture(name, mode="r"):
    with open(os.path.join(FIXTURES, name), mode) as f:
        return f.read()


def utc(*a):
    return int(datetime(*a, tzinfo=timezone.utc).timestamp())


# Invented config. The unrounded digits, the region, the sensor's name and
# the broker's host must never appear in anything the helper prints.
LAT, LON = 51.4837, -0.0049
REGION = "Northshire and the Dales"
SENSOR = "Invented Garden Probe"
BASE = "z2m-test"
SECRETS = ["51.4837", "0.0049", "51.48", REGION, "Northshire", SENSOR, "Garden Probe",
           "localhost", BASE]

# ---- PNG tiles, written here independently of the helper's decoder -------


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def filtered(rows, bpp, filters):
    """Scanlines with filter byte, each row encoded with filters[i % len]."""
    out, prior = b"", bytes(len(rows[0]))
    for i, row in enumerate(rows):
        f = filters[i % len(filters)]
        enc = bytearray(len(row))
        for k, v in enumerate(row):
            a = row[k - bpp] if k >= bpp else 0
            b = prior[k]
            c = prior[k - bpp] if k >= bpp else 0
            if f == 0:
                pred = 0
            elif f == 1:
                pred = a
            elif f == 2:
                pred = b
            elif f == 3:
                pred = (a + b) // 2
            else:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
            enc[k] = (v - pred) & 255
        out += bytes([f]) + bytes(enc)
        prior = row
    return out


def png(rows, colour=6, depth=8, bpp=4, filters=(0,), plte=b"", trns=b"", interlace=0,
        size=256, pad_to=None):
    ihdr = struct.pack(">IIBBBBB", size, size, depth, colour, 0, 0, interlace)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    if plte:
        data += chunk(b"PLTE", plte)
    if trns:
        data += chunk(b"tRNS", trns)
    tail = chunk(b"IDAT", zlib.compress(filtered(rows, bpp, filters))) + chunk(b"IEND", b"")
    if pad_to is not None:
        room = pad_to - len(data) - len(tail) - 12
        data += chunk(b"tEXt", b"x" * room)
    return data + tail


def rgba_tile(echo=(), filters=(0,)):
    """A 256 px RGBA tile, transparent but for the (x, y) pixels in `echo`."""
    rows = [bytearray(256 * 4) for _ in range(256)]
    for x, y in echo:
        rows[y][4 * x:4 * x + 4] = bytes([10, 120, 220, 200])
    return png([bytes(r) for r in rows], filters=filters)


TRANSPARENT = rgba_tile()


# ---- pure: config ---------------------------------------------------------

GOOD = {"latitude": LAT, "longitude": LON, "warnings_region": REGION,
        "mqtt": {"host": "localhost", "sensor": SENSOR}}
config, problem = dw.validate_config(GOOD)
eq("config defaults and rounding", (config, problem), ({
    "latitude": 51.48, "longitude": 0.0, "region": REGION, "host": "localhost",
    "port": 1883, "base": "zigbee2mqtt", "sensor": SENSOR}, None))
check("rounded longitude is 0.0, not -0.0", str(config["longitude"]) == "0.0")
eq("query carries 2 decimals", dw.point_query(config["latitude"], config["longitude"]),
   "latitude=51.48&longitude=0.00")
eq("round_point", dw.round_point(-12.3456, 179.999), (-12.35, 180.0))


def bad(key, **changes):
    raw = json.loads(json.dumps(GOOD))
    for path, value in changes.items():
        target = raw
        parts = path.split("__")
        for p in parts[:-1]:
            target = target[p]
        if value is KeyError:
            del target[parts[-1]]
        else:
            target[parts[-1]] = value
    eq(f"invalid config: {key} ({changes})", dw.validate_config(raw), (None, ("invalid", key)))


bad("latitude", latitude=KeyError)
bad("latitude", latitude="51.48")
bad("latitude", latitude=True)
bad("latitude", latitude=91)
bad("longitude", longitude=-180.5)
bad("warnings_region", warnings_region=" ")
bad("warnings_region", warnings_region=["x"])
bad("mqtt", mqtt="localhost")
bad("mqtt.host", mqtt__host="")
bad("mqtt.host", mqtt__host=KeyError)
bad("mqtt.port", mqtt__port="1883")
bad("mqtt.port", mqtt__port=0)
bad("mqtt.port", mqtt__port=True)
bad("mqtt.base", mqtt__base="z2m/#")
bad("mqtt.base", mqtt__base="a//b")
bad("mqtt.sensor", mqtt__sensor=KeyError)
bad("mqtt.sensor", mqtt__sensor="Probe+")
bad("mqtt.sensor", mqtt__sensor="bridge/state")
eq("config not an object", dw.validate_config([GOOD]), (None, ("invalid", None)))
eq("config file missing", dw.load_config(os.path.join(WORK, "absent.json")), (None, ("missing", None)))
with open(os.path.join(WORK, "broken.json"), "w") as f:
    f.write("{\"latitude\": 51.4837,")
eq("config file not JSON", dw.load_config(os.path.join(WORK, "broken.json")), (None, ("invalid", None)))

# ---- pure: Open-Meteo -----------------------------------------------------

FORECAST = json.loads(fixture("forecast.json"))
event = dw.forecast_event(FORECAST, 1000)
eq("forecast keys", list(event), ["event", "fetched", "utc_offset", "current", "hourly", "daily"])
eq("forecast current", event["current"], {
    "time": utc(2026, 3, 27, 5, 15), "temperature": 3.1, "humidity": 88, "code": 61, "is_day": 0,
    "cloud": 92, "precipitation": 0.4, "wind": 21.5, "wind_dir": 225, "gusts": 44.0})
eq("48 hours from the current hour", (len(event["hourly"]), event["hourly"][0]["time"],
                                      event["hourly"][-1]["time"]),
   (48, utc(2026, 3, 27, 5), utc(2026, 3, 27, 5) + 47 * 3600))
eq("an hour", event["hourly"][0], {"time": utc(2026, 3, 27, 5), "temperature": 3.8, "code": 1,
                                   "is_day": 0, "precipitation": 0.0, "snowfall": 0.0, "cloud": 65})
eq("a null value stays null", event["hourly"][5]["temperature"], None)
# The week crosses the change to summer time on 29 March: from then on each
# day's local midnight is 23:00 UTC the day before.
eq("daily dates across the clock change", [d["date"] for d in event["daily"]],
   ["2026-03-27", "2026-03-28", "2026-03-29", "2026-03-30", "2026-03-31", "2026-04-01",
    "2026-04-02"])
eq("a day", event["daily"][4], {"date": "2026-03-31", "code": 71, "tmax": 6.0, "tmin": -1.0,
                                "precipitation": 2.0, "snowfall": 1.4,
                                "sunrise": utc(2026, 3, 30, 23) + 6 * 3600 + 53 * 60,
                                "sunset": utc(2026, 3, 30, 23) + 18 * 3600 + 38 * 60})
short = json.loads(json.dumps(FORECAST))
del short["hourly"]["cloud_cover"]
short["hourly"]["weather_code"] = short["hourly"]["weather_code"][:6]
short["hourly"]["is_day"][5] = True
e = dw.forecast_event(short, 1)
eq("a missing column is null", e["hourly"][0]["cloud"], None)
eq("a short column ends in nulls", (e["hourly"][0]["code"], e["hourly"][1]["code"]), (1, None))
eq("a bool is not a number", e["hourly"][0]["is_day"], None)
for what, change in [("no current", lambda d: d.pop("current")),
                     ("hourly times not a list", lambda d: d["hourly"].update(time=5)),
                     ("a time not an integer", lambda d: d["daily"]["time"].__setitem__(0, "x")),
                     ("no offset", lambda d: d.pop("utc_offset_seconds"))]:
    broken = json.loads(json.dumps(FORECAST))
    change(broken)
    raises(f"forecast refused: {what}", dw.forecast_event, broken, 1)

AIR = json.loads(fixture("air.json"))
eq("air event", dw.air_event(AIR, 7), {
    "event": "air", "fetched": 7, "aqi": 31, "pm2_5": 7.2, "pm10": 12.9, "no2": 19.4, "o3": 48.0,
    "so2": 1.1, "sub": {"pm2_5": 25, "pm10": 16, "no2": 31, "o3": 15, "so2": 1},
    "pollen": {"alder": 12.5, "birch": 0.0, "grass": 0.0, "mugwort": 0.0, "olive": None,
               "ragweed": None}})
raises("air refused without current", dw.air_event, {"hourly": {}}, 1)
url = urllib.parse.urlsplit(dw.forecast_url(51.48, 0.0))
eq("forecast URL", (url.scheme, url.netloc, url.path), ("https", "api.open-meteo.com", "/v1/forecast"))
q = urllib.parse.parse_qs(url.query)
eq("forecast asks unixtime, 7 days", (q["timeformat"], q["forecast_days"], q["latitude"], q["longitude"]),
   (["unixtime"], ["7"], ["51.48"], ["0.00"]))
url = urllib.parse.urlsplit(dw.air_url(51.48, 0.0))
eq("air URL", (url.netloc, url.path, urllib.parse.parse_qs(url.query)["timeformat"]),
   ("air-quality-api.open-meteo.com", "/v1/air-quality", ["unixtime"]))

# ---- pure: warnings -------------------------------------------------------

RSS = fixture("warnings.xml", "rb")
NOW = utc(2026, 11, 22)
items = dw.warnings_items(RSS, REGION, NOW)
link = "https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-warnings#?id=00000000-fixture-"
eq("warnings: the region's, most severe first, then earliest, unknown last", items, [
    {"level": "red", "type": "snow", "title": "Red warning of snow", "areas": "Upper Dale",
     "from": utc(2026, 11, 24), "to": utc(2026, 11, 24, 12),
     "when": "0000 Tue 24 Nov to 1200 Tue 24 Nov",
     "link": "https://weather.metoffice.gov.uk/warnings-and-advice/uk-warnings#?id=00000000-fixture-0002"},
    {"level": "amber", "type": "wind", "title": "Amber warning of wind", "areas": "the Coastal Strip",
     "from": utc(2026, 11, 23, 3), "to": utc(2026, 11, 23, 15),
     "when": "0300 Mon 23 Nov to 1500 Mon 23 Nov", "link": link + "0004"},
    {"level": "yellow", "type": "ice", "title": "Yellow warning of ice", "areas": "Upper Dale",
     "from": utc(2026, 11, 21, 18), "to": utc(2026, 11, 22, 10),
     "when": "1800 Sat 21 Nov to 1000 Sun 22 Nov", "link": link + "0009"},
    {"level": "yellow", "type": "rain", "title": "Yellow warning of rain",
     "areas": "Upper Dale, Lower Dale, Northtown",
     "from": utc(2026, 11, 22, 6), "to": utc(2026, 11, 22, 23, 59),
     "when": "0600 Sun 22 Nov to 2359 Sun 22 Nov",
     "link": "https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-warnings#?date=2026-11-22&id=00000000-fixture-0001&referrer=rss"},
    {"level": "yellow", "type": "wind and rain", "title": "Yellow warning of wind and rain",
     "areas": "Upper Dale, Lower Dale, Northtown, the Coastal Strip",
     "from": utc(2026, 11, 22, 21), "to": utc(2026, 11, 24, 9),
     "when": "2100 Sun 22 Nov to 0900 Tue 24 Nov", "link": link + "0003"},
    {"level": "yellow", "type": "thunderstorms", "title": "Yellow warning of thunderstorms",
     "areas": "Northtown", "from": None, "to": None,
     "when": "1500 Sunday 22 November until late", "link": link + "0006"},
])
eq("another region's feed", [w["areas"] for w in dw.warnings_items(RSS, "southshire  coast", NOW)],
   ["Porthaven"])
eq("an empty feed", dw.warnings_items(b"<rss version='2.0'><channel/></rss>", REGION, NOW), [])
raises("not RSS", dw.warnings_items, b"<html></html>", REGION, NOW)
raises("not XML", dw.warnings_items, b"{\"items\": []}", REGION, NOW)

# Validity: UK local time, the year inferred from the weekday.
eq("summer time", dw.validity("0600 Mon 29 Jun to 1800 Mon 29 Jun", utc(2026, 6, 20)),
   (utc(2026, 6, 29, 5), utc(2026, 6, 29, 17)))
eq("across New Year", dw.validity("1800 Thu 31 Dec to 1200 Fri 1 Jan", utc(2026, 12, 30)),
   (utc(2026, 12, 31, 18), utc(2027, 1, 1, 12)))
eq("seen after New Year", dw.validity("1800 Thu 31 Dec to 1200 Fri 1 Jan", utc(2027, 1, 1, 6)),
   (utc(2026, 12, 31, 18), utc(2027, 1, 1, 12)))
eq("January seen in December", dw.validity("0900 Sat 2 Jan to 2100 Sat 2 Jan", utc(2026, 12, 28)),
   (utc(2027, 1, 2, 9), utc(2027, 1, 2, 21)))
for text in ["0600 Mon 22 Nov to 2359 Sun 22 Nov", "0600 Sun 22 Nov", "2500 Sun 22 Nov to 2359 Sun 22 Nov",
             "0600 Sun 31 Nov to 2359 Sun 22 Nov", "2359 Sun 22 Nov to 0600 Sun 22 Nov",
             "0600 Sun 22 Xyz to 2359 Sun 22 Nov", ""]:
    eq(f"validity does not parse: {text!r}", dw.validity(text, NOW), (None, None))

for good in ["https://www.metoffice.gov.uk/weather/x", "https://weather.metoffice.gov.uk/"]:
    check(f"link allowed: {good}", dw.allowed_link(good))
for foreign in ["http://www.metoffice.gov.uk/x", "https://metoffice.gov.uk/x",
                "https://www.metoffice.gov.uk.example.net/x", "https://www.metoffice.gov.uk:8443/x",
                "https://user@www.metoffice.gov.uk/x", "https://www.metoffice.gov.uk",
                "javascript:alert(1)", "https://example.org/?https://www.metoffice.gov.uk/"]:
    check(f"link refused: {foreign}", not dw.allowed_link(foreign))
eq("enclosure: double type", dw.kind_from_enclosure("https://x/a/yellow-wind-rain.png"),
   ("yellow", "wind and rain"))
eq("enclosure: two-word type", dw.kind_from_enclosure("https://x/amber-extreme-heat.png"),
   ("amber", "extreme heat"))
eq("enclosure: unknown level", dw.kind_from_enclosure("https://x/orange-rain.png"), None)
eq("enclosure: unknown type", dw.kind_from_enclosure("https://x/red-locusts.png"), None)
eq("title fallback", dw.kind_from_title("Amber warning of snow and ice"), ("amber", "snow and ice"))

# ---- pure: radar ----------------------------------------------------------

eq("the fixed block", dw.block_tiles(), [(x, y) for x in (30, 31, 32) for y in (18, 19, 20, 21)])
eq("tile URL", dw.tile_url("https://tilecache.rainviewer.com", "/v2/radar/abc", 31, 20),
   "https://tilecache.rainviewer.com/v2/radar/abc/256/6/31/20/2/1_0.png")
check("never above zoom 7", dw.ZOOM <= 7)
# Web Mercator by the asinh form, not the helper's log(tan + sec).
want_y = (1 - math.asinh(math.tan(math.radians(51.48))) / math.pi) / 2 * 256 * 2 ** 6 - 18 * 256
eq("centre", dw.centre(51.48, 0.0), [512.0, round(want_y, 1)])
host, frames = dw.radar_frames(json.loads(fixture("weather-maps.json")))
eq("frames oldest first", [f[2] for f in frames], ["fixture0001", "fixture0002", "fixture0003"])
maps = json.loads(fixture("weather-maps.json"))
for what, change in [("a foreign host", lambda d: d.update(host="https://tiles.example.net")),
                     ("a path with ..", lambda d: d["radar"]["past"][0].update(path="/v2/radar/../x")),
                     ("a path with a query", lambda d: d["radar"]["past"][0].update(path="/v2/radar/a?b")),
                     ("no past", lambda d: d["radar"].pop("past"))]:
    broken = json.loads(json.dumps(maps))
    change(broken)
    raises(f"frames refused: {what}", dw.radar_frames, broken)

NOT_SUPPORTED_SIZE = png([bytes(256)] * 256, colour=3, depth=8, bpp=1, plte=b"\0\0\0", pad_to=1370)
eq("stand-in picture is 1370 bytes", len(NOT_SUPPORTED_SIZE), 1370)
check("tile refused: the picture's size", not dw.tile_ok(NOT_SUPPORTED_SIZE))
check("tile accepted: a transparent tile", dw.tile_ok(TRANSPARENT))
saved = dw.NOT_SUPPORTED
dw.NOT_SUPPORTED = {(1, hashlib.sha256(TRANSPARENT).hexdigest())}
check("tile refused: the picture's content", not dw.tile_ok(TRANSPARENT))
dw.NOT_SUPPORTED = saved
check("tile refused: 512 px", not dw.tile_ok(png([bytes(512 * 4 + 0)] * 1, size=512)))
check("tile refused: not a PNG", not dw.tile_ok(b"GIF89a" + bytes(100)))

# Decoding: every filter type, palette transparency, and what cannot be read.
pixels = [(0, 0), (255, 0), (17, 3), (128, 128), (255, 255)]
for filters in [(0,), (1,), (2,), (3,), (4,), (0, 1, 2, 3, 4)]:
    rows = dw.png_alpha(rgba_tile(pixels, filters=filters), 256)
    lit = sorted((x, y) for y, r in enumerate(rows) for x, a in enumerate(r) if a)
    eq(f"decode, filters {filters}", lit, sorted(pixels))
palette_rows = []
for y in range(256):
    row = bytearray(128)
    if y == 9:
        row[20] = 0x21  # pixels 40 and 41: indexes 2 (opaque) and 1 (transparent)
    palette_rows.append(bytes(row))
pal = png(palette_rows, colour=3, depth=4, bpp=1, plte=bytes(9), trns=b"\x00\x00", filters=(4, 1))
rows = dw.png_alpha(pal, 256)
eq("decode, 4-bit palette with tRNS",
   sorted((x, y) for y, r in enumerate(rows) for x, a in enumerate(r) if a), [(40, 9)])
eq("decode refused: interlaced", dw.png_alpha(png([bytes(1025)[:1024]] * 256, interlace=1), 256), None)
eq("decode refused: RGB without alpha",
   dw.png_alpha(png([bytes(768)] * 256, colour=2, bpp=3), 256), None)
eq("decode refused: truncated", dw.png_alpha(TRANSPARENT[:60], 256), None)

BOX = dw.view_box(dw.centre(51.48, 0.0))
left, top, right, bottom = BOX
eq("view is 390 x 250", (right - left, bottom - top), (390, 250))


def tiles_with(echo=None, broken=None):
    """read_tile for a frame: transparent, but for one block pixel lit and
    one tile undecodable."""
    def read(x, y):
        if broken == (x, y):
            return png([bytes(1024)] * 256, interlace=1)
        if echo and (echo[0] // 256 + 30, echo[1] // 256 + 18) == (x, y):
            return rgba_tile([(echo[0] % 256, echo[1] % 256)])
        return TRANSPARENT
    return read


eq("dry: nothing anywhere", dw.frame_dry(tiles_with(), BOX), True)
eq("dry: echo just left of the view", dw.frame_dry(tiles_with((left - 1, top + 5)), BOX), True)
eq("dry: echo just below the view", dw.frame_dry(tiles_with((left + 5, bottom)), BOX), True)
eq("not dry: echo at the view's corner", dw.frame_dry(tiles_with((left, top)), BOX), False)
eq("not dry: echo at the far corner", dw.frame_dry(tiles_with((right - 1, bottom - 1)), BOX), False)
VIEW_TILE = (left // 256 + 30, top // 256 + 18)
eq("dry unknown: a view tile undecodable", dw.frame_dry(tiles_with(broken=VIEW_TILE), BOX), None)
eq("dry: an undecodable tile outside the view is not read",
   dw.frame_dry(tiles_with(broken=(30, 18)), BOX), True)

eq("retry schedule", [dw.retry_delay(n) for n in range(1, 8)], [60, 120, 240, 480, 900, 900, 900])
eq("commands", [dw.command('{"cmd":"refresh"}'), dw.command('{"cmd": "radar", "on": true}'),
                dw.command('{"cmd":"radar","on":false}')],
   [("refresh",), ("radar", True), ("radar", False)])
for line in ['{"cmd":"radar","on":1}', '{"cmd":"refresh","x":1}', '["refresh"]', '{"cmd":"publish"}']:
    raises(f"command refused: {line}", dw.command, line)
eq("reading time: ISO", dw.reading_time("2026-11-15T10:00:00.000Z", 5), utc(2026, 11, 15, 10))
eq("reading time: epoch ms", dw.reading_time(1795345000123, 5), 1795345000)
eq("reading time: none", dw.reading_time(None, 5), 5)
eq("reading time: garbage", dw.reading_time("yesterday", 5), 5)
eq("reading: every field, in the event's order",
   list(dw.reading({"temperature": 7.4, "humidity": 78, "battery": 55, "linkquality": 86}, 5).items()),
   [("temperature", 7.4), ("humidity", 78), ("battery", 55), ("linkquality", 86), ("at", 5)])
eq("linkquality absent", dw.reading({"temperature": 7.4}, 5)["linkquality"], None)
for bad_link in ["86", True, None, 86.5, float("nan"), [86], {"v": 86}]:
    eq(f"linkquality not a number: {bad_link!r}", dw.reading({"linkquality": bad_link}, 5)["linkquality"], None)
for edge, want in [(-1, None), (0, 0), (255, 255), (256, None), (86.0, 86)]:
    eq(f"linkquality range: {edge!r}", dw.reading({"linkquality": edge}, 5)["linkquality"], want)
check("the source has one MQTT call that sends, the subscribe",
      "publish(" not in open(SOURCE).read())
print(f"pure: {CHECKS[0]} checks, {len(FAILURES)} failed")

# ---- the built helper -----------------------------------------------------


CHILDREN = []


@atexit.register
def stop_children():
    """A failed assertion must not leave a broker or a helper holding this
    script's output open."""
    for proc in CHILDREN:
        if proc.poll() is None:
            proc.kill()


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


MQTT_PORT = free_port()


class Broker:
    def __init__(self):
        self.conf = os.path.join(WORK, "mosquitto.conf")
        self.log = os.path.join(WORK, "mosquitto.log")
        with open(self.conf, "w") as f:
            f.write(f"listener {MQTT_PORT} 127.0.0.1\nallow_anonymous true\n"
                    f"log_dest file {self.log}\nlog_type all\n")

    def start(self):
        self.proc = subprocess.Popen([MOSQUITTO, "-c", self.conf])
        CHILDREN.append(self.proc)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", MQTT_PORT), timeout=0.2).close()
                return
            except OSError:
                time.sleep(0.05)
        raise SystemExit("mosquitto did not start")

    def stop(self):
        self.proc.terminate()
        self.proc.wait()


class Spy:
    """Plays Zigbee2MQTT and records every message on "#"."""

    def __init__(self):
        self.seen, self.sent = [], []
        self.lock = threading.Lock()
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="test-spy")
        self.connected = threading.Event()
        self.client.on_connect = lambda c, *a: (c.subscribe("#"), self.connected.set())
        self.client.on_message = self.on_message
        self.client.connect("127.0.0.1", MQTT_PORT)
        self.client.loop_start()
        assert self.connected.wait(5), "spy did not connect"

    def on_message(self, client, userdata, msg):
        with self.lock:
            self.seen.append((msg.topic, bytes(msg.payload)))

    def publish(self, topic, payload, retain=False):
        text = payload if isinstance(payload, str) else json.dumps(payload)
        with self.lock:
            self.sent.append((f"{BASE}/{topic}", text.encode()))
        self.client.publish(f"{BASE}/{topic}", text, qos=1, retain=retain).wait_for_publish(5)


class Fake(BaseHTTPRequestHandler):
    """Open-Meteo, the Met Office and RainViewer on one loopback port."""
    requests = []  # (monotonic time, path, query, user agent)
    lock = threading.Lock()
    answers = {}  # path -> list of (status, body, delay); the last is kept
    tiles = {}  # (frame id, x, y) -> bytes

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        with Fake.lock:
            Fake.requests.append((time.monotonic(), u.path, u.query, self.headers.get("User-Agent")))
            queue_ = Fake.answers.get(u.path)
            if queue_:
                status, body, delay = queue_[0] if len(queue_) == 1 else queue_.pop(0)
            elif u.path.startswith("/v2/radar/"):
                parts = u.path.split("/")
                status, delay = 200, 0
                body = Fake.tiles.get((parts[3], int(parts[6]), int(parts[7])), TRANSPARENT)
            else:
                status, body, delay = 404, b"", 0
        time.sleep(delay)
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def answer(path, *replies):
    with Fake.lock:
        Fake.answers[path] = [r if isinstance(r, tuple) else (200, r, 0) for r in replies]


def requests_since(t, path=None):
    with Fake.lock:
        return [r for r in Fake.requests if r[0] >= t and (path is None or r[1] == path)]


FORECAST_PATH, AIR_PATH = "/v1/forecast", "/v1/air-quality"
WARNINGS_PATH = "/public/data/PWSCache/WarningsRSS/Region/UK"
MAPS_PATH = "/public/weather-maps.json"
answer(FORECAST_PATH, fixture("forecast.json", "rb"))
answer(AIR_PATH, fixture("air.json", "rb"))
answer(WARNINGS_PATH, RSS)
answer(MAPS_PATH, fixture("weather-maps.json", "rb"))

server = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
threading.Thread(target=server.serve_forever, daemon=True).start()
ORIGIN = f"http://127.0.0.1:{server.server_address[1]}"
SCALE = 0.01

# Every line any run printed, on either stream.
PRINTED = []
SHAPES = {
    "config": None,
    "broker": ["event", "state"],
    "sensor": ["event", "temperature", "humidity", "battery", "linkquality", "at", "available"],
    "forecast": ["event", "fetched", "utc_offset", "current", "hourly", "daily"],
    "forecast_error": ["event", "at", "reason"],
    "air": ["event", "fetched", "aqi", "pm2_5", "pm10", "no2", "o3", "so2", "sub", "pollen"],
    "air_error": ["event", "at", "reason"],
    "warnings": ["event", "fetched", "items"],
    "warnings_error": ["event", "at", "reason"],
    "radar": ["event", "fetched", "zoom", "tile", "x0", "y0", "cols", "rows", "centre", "frames"],
    "radar_error": ["event", "at", "reason"],
}


class Helper:
    def __init__(self, config, cache=True, origin=ORIGIN, env=None):
        args = [HELPER, "--config", config, "--test-origin", origin, "--test-scale", str(SCALE)]
        if cache:
            self.cache = os.path.join(WORK, "cache")
            args += ["--cache", self.cache]
        environment = {"PATH": "", "HOME": os.path.join(WORK, "home"), **(env or {})}
        self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, env=environment)
        CHILDREN.append(self.proc)
        self.events, self.log, self.lines, self.errors = queue.Queue(), [], [], []
        self.waiting = []
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.read_errors, daemon=True).start()

    def read(self):
        for line in self.proc.stdout:
            PRINTED.append(line)
            self.lines.append(line)
            event = json.loads(line)
            shape = SHAPES.get(event.get("event"), "unknown")
            if event.get("event") == "config":
                shape = ["event", "state", "key"] if event.get("state") == "invalid" else ["event", "state"]
            check(f"shape of {event.get('event')}", list(event) == shape, line)
            self.events.put(event)
        self.events.put(None)

    def read_errors(self):
        for line in self.proc.stderr:
            PRINTED.append(line)
            self.errors.append(line)

    def send(self, obj):
        self.proc.stdin.write((obj if isinstance(obj, str) else json.dumps(obj)) + "\n")
        self.proc.stdin.flush()

    def expect(self, timeout=5, **fields):
        """The first event not yet taken that matches `fields`; the ones
        skipped stay for later calls."""
        def matches(event):
            return all(event.get(k) == v for k, v in fields.items())
        for i, event in enumerate(self.waiting):
            if matches(event):
                return self.waiting.pop(i)
        deadline = time.monotonic() + timeout
        while True:
            try:
                event = self.events.get(timeout=max(deadline - time.monotonic(), 0))
            except queue.Empty:
                raise AssertionError(f"timed out waiting for {fields}; "
                                     f"waiting: {[e['event'] for e in self.waiting]}")
            if event is None:
                raise AssertionError(f"helper exited waiting for {fields}")
            self.log.append(event)
            if matches(event):
                return event
            self.waiting.append(event)

    def quiet(self, seconds):
        """The events not yet taken and those that arrive within `seconds`."""
        got, deadline = self.waiting, time.monotonic() + seconds
        self.waiting = []
        while (left := deadline - time.monotonic()) > 0:
            try:
                event = self.events.get(timeout=left)
            except queue.Empty:
                break
            if event is None:
                break
            self.log.append(event)
            got.append(event)
        return got

    def close(self):
        self.proc.stdin.close()
        check("exit status 0", self.proc.wait(10) == 0)


def write_config(name, obj):
    path = os.path.join(WORK, name)
    with open(path, "w") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj))
    return path


broker = Broker()
broker.start()
spy = Spy()
GOOD_CONFIG = {"latitude": LAT, "longitude": LON, "warnings_region": REGION,
               "mqtt": {"host": "localhost", "port": MQTT_PORT, "base": BASE, "sensor": SENSOR}}
CONFIG = write_config("config.json", GOOD_CONFIG)

# Missing and invalid config: one line, naming the key and nothing else.
h = Helper(os.path.join(WORK, "absent.json"))
eq("missing config line", h.expect(event="config"), {"event": "config", "state": "missing"})
h.send({"cmd": "refresh"})
eq("missing config: nothing more", h.quiet(0.5), [])
h.close()
for key, raw in [(None, "{"), (None, "[]"), ("latitude", {**GOOD_CONFIG, "latitude": "north"}),
                 ("mqtt.host", {**GOOD_CONFIG, "mqtt": {**GOOD_CONFIG["mqtt"], "host": 5}}),
                 ("mqtt.sensor", {**GOOD_CONFIG, "mqtt": {"host": "localhost", "sensor": "a/+"}})]:
    h = Helper(write_config("bad.json", raw))
    h.expect(event="config")
    eq(f"invalid config line ({key})", h.lines[0],
       json.dumps({"event": "config", "state": "invalid", "key": key}) + "\n")
    h.close()
eq("invalid config: no request made", requests_since(0), [])

# A retained reading before the helper starts.
spy.publish(SENSOR, {"temperature": 7.4, "humidity": 78.0, "battery": 55, "linkquality": 90,
                     "last_seen": "2026-11-22T10:15:00.000Z"}, retain=True)
spy.publish(f"{SENSOR}/availability", {"state": "online"}, retain=True)

answer(FORECAST_PATH, (500, b"", 0), (500, b"", 0), (500, b"", 0), fixture("forecast.json", "rb"))
start = time.monotonic()
h = Helper(CONFIG)
eq("config ok line", h.expect(event="config"), {"event": "config", "state": "ok"})
h.expect(event="broker", state="connected")
eq("retained reading", h.expect(event="sensor"), {
    "event": "sensor", "temperature": 7.4, "humidity": 78.0, "battery": 55, "linkquality": 90,
    "at": utc(2026, 11, 22, 10, 15), "available": True})
air = h.expect(event="air")
eq("air event, built", air, dw.air_event(AIR, air["fetched"]))
warnings = h.expect(event="warnings")
eq("warnings, built: levels in order", [w["level"] for w in warnings["items"]],
   ["red", "amber", "yellow", "yellow", "yellow", "yellow"])
eq("warnings, built: the region's items only, foreign links dropped",
   sorted(w["link"].split("fixture-")[1][:4] for w in warnings["items"]),
   ["0001", "0002", "0003", "0004", "0006", "0009"])

# Back-off: three 500s, then the fixture.
errors = [h.expect(event="forecast_error") for _ in range(3)]
eq("forecast errors say http", [e["reason"] for e in errors], ["http"] * 3)
forecast = h.expect(timeout=10, event="forecast")
eq("forecast line, built, byte for byte",
   next(line for line in h.lines if line.startswith('{"event": "forecast", ')),
   json.dumps(dw.forecast_event(FORECAST, forecast["fetched"])) + "\n")
times = [r[0] for r in requests_since(start, FORECAST_PATH)]
gaps = [round(b - a, 2) for a, b in zip(times, times[1:])]
want = [60 * SCALE, 120 * SCALE, 240 * SCALE]
check(f"retry gaps {gaps} follow 60, 120, 240 s scaled",
      len(gaps) == 3 and all(w - 0.05 <= g <= w + 0.35 for g, w in zip(gaps, want)), gaps)

every = requests_since(start)
eq("User-Agent on every request", {r[3] for r in every}, {"desk-weather"})
q = urllib.parse.parse_qs(requests_since(start, FORECAST_PATH)[0][2])
eq("forecast request: the rounded point", (q["latitude"], q["longitude"]), (["51.48"], ["0.00"]))
q = urllib.parse.parse_qs(requests_since(start, AIR_PATH)[0][2])
eq("air request: the rounded point", (q["latitude"], q["longitude"]), (["51.48"], ["0.00"]))
eq("warnings: only the whole-UK feed, no query",
   {(r[1], r[2]) for r in every if "Warnings" in r[1]}, {(WARNINGS_PATH, "")})
eq("no radar request while radar is off", [r for r in every if "radar" in r[1] or r[1] == MAPS_PATH], [])

# Live readings and availability.
spy.publish(SENSOR, {"temperature": 6.9, "humidity": 80, "battery": 54})
before = int(time.time())
live = h.expect(event="sensor")
check("live reading without last_seen: at = arrival",
      live["temperature"] == 6.9 and before - 1 <= live["at"] <= before + 2, live)
spy.publish(f"{SENSOR}/availability", "offline")
eq("availability offline", h.expect(event="sensor")["available"], False)
spy.publish(f"{SENSOR}/availability", {"state": "offline"})
spy.publish(SENSOR, "not json")
spy.publish(f"{SENSOR}/availability", {"state": "online"})
eq("same availability and a malformed reading send nothing; online does",
   [e for e in h.quiet(1) if e["event"] == "sensor"],
   [{"event": "sensor", "temperature": 6.9, "humidity": 80, "battery": 54, "linkquality": None,
     "at": live["at"], "available": True}])

# Refresh, twice while the forecast call is still running: one call.
answer(FORECAST_PATH, (200, fixture("forecast.json", "rb"), 1.5))
h.waiting.clear()
t = time.monotonic()
h.send({"cmd": "refresh"})
time.sleep(0.3)
h.send({"cmd": "refresh"})
got = h.quiet(2.5)
eq("refresh: one forecast call while one runs", len(requests_since(t, FORECAST_PATH)), 1)
eq("refresh: air and warnings fetched again", (len(requests_since(t, AIR_PATH)) >= 1,
                                               len(requests_since(t, WARNINGS_PATH)) >= 1), (True, True))
check("refresh: a forecast event", any(e["event"] == "forecast" for e in got))
answer(FORECAST_PATH, fixture("forecast.json", "rb"))

# Radar on: the frame list, then every frame's 12 tiles, newest first.
POINT = dw.centre(51.48, 0.0)
Fake.tiles[("fixture0002", *VIEW_TILE)] = rgba_tile([(left % 256 + 3, top % 256 + 3)])
Fake.tiles[("fixture0003", *VIEW_TILE)] = png([bytes(1024)] * 256, interlace=1)
h.waiting.clear()
t = time.monotonic()
h.send({"cmd": "radar", "on": True})
first = h.expect(event="radar")
eq("radar: the block and the centre", {k: first[k] for k in ("zoom", "tile", "x0", "y0", "cols", "rows", "centre")},
   {"zoom": 6, "tile": 256, "x0": 30, "y0": 18, "cols": 3, "rows": 4, "centre": POINT})
eq("radar: nothing cached yet", first["frames"], [])
progress = [h.expect(event="radar")["frames"] for _ in range(3)]
eq("radar: frames complete newest first", [[f["dir"][-4:] for f in p] for p in progress],
   [["0003"], ["0002", "0003"], ["0001", "0002", "0003"]])
radar_dir = os.path.join(WORK, "cache", "radar")
eq("radar: the final event", progress[-1], [
    {"time": 1795348800, "dir": os.path.join(radar_dir, "fixture0001"), "dry": True},
    {"time": 1795349400, "dir": os.path.join(radar_dir, "fixture0002"), "dry": False},
    {"time": 1795350000, "dir": os.path.join(radar_dir, "fixture0003"), "dry": None}])
eq("radar: every tile on disk, no temporary file",
   sorted(os.listdir(os.path.join(radar_dir, "fixture0002"))),
   sorted(f"{x}_{y}.png" for x, y in dw.block_tiles()))
with open(os.path.join(radar_dir, "fixture0002", "%d_%d.png" % VIEW_TILE), "rb") as f:
    eq("radar: a tile as served", f.read(), Fake.tiles[("fixture0002", *VIEW_TILE)])
tile_requests = [r[1] for r in requests_since(t) if r[1].startswith("/v2/radar/")]
allowed = {f"/v2/radar/fixture000{i}/256/6/{x}/{y}/2/1_0.png" for i in (1, 2, 3)
           for x, y in dw.block_tiles()}
eq("radar: exactly the fixed block, once per frame", sorted(tile_requests), sorted(allowed))

# Radar every 5 min (scaled) while on: the list again, no tile again.
h.expect(timeout=5, event="radar")
eq("radar: complete frames are not fetched again",
   len([r for r in requests_since(t) if r[1].startswith("/v2/radar/")]), 36)

# A frame dropped and one added: the dropped one's files go after the event.
maps2 = json.loads(fixture("weather-maps.json"))
maps2["radar"]["past"] = [f for f in maps2["radar"]["past"] if f["path"] != "/v2/radar/fixture0001"]
maps2["radar"]["past"].append({"time": 1795350600, "path": "/v2/radar/fixture0004"})
answer(MAPS_PATH, json.dumps(maps2).encode())
dropped = h.expect(timeout=5, event="radar")
eq("radar: the dropped frame is not listed", [f["dir"][-4:] for f in dropped["frames"]], ["0002", "0003"])
for _ in range(20):
    if not os.path.exists(os.path.join(radar_dir, "fixture0001")):
        break
    time.sleep(0.05)
check("radar: the dropped frame is deleted", not os.path.exists(os.path.join(radar_dir, "fixture0001")))
eq("radar: the new frame follows", [f["dir"][-4:] for f in h.expect(event="radar")["frames"]],
   ["0002", "0003", "0004"])

# The "Zoom Level Not Supported" picture is an error, never a frame.
maps3 = json.loads(json.dumps(maps2))
maps3["radar"]["past"].append({"time": 1795351200, "path": "/v2/radar/fixture0005"})
Fake.tiles[("fixture0005", 31, 19)] = NOT_SUPPORTED_SIZE
answer(MAPS_PATH, json.dumps(maps3).encode())
eq("radar: the picture is a tile error", h.expect(timeout=5, event="radar_error")["reason"], "tile")
check("radar: the picture is not written",
      not os.path.exists(os.path.join(radar_dir, "fixture0005", "31_19.png")))
check("radar: the frame is never listed",
      all("fixture0005" not in f["dir"] for e in h.log if e["event"] == "radar" for f in e["frames"]))

# A frame list naming another tile host: refused before any tile request.
maps4 = {**maps2, "host": "https://tiles.example.net"}
maps4["radar"] = {"past": [{"time": 1795351800, "path": "/v2/radar/fixture0006"}]}
answer(MAPS_PATH, json.dumps(maps4).encode())
eq("radar: a foreign tile host is a parse error",
   h.expect(timeout=10, event="radar_error", reason="parse")["reason"], "parse")
eq("radar: no tile requested from it", [r for r in Fake.requests if "fixture0006" in r[1]], [])

# Radar off: no more radar requests; the cache stays.
h.send({"cmd": "radar", "on": False})
time.sleep(0.5)
t = time.monotonic()
h.quiet(dw.INTERVALS["radar"] * SCALE + dw.RETRY_MAX * SCALE + 1)
eq("radar off: no request", [r for r in requests_since(t) if r[1] == MAPS_PATH or "radar" in r[1]], [])
check("radar off: the cache stays", os.path.isdir(os.path.join(radar_dir, "fixture0002")))

# Bad lines on stdin: stderr only.
n_lines = len(h.lines)
h.send("radar on")
h.send({"cmd": "publish", "topic": "x"})
time.sleep(0.5)
eq("bad commands: nothing on stdout", h.lines[n_lines:], [])
eq("bad commands: one stderr line each", sum("not a command" in e for e in h.errors), 2)
h.close()

# Parse errors and an unreachable network, from a fresh helper.
answer(FORECAST_PATH, b"{")
answer(AIR_PATH, b"[1, 2]")
answer(WARNINGS_PATH, b"<html>maintenance</html>")
h = Helper(CONFIG)
eq("parse errors", sorted(h.expect(event=e)["reason"] for e in ("forecast_error", "air_error", "warnings_error")),
   ["parse", "parse", "parse"])
h.close()
closed = f"http://127.0.0.1:{free_port()}"
h = Helper(CONFIG, origin=closed, cache=False, env={"XDG_CACHE_HOME": os.path.join(WORK, "xdg")})
eq("network errors", sorted(h.expect(event=e)["reason"] for e in ("forecast_error", "air_error", "warnings_error")),
   ["network", "network", "network"])
h.send({"cmd": "radar", "on": True})
eq("radar network error", h.expect(event="radar_error")["reason"], "network")
h.close()
answer(FORECAST_PATH, fixture("forecast.json", "rb"))
answer(AIR_PATH, fixture("air.json", "rb"))
answer(WARNINGS_PATH, RSS)
answer(MAPS_PATH, fixture("weather-maps.json", "rb"))
h = Helper(CONFIG, cache=False, env={"XDG_CACHE_HOME": os.path.join(WORK, "xdg")})
h.send({"cmd": "radar", "on": True})
event = h.expect(timeout=10, event="radar", frames=[{"time": 1795348800, "dir": os.path.join(WORK, "xdg", "desk-weather", "radar", "fixture0001"), "dry": True},
                                                    {"time": 1795349400, "dir": os.path.join(WORK, "xdg", "desk-weather", "radar", "fixture0002"), "dry": False},
                                                    {"time": 1795350000, "dir": os.path.join(WORK, "xdg", "desk-weather", "radar", "fixture0003"), "dry": None}])
check("default cache under XDG_CACHE_HOME", bool(event))
h.close()

# The broker down: lost, retried every 10 s, while HTTP carries on.
spy.connected.clear()
broker.stop()
h = Helper(CONFIG)
eq("broker unreachable: lost", h.expect(event="broker")["state"], "lost")
h.expect(event="forecast")
broker.start()
assert spy.connected.wait(10), "spy did not reconnect"
spy.publish(SENSOR, {"temperature": 5.5, "humidity": 90, "battery": 53,
                     "last_seen": "2026-11-22T11:00:00.000Z"}, retain=True)
t = time.monotonic()
h.expect(timeout=15, event="broker", state="connected")
waited = time.monotonic() - t
check(f"reconnected within the 10 s retry ({waited:.1f} s)", waited <= 11)
eq("then the retained reading", h.expect(event="sensor")["at"], utc(2026, 11, 22, 11))
spy.connected.clear()
broker.stop()
eq("broker stops: lost", h.expect(event="broker")["state"], "lost")
h.close()

# A broker that refuses the connection.
broker.start()
assert spy.connected.wait(10), "spy did not reconnect"
refusing_port = free_port()
conf = write_config("refusing.conf", f"listener {refusing_port} 127.0.0.1\nallow_anonymous false\n")
refusing = subprocess.Popen([MOSQUITTO, "-c", conf], stderr=subprocess.DEVNULL)
CHILDREN.append(refusing)
time.sleep(0.5)
h = Helper(write_config("refusing.json", {**GOOD_CONFIG, "mqtt": {**GOOD_CONFIG["mqtt"], "port": refusing_port}}))
eq("broker refuses: lost", h.expect(event="broker")["state"], "lost")
h.close()
refusing.terminate()
refusing.wait()

# Nothing published by any helper: every message the spy saw was this
# script's own, and the broker logged no PUBLISH from another client.
time.sleep(0.5)
with spy.lock:
    foreign = [m for m in spy.seen if m not in spy.sent]
eq("nothing published to the broker", foreign, [])
with open(broker.log) as f:
    log = f.read()
publishers = {line.split("Received PUBLISH from ", 1)[1].split(" ", 1)[0]
              for line in log.splitlines() if "Received PUBLISH from " in line}
eq("one client published, the spy", publishers, {"test-spy"})

# No config value in anything printed.
text = "".join(PRINTED)
for secret in SECRETS:
    check(f"never printed: {secret!r}", secret not in text)
check("stderr was written at all (the check above saw it)", any("desk-weather:" in line for line in PRINTED))

spy.client.loop_stop()
broker.stop()
server.shutdown()
shutil.rmtree(os.path.join(WORK, "cache"), ignore_errors=True)
print(f"{CHECKS[0]} checks, {len(FAILURES)} failed")
if FAILURES:
    sys.exit(1)
