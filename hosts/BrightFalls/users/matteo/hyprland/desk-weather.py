"""Weather for the Quickshell weather panel and its bar item.

Reads an outdoor sensor over MQTT (subscribe only), the forecast and air
quality from Open-Meteo, the Met Office's whole-UK warnings feed and
RainViewer's past radar frames, and reports them to its parent as JSON lines.

Usage: desk-weather [--config FILE] [--cache DIR]

--config: JSON, the only place the location and the broker live:
    {"latitude": 51.48, "longitude": 0.00,
     "warnings_region": "<region name as the Met Office writes it>",
     "mqtt": {"host": str, "port": 1883?, "base": "zigbee2mqtt"?,
              "sensor": "<Zigbee2MQTT friendly name>"}}
    Defaults to the path the package was built with. Latitude and longitude
    are rounded to 2 decimals before any request. Nothing from this file is
    printed, logged or sent anywhere except the rounded pair to Open-Meteo
    and the MQTT connection itself. Errors name the key at fault, never a
    value.
--cache: where radar frames are kept; default $XDG_CACHE_HOME/desk-weather
    (~/.cache/desk-weather).

stdout carries only the events below, one JSON object per line. All times
are Unix seconds (integers, UTC). Missing values are null, never absent keys.

  {"event":"config","state":"ok"}
  {"event":"config","state":"missing"}
  {"event":"config","state":"invalid","key":"mqtt.host"}
      key is null when the file as a whole is unreadable or not an object.
      After missing or invalid nothing else is sent; the process waits for
      stdin to close.

  {"event":"broker","state":"connected"|"lost"}
      Sent on each change; "lost" also when the first connection fails.
      Reconnects every 10 s.
  {"event":"sensor","temperature":7.4,"humidity":78.0,"battery":55,
   "linkquality":86,"at":1795345000,"available":true}
      linkquality = Zigbee2MQTT's linkquality, an integer 0..255; null when
      the message has none or it is not an integer in that range.
      at = the reading's time (Zigbee2MQTT last_seen if present, else
      arrival; null before any reading). available = Zigbee2MQTT
      availability (true when unknown). Sent on each reading and on each
      availability change; the retained message on connect counts as a
      reading with its own last_seen.

  {"event":"forecast","fetched":t,"utc_offset":0,
   "current":{"time","temperature","humidity","code","is_day","cloud",
              "precipitation","wind","wind_dir","gusts"},
   "hourly":[{"time","temperature","code","is_day","precipitation",
              "snowfall","cloud"}, ... up to 48 from the current hour],
   "daily":[{"date":"2026-11-22","code","tmax","tmin","precipitation",
             "snowfall","sunrise","sunset"}, ... up to 7]}
      Units: degrees C, %, mm (precipitation), cm (snowfall), km/h,
      degrees. code = WMO weather code as Open-Meteo gives it. date is the
      local day at the forecast point.
  {"event":"forecast_error","at":t,"reason":"network"|"http"|"parse"}

  {"event":"air","fetched":t,"aqi":28,"pm2_5":6.5,"pm10":10.8,"no2":15.8,
   "o3":55.0,"so2":1.6,
   "sub":{"pm2_5":23,"pm10":14,"no2":28,"o3":18,"so2":2},
   "pollen":{"alder","birch","grass","mugwort","olive","ragweed"}}
      aqi = european_aqi; pollen values null when the source gives none.
  {"event":"air_error","at":t,"reason":"network"|"http"|"parse"}

  {"event":"warnings","fetched":t,"items":[
    {"level":"yellow"|"amber"|"red","type":"rain",
     "title":"Yellow warning of rain","areas":str,"from":t|null,"to":t|null,
     "when":"0600 Sun 22 Nov to 2359 Sun 22 Nov","link":str}]}
      Only items for the configured region, most severe first, then
      earliest. level and type from the enclosure file name, falling back
      to the title. from/to parsed from the validity text as UK local time
      with the year inferred (the year nearest now whose weekday matches);
      null when it does not parse ("when" always carries the raw text).
      link is only ever a https://www.metoffice.gov.uk/ or
      https://weather.metoffice.gov.uk/ URL; an item with any other link
      is dropped.
  {"event":"warnings_error","at":t,"reason":"network"|"http"|"parse"}

  {"event":"radar","fetched":t,"zoom":6,"tile":256,"x0":30,"y0":18,
   "cols":3,"rows":4,"centre":[412.3,520.8],
   "frames":[{"time":t,"dir":"<cache>/radar/<id>","dry":false}, ... oldest first]}
      dry = true when no pixel of the frame has any radar echo (any alpha)
      inside the 390 x 250 px view around centre (the area the panel shows),
      false when one has, null when the helper could not decode the tiles
      (only non-interlaced 8-bit RGBA, grey with alpha, or palette PNGs are
      read). A decode failure never drops the frame. A frame's tiles are <dir>/<x>_<y>.png for x in x0..x0+cols-1, y in
      y0..y0+rows-1; a frame is listed only when all its tiles are on disk.
      centre = the configured point in pixels from the block's top-left
      corner. Sent at the start of each radar fetch and again after each
      frame it completes (newest first). Frames no longer offered are
      deleted from disk after the event that drops them.
  {"event":"radar_error","at":t,"reason":"network"|"http"|"parse"|"tile"}
      tile: a tile was not a 256 px PNG, or was the provider's "Zoom Level
      Not Supported" picture.

stdin:
  {"cmd":"refresh"}            fetch forecast, air and warnings now
  {"cmd":"radar","on":true}    start fetching radar frames (the page is open)
  {"cmd":"radar","on":false}   stop; keep the cache
  Anything else is ignored with a line on stderr. When stdin closes the
  process exits.

Cadence: forecast every 20 min, air every 60 min, warnings every 15 min,
radar every 5 min only while on (and at once when turned on). After an
error a source retries at 60 s, doubling to 15 min. A refresh while a fetch
runs does not start a second one. Tile requests are spaced 0.8 s apart
(RainViewer allows 100 a minute per address).

Requests: the forecast and air-quality calls, the whole-UK warnings feed
(the region is never in a request), RainViewer's frame list and the fixed
block of zoom-6 tiles x 30-32, y 18-21 (the British Isles) from
https://tilecache.rainviewer.com, whatever the location. stdlib HTTP only,
a 20 s timeout on each, no redirects followed, User-Agent "desk-weather".
MQTT is subscribe only: this program has no code path that publishes.
"""

import argparse
import functools
import hashlib
import json
import math
import os
import re
import shutil
import struct
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zlib
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import paho.mqtt.client as mqtt

CONFIG = "@config@"
# "yes" only in the build the weather-helper check makes; it adds the
# --test-origin and --test-scale flags. The installed build never has them.
TESTING = "@testing@" == "yes"

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
AIR_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"
WARNINGS_URL = "https://www.metoffice.gov.uk/public/data/PWSCache/WarningsRSS/Region/UK"
RADAR_URL = "https://api.rainviewer.com/public/weather-maps.json"
TILE_HOSTS = {"https://tilecache.rainviewer.com"}
LINK_HOSTS = {"www.metoffice.gov.uk", "weather.metoffice.gov.uk"}

USER_AGENT = "desk-weather"
TIMEOUT = 20
MAX_BYTES = 4 << 20
MQTT_RETRY = 10

MINUTE = 60
INTERVALS = {"forecast": 20 * MINUTE, "air": 60 * MINUTE, "warnings": 15 * MINUTE,
             "radar": 5 * MINUTE}
RETRY_FIRST, RETRY_MAX = 60, 15 * MINUTE
TILE_GAP = 0.8

# The fixed radar block. Zoom 6 is below RainViewer's maximum of 7; above it
# the server answers with a picture, not an error.
ZOOM, TILE, X0, Y0, COLS, ROWS = 6, 256, 30, 18, 3, 4
# RainViewer's "Zoom Level Not Supported" picture, as served on 2026-11-22.
# A second guard only: the first is that no URL here asks above zoom 7.
NOT_SUPPORTED = {(1370, "1d406fd834a5cbed434471bb02a1d98a6dd89286a7a67826274a296fb871210c")}

UK = ZoneInfo("Europe/London")
LEVELS = {"red": 0, "amber": 1, "yellow": 2}
MONTHS = {m: i for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}
DAYS = {d: i for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])}
STAMP = r"(\d{4}) ([A-Z][a-z]{2}) (\d{1,2}) ([A-Z][a-z]{2})"
VALIDITY = re.compile(rf"^{STAMP} to {STAMP}$")
# Enclosure words -> the type as the title writes it.
TYPES = {"rain": "rain", "wind": "wind", "snow": "snow", "ice": "ice", "fog": "fog",
         "lightning": "lightning", "thunderstorm": "thunderstorms",
         "thunderstorms": "thunderstorms", "extreme-heat": "extreme heat",
         "heat": "extreme heat"}
FRAME_PATH = re.compile(r"^(/[A-Za-z0-9_-]+)+$")

LOCK = threading.Lock()


def emit(**obj):
    with LOCK:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def say(text):
    """A diagnostic on stderr. Callers pass fixed text and type names only."""
    with LOCK:
        sys.stderr.write(f"desk-weather: {text}\n")
        sys.stderr.flush()


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def valid_name(name):
    return (isinstance(name, str) and "+" not in name and "#" not in name
            and "" not in name.split("/"))


# ---- config ----------------------------------------------------------------

def load_config(path):
    """Returns (config, None) or (None, ("missing", None) | ("invalid", key)).
    key is the dotted key at fault, None for the whole file."""
    try:
        with open(path) as f:
            raw = json.load(f)
    except FileNotFoundError:
        return None, ("missing", None)
    except (OSError, ValueError, RecursionError):
        return None, ("invalid", None)
    return validate_config(raw)


def validate_config(raw):
    """The checked config with defaults filled, as for load_config."""
    if not isinstance(raw, dict):
        return None, ("invalid", None)
    lat, lon = raw.get("latitude"), raw.get("longitude")
    if not is_number(lat) or not -90 <= lat <= 90:
        return None, ("invalid", "latitude")
    if not is_number(lon) or not -180 <= lon <= 180:
        return None, ("invalid", "longitude")
    region = raw.get("warnings_region")
    if not isinstance(region, str) or not region.strip():
        return None, ("invalid", "warnings_region")
    m = raw.get("mqtt")
    if not isinstance(m, dict):
        return None, ("invalid", "mqtt")
    if not isinstance(m.get("host"), str) or not m["host"]:
        return None, ("invalid", "mqtt.host")
    port = m.get("port", 1883)
    if not isinstance(port, int) or isinstance(port, bool) or not 0 < port < 65536:
        return None, ("invalid", "mqtt.port")
    base = m.get("base", "zigbee2mqtt")
    if not valid_name(base):
        return None, ("invalid", "mqtt.base")
    sensor = m.get("sensor")
    if not valid_name(sensor) or sensor.split("/")[0] == "bridge":
        return None, ("invalid", "mqtt.sensor")
    lat, lon = round_point(lat, lon)
    return {"latitude": lat, "longitude": lon, "region": region,
            "host": m["host"], "port": port, "base": base, "sensor": sensor}, None


def round_point(lat, lon):
    """Latitude and longitude at 2 decimals; adding 0.0 turns -0.0 into 0.0."""
    return round(lat, 2) + 0.0, round(lon, 2) + 0.0


# ---- Open-Meteo ------------------------------------------------------------

CURRENT = [("temperature", "temperature_2m"), ("humidity", "relative_humidity_2m"),
           ("code", "weather_code"), ("is_day", "is_day"), ("cloud", "cloud_cover"),
           ("precipitation", "precipitation"), ("wind", "wind_speed_10m"),
           ("wind_dir", "wind_direction_10m"), ("gusts", "wind_gusts_10m")]
HOURLY = [("temperature", "temperature_2m"), ("code", "weather_code"), ("is_day", "is_day"),
          ("precipitation", "precipitation"), ("snowfall", "snowfall"),
          ("cloud", "cloud_cover")]
DAILY = [("code", "weather_code"), ("tmax", "temperature_2m_max"),
         ("tmin", "temperature_2m_min"), ("precipitation", "precipitation_sum"),
         ("snowfall", "snowfall_sum"), ("sunrise", "sunrise"), ("sunset", "sunset")]
AIR = [("aqi", "european_aqi"), ("pm2_5", "pm2_5"), ("pm10", "pm10"),
       ("no2", "nitrogen_dioxide"), ("o3", "ozone"), ("so2", "sulphur_dioxide")]
SUB = [("pm2_5", "european_aqi_pm2_5"), ("pm10", "european_aqi_pm10"),
       ("no2", "european_aqi_nitrogen_dioxide"), ("o3", "european_aqi_ozone"),
       ("so2", "european_aqi_sulphur_dioxide")]
POLLEN = ["alder", "birch", "grass", "mugwort", "olive", "ragweed"]


def point_query(lat, lon):
    return f"latitude={lat:.2f}&longitude={lon:.2f}"


def forecast_url(lat, lon):
    return (f"{FORECAST_URL}?{point_query(lat, lon)}"
            f"&current={','.join(k for _, k in CURRENT)}"
            f"&hourly={','.join(k for _, k in HOURLY)}"
            f"&daily={','.join(k for _, k in DAILY)}"
            "&timeformat=unixtime&timezone=auto&forecast_days=7")


def air_url(lat, lon):
    keys = [k for _, k in AIR] + [k for _, k in SUB] + [f"{p}_pollen" for p in POLLEN]
    return f"{AIR_URL}?{point_query(lat, lon)}&current={','.join(keys)}&timeformat=unixtime"


def number(v):
    return v if is_number(v) else None


def unix(v):
    """An integer time, or ValueError."""
    if not is_number(v) or v != int(v):
        raise ValueError("time")
    return int(v)


def column(block, key, n):
    values = block.get(key)
    if not isinstance(values, list):
        return [None] * n
    return [number(v) for v in values[:n]] + [None] * (n - len(values))


def forecast_event(data, fetched):
    """The forecast event from Open-Meteo's response (timeformat=unixtime);
    ValueError if it lacks the parts every view needs."""
    if not isinstance(data, dict):
        raise ValueError("not an object")
    offset = data.get("utc_offset_seconds")
    cur, hourly, daily = data.get("current"), data.get("hourly"), data.get("daily")
    if not (isinstance(offset, int) and isinstance(cur, dict)
            and isinstance(hourly, dict) and isinstance(daily, dict)):
        raise ValueError("shape")
    current = {"time": unix(cur.get("time"))}
    current.update({name: number(cur.get(key)) for name, key in CURRENT})

    times = hourly.get("time")
    if not isinstance(times, list):
        raise ValueError("hourly time")
    times = [unix(t) for t in times]
    columns = {name: column(hourly, key, len(times)) for name, key in HOURLY}
    start = current["time"] - current["time"] % 3600
    hours = [{"time": t, **{name: columns[name][i] for name, _ in HOURLY}}
             for i, t in enumerate(times) if t >= start][:48]

    days = daily.get("time")
    if not isinstance(days, list):
        raise ValueError("daily time")
    days = [unix(t) for t in days]
    columns = {name: column(daily, key, len(days)) for name, key in DAILY}
    rows = []
    for i, t in enumerate(days[:7]):
        # Each day's time is its local midnight; noon is the same day under
        # either side of a daylight-saving change within the week.
        date = datetime.fromtimestamp(t + offset + 12 * 3600, timezone.utc).date()
        row = {"date": date.isoformat()}
        for name, _ in DAILY:
            v = columns[name][i]
            row[name] = int(v) if name in ("sunrise", "sunset") and v is not None else v
        rows.append(row)
    return {"event": "forecast", "fetched": fetched, "utc_offset": offset,
            "current": current, "hourly": hours, "daily": rows}


def air_event(data, fetched):
    """The air event from Open-Meteo's air-quality response; ValueError if
    it has no current block."""
    if not isinstance(data, dict) or not isinstance(data.get("current"), dict):
        raise ValueError("shape")
    cur = data["current"]
    event = {"event": "air", "fetched": fetched}
    event.update({name: number(cur.get(key)) for name, key in AIR})
    event["sub"] = {name: number(cur.get(key)) for name, key in SUB}
    event["pollen"] = {p: number(cur.get(f"{p}_pollen")) for p in POLLEN}
    return event


# ---- Met Office warnings ---------------------------------------------------

def stamp_time(hhmm, day, date, month, now):
    """UTC seconds for one "HHMM Ddd DD Mon" in UK local time, the year
    nearest `now` whose weekday matches; None if none does."""
    if day not in DAYS or month not in MONTHS:
        return None
    hour, minute = int(hhmm[:2]), int(hhmm[2:])
    if hour > 23 or minute > 59:
        return None
    best = None
    year = datetime.fromtimestamp(now, UK).year
    for y in (year - 1, year, year + 1):
        try:
            local = datetime(y, MONTHS[month], int(date), hour, minute, tzinfo=UK)
        except ValueError:
            continue
        if local.weekday() != DAYS[day]:
            continue
        t = int(local.timestamp())
        if best is None or abs(t - now) < abs(best - now):
            best = t
    return best


def validity(when, now):
    """(from, to) from "HHMM Ddd DD Mon to HHMM Ddd DD Mon"; (None, None)
    when it does not parse or does not run forwards."""
    m = VALIDITY.match(when)
    if not m:
        return None, None
    start = stamp_time(*m.groups()[:4], now)
    end = stamp_time(*m.groups()[4:], now)
    if start is None or end is None or end <= start:
        return None, None
    return start, end


def allowed_link(link):
    try:
        u = urllib.parse.urlsplit(link)
    except ValueError:
        return False
    return (u.scheme == "https" and u.hostname in LINK_HOSTS and u.netloc == u.hostname
            and link.startswith(f"https://{u.hostname}/"))


def kind_from_enclosure(url):
    """(level, type) from an enclosure like ".../yellow-rain.png", or None."""
    name = urllib.parse.urlsplit(url).path.rsplit("/", 1)[-1]
    m = re.fullmatch(r"([a-z]+)-([a-z-]+)\.png", name)
    if not m or m.group(1) not in LEVELS:
        return None
    words, types = m.group(2).split("-"), []
    while words:
        for n in (2, 1):
            key = "-".join(words[:n])
            if len(words) >= n and key in TYPES:
                types.append(TYPES[key])
                words = words[n:]
                break
        else:
            return None
    return m.group(1), " and ".join(types)


def kind_from_title(title):
    m = re.fullmatch(r"(Yellow|Amber|Red) warning of (.+)", title)
    return (m.group(1).lower(), m.group(2)) if m else None


def squash(text):
    return " ".join((text or "").split())


def warning(item, region, now):
    """One feed item as a warnings entry, or None if it is not for `region`,
    has a link outside the allow-list, or has no level."""
    title = squash(item.findtext("title"))
    head, sep, place = title.partition(" affecting ")
    if not sep or place.casefold() != squash(region).casefold():
        return None
    link = squash(item.findtext("link"))
    if not allowed_link(link):
        return None
    enclosure = item.find("enclosure")
    kind = kind_from_enclosure(enclosure.get("url", "")) if enclosure is not None else None
    kind = kind or kind_from_title(head)
    if kind is None:
        return None
    description = squash(item.findtext("description"))
    body = description[len(title) + 1:] if description.startswith(title + ":") else description
    areas, _, when = body.partition("valid from ")
    areas = areas.strip().rstrip(",").strip()
    when = when.strip()
    start, end = validity(when, now)
    return {"level": kind[0], "type": kind[1], "title": head, "areas": areas,
            "from": start, "to": end, "when": when, "link": link}


def warnings_items(xml_bytes, region, now):
    """The region's warnings from the whole-UK RSS, most severe first, then
    earliest (unknown start last); ValueError if it is not RSS."""
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        raise ValueError("xml")
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise ValueError("not rss")
    items = [w for w in (warning(i, region, now) for i in channel.findall("item")) if w]
    items.sort(key=lambda w: (LEVELS[w["level"]], w["from"] is None, w["from"] or 0))
    return items


# ---- RainViewer ------------------------------------------------------------

def block_tiles():
    """The fixed tile block, (x, y) column by column."""
    return [(x, y) for x in range(X0, X0 + COLS) for y in range(Y0, Y0 + ROWS)]


def tile_url(host, path, x, y):
    return f"{host}{path}/{TILE}/{ZOOM}/{x}/{y}/2/1_0.png"


def centre(lat, lon):
    """The point in pixels from the block's top-left corner (Web Mercator)."""
    n = TILE * 2 ** ZOOM
    px = (lon + 180) / 360 * n
    phi = math.radians(lat)
    py = (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2 * n
    return [round(px - X0 * TILE, 1), round(py - Y0 * TILE, 1)]


def radar_frames(data):
    """(host, [(time, path, id)] oldest first) from weather-maps.json;
    ValueError for anything this program will not request."""
    if not isinstance(data, dict):
        raise ValueError("shape")
    host, radar = data.get("host"), data.get("radar")
    if host not in TILE_HOSTS or not isinstance(radar, dict) or not isinstance(radar.get("past"), list):
        raise ValueError("shape")
    frames = []
    for f in radar["past"]:
        if not isinstance(f, dict) or not isinstance(f.get("path"), str):
            raise ValueError("frame")
        if not FRAME_PATH.match(f["path"]):
            raise ValueError("path")
        frames.append((unix(f.get("time")), f["path"], f["path"].rsplit("/", 1)[-1]))
    frames.sort()
    return host, frames


def tile_ok(data):
    """Whether bytes are a 256 px PNG and not the "Zoom Level Not Supported"
    picture (by size or content)."""
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return False
    if struct.unpack(">II", data[16:24]) != (TILE, TILE):
        return False
    sizes = {size for size, _ in NOT_SUPPORTED}
    digests = {digest for _, digest in NOT_SUPPORTED}
    return len(data) not in sizes and hashlib.sha256(data).hexdigest() not in digests


def png_alpha(data, rows):
    """The alpha of each pixel in the first `rows` rows of a non-interlaced
    256 px PNG, as one bytes object per row (palette transparency counts as
    alpha); None for anything else: 8-bit RGBA or grey with alpha, or a
    palette of 1, 2, 4 or 8 bits."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    i, header, idat, trns = 8, None, [], b""
    while i + 8 <= len(data):
        (n,), kind = struct.unpack(">I", data[i:i + 4]), data[i + 4:i + 8]
        body = data[i + 8:i + 8 + n]
        if kind == b"IHDR":
            header = body
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IEND":
            break
        i += 12 + n
    if header is None or len(header) != 13:
        return None
    width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", header)
    channels = {6: 4, 4: 2, 3: 1}.get(colour)
    if (width, height) != (TILE, TILE) or interlace or channels is None:
        return None
    if (colour != 3 and depth != 8) or (colour == 3 and depth not in (1, 2, 4, 8)):
        return None
    try:
        raw = zlib.decompress(b"".join(idat))
    except zlib.error:
        return None
    stride = (width * channels * depth + 7) // 8
    if len(raw) < (stride + 1) * rows:
        return None
    step = max(1, channels * depth // 8)
    prior, out = bytearray(stride), []
    for r in range(rows):
        kind = raw[r * (stride + 1)]
        line = bytearray(raw[r * (stride + 1) + 1:(r + 1) * (stride + 1)])
        if kind == 1:
            for k in range(step, stride):
                line[k] = (line[k] + line[k - step]) & 255
        elif kind == 2:
            for k in range(stride):
                line[k] = (line[k] + prior[k]) & 255
        elif kind == 3:
            for k in range(stride):
                left = line[k - step] if k >= step else 0
                line[k] = (line[k] + ((left + prior[k]) >> 1)) & 255
        elif kind == 4:
            for k in range(stride):
                a = line[k - step] if k >= step else 0
                b, c = prior[k], prior[k - step] if k >= step else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[k] = (line[k] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        elif kind != 0:
            return None
        prior = line
        if colour == 6:
            out.append(bytes(line[3::4]))
        elif colour == 4:
            out.append(bytes(line[1::2]))
        else:
            per = 8 // depth
            mask = (1 << depth) - 1
            alpha = bytearray(width)
            for px in range(width):
                index = (line[px // per] >> (8 - depth * (px % per + 1))) & mask
                alpha[px] = trns[index] if index < len(trns) else 255
            out.append(bytes(alpha))
    return out


def view_box(point):
    """The panel's 390 x 250 px view around `point`, as (left, top, right,
    bottom) in block pixels, right and bottom exclusive."""
    cx, cy = point
    return (math.floor(cx - 195), math.floor(cy - 125),
            math.floor(cx - 195) + 390, math.floor(cy - 125) + 250)


def frame_dry(read_tile, box):
    """True when no pixel inside `box` has any alpha, False when one has, None
    when a tile it needs cannot be decoded. read_tile(x, y) gives a tile's
    bytes. Pixels outside the block count as dry."""
    left, top, right, bottom = box
    for x, y in block_tiles():
        tx, ty = (x - X0) * TILE, (y - Y0) * TILE
        x1, x2 = max(left, tx) - tx, min(right, tx + TILE) - tx
        y1, y2 = max(top, ty) - ty, min(bottom, ty + TILE) - ty
        if x1 >= x2 or y1 >= y2:
            continue
        try:
            rows = png_alpha(read_tile(x, y), y2)
        except OSError:
            rows = None
        if rows is None:
            return None
        if any(any(row[x1:x2]) for row in rows[y1:y2]):
            return False
    return True


def read_tile(directory, x, y):
    with open(os.path.join(directory, f"{x}_{y}.png"), "rb") as f:
        return f.read()


# ---- schedule --------------------------------------------------------------

def retry_delay(failures):
    """Seconds before the next try after `failures` errors in a row (>= 1)."""
    return min(RETRY_FIRST * 2 ** (failures - 1), RETRY_MAX)


# ---- HTTP ------------------------------------------------------------------

class Problem(Exception):
    """A fetch failed; args[0] is the reason the error event carries."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


class Http:
    def __init__(self, origin=None):
        self.origin = origin

    def get(self, url):
        if self.origin:
            u = urllib.parse.urlsplit(url)
            url = self.origin + urllib.parse.urlunsplit(("", "", u.path, u.query, ""))
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with OPENER.open(request, timeout=TIMEOUT) as r:
                data = r.read(MAX_BYTES + 1)
        except urllib.error.HTTPError:
            raise Problem("http")
        except (urllib.error.URLError, OSError, ValueError):
            raise Problem("network")
        if len(data) > MAX_BYTES:
            raise Problem("parse")
        return data

    def json(self, url):
        data = self.get(url)
        try:
            return json.loads(data)
        except (ValueError, RecursionError):
            raise Problem("parse")


# ---- the sources -----------------------------------------------------------

class Source:
    def __init__(self, name, run, enabled=True):
        self.name, self.run, self.enabled = name, run, enabled
        self.due = 0.0
        self.failures = 0
        self.running = False


class Weather:
    def __init__(self, config, cache, http, scale):
        self.config, self.cache, self.http, self.scale = config, cache, http, scale
        self.cond = threading.Condition()
        self.dry = {}  # frame id -> its "dry"
        self.sources = {
            "forecast": Source("forecast", self.fetch_forecast),
            "air": Source("air", self.fetch_air),
            "warnings": Source("warnings", self.fetch_warnings),
            "radar": Source("radar", self.fetch_radar, enabled=False),
        }

    def start(self):
        threading.Thread(target=self.schedule, daemon=True).start()

    def schedule(self):
        with self.cond:
            while True:
                now = time.monotonic()
                waits = []
                for s in self.sources.values():
                    if not s.enabled or s.running:
                        continue
                    if s.due <= now:
                        s.running = True
                        threading.Thread(target=self.work, args=(s,), daemon=True).start()
                    else:
                        waits.append(s.due - now)
                self.cond.wait(min(waits) if waits else None)

    def work(self, source):
        try:
            source.run()
            ok = True
        except Problem as e:
            ok, reason = False, e.args[0]
        except Exception as e:
            ok, reason = False, "parse"
            say(f"{source.name}: {type(e).__name__}")
        with self.cond:
            if ok:
                source.failures = 0
                source.due = time.monotonic() + INTERVALS[source.name] * self.scale
            else:
                source.failures += 1
                source.due = time.monotonic() + retry_delay(source.failures) * self.scale
            source.running = False
            self.cond.notify()
        if not ok and source.enabled:
            emit(event=f"{source.name}_error", at=int(time.time()), reason=reason)

    def refresh(self):
        with self.cond:
            for name in ("forecast", "air", "warnings"):
                self.sources[name].due = 0.0
            self.cond.notify()

    def radar(self, on):
        with self.cond:
            source = self.sources["radar"]
            if on and not source.enabled:
                source.due = 0.0
            source.enabled = on
            self.cond.notify()

    def fetch_forecast(self):
        c = self.config
        data = self.http.json(forecast_url(c["latitude"], c["longitude"]))
        try:
            event = forecast_event(data, int(time.time()))
        except ValueError:
            raise Problem("parse")
        emit(**event)

    def fetch_air(self):
        c = self.config
        data = self.http.json(air_url(c["latitude"], c["longitude"]))
        try:
            event = air_event(data, int(time.time()))
        except ValueError:
            raise Problem("parse")
        emit(**event)

    def fetch_warnings(self):
        data = self.http.get(WARNINGS_URL)
        fetched = int(time.time())
        try:
            items = warnings_items(data, self.config["region"], fetched)
        except ValueError:
            raise Problem("parse")
        emit(event="warnings", fetched=fetched, items=items)

    def fetch_radar(self):
        data = self.http.json(RADAR_URL)
        fetched = int(time.time())
        try:
            host, frames = radar_frames(data)
        except ValueError:
            raise Problem("parse")
        root = os.path.join(self.cache, "radar")
        os.makedirs(root, exist_ok=True)
        self.report_radar(fetched, frames, root)
        for t, path, fid in reversed(frames):
            directory = os.path.join(root, fid)
            if self.complete(directory):
                continue
            os.makedirs(directory, exist_ok=True)
            for x, y in block_tiles():
                target = os.path.join(directory, f"{x}_{y}.png")
                if os.path.exists(target):
                    continue
                if not self.sources["radar"].enabled:
                    return
                time.sleep(TILE_GAP * self.scale)
                tile = self.http.get(tile_url(host, path, x, y))
                if not tile_ok(tile):
                    raise Problem("tile")
                temporary = os.path.join(directory, f".{x}_{y}.png.tmp")
                with open(temporary, "wb") as f:
                    f.write(tile)
                os.replace(temporary, target)
            self.report_radar(fetched, frames, root)

    @staticmethod
    def complete(directory):
        return all(os.path.exists(os.path.join(directory, f"{x}_{y}.png"))
                   for x, y in block_tiles())

    def report_radar(self, fetched, frames, root):
        c = self.config
        point = centre(c["latitude"], c["longitude"])
        listed = []
        for t, _, fid in frames:
            directory = os.path.join(root, fid)
            if not self.complete(directory):
                continue
            # Tiles of a frame never change once complete, so each is
            # decoded once per process.
            if fid not in self.dry:
                self.dry[fid] = frame_dry(functools.partial(read_tile, directory),
                                          view_box(point))
            listed.append({"time": t, "dir": directory, "dry": self.dry[fid]})
        emit(event="radar", fetched=fetched, zoom=ZOOM, tile=TILE, x0=X0, y0=Y0,
             cols=COLS, rows=ROWS, centre=point, frames=listed)
        offered = {fid for _, _, fid in frames}
        for name in os.listdir(root):
            if name not in offered:
                shutil.rmtree(os.path.join(root, name), ignore_errors=True)
                self.dry.pop(name, None)


# ---- MQTT ------------------------------------------------------------------

def reading_time(last_seen, arrival):
    """Zigbee2MQTT's last_seen (ISO 8601, or epoch milliseconds) in Unix
    seconds, else `arrival`."""
    if isinstance(last_seen, str):
        try:
            seen = datetime.fromisoformat(last_seen)
        except ValueError:
            return arrival
        if seen.tzinfo is None:
            seen = seen.replace(tzinfo=timezone.utc)
        return int(seen.timestamp())
    if is_number(last_seen):
        return int(last_seen // 1000)
    return arrival


def link_quality(v):
    """Zigbee2MQTT's linkquality as an integer 0..255, else None."""
    if not is_number(v) or v != int(v) or not 0 <= v <= 255:
        return None
    return int(v)


def reading(payload, arrival):
    """The sensor event's reading fields from one Zigbee2MQTT state message
    (a dict), in the event's key order."""
    return {"temperature": number(payload.get("temperature")),
            "humidity": number(payload.get("humidity")),
            "battery": number(payload.get("battery")),
            "linkquality": link_quality(payload.get("linkquality")),
            "at": reading_time(payload.get("last_seen"), arrival)}


def availability_of(payload):
    """True, False, or None (not an availability message)."""
    text = payload.decode(errors="replace").strip()
    try:
        value = json.loads(text)
        state = value.get("state") if isinstance(value, dict) else None
    except (ValueError, RecursionError):
        state = text
    return {"online": True, "offline": False}.get(state)


class Sensor:
    def __init__(self, config):
        self.topic = f"{config['base']}/{config['sensor']}"
        self.config = config
        self.reading = {"temperature": None, "humidity": None, "battery": None,
                        "linkquality": None, "at": None}
        self.available = True
        self.broker = None
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, clean_session=True)
        self.client.reconnect_delay_set(MQTT_RETRY, MQTT_RETRY)
        self.client.on_connect = self.on_connect
        self.client.on_connect_fail = lambda client, userdata: self.set_broker("lost")
        self.client.on_disconnect = lambda *args: self.set_broker("lost")
        self.client.on_message = self.on_message
        self.stopping = threading.Event()

    def start(self):
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        try:
            # The first connection is made here: paho's own first retry
            # waits twice the delay.
            while True:
                try:
                    self.client.connect(self.config["host"], self.config["port"], keepalive=30)
                    break
                except OSError:
                    self.set_broker("lost")
                if self.stopping.wait(MQTT_RETRY):
                    return
            self.client.loop_forever()
        except BaseException as e:
            say(f"mqtt: {type(e).__name__}")
        if self.stopping.is_set():
            return
        self.set_broker("lost")
        say("mqtt: network thread ended")
        with LOCK:
            os._exit(1)

    def stop(self):
        self.stopping.set()
        self.client.disconnect()

    def set_broker(self, state):
        if state != self.broker and not self.stopping.is_set():
            self.broker = state
            emit(event="broker", state=state)

    def on_connect(self, client, userdata, flags, reason, properties):
        if reason.is_failure:
            self.set_broker("lost")
            return
        self.set_broker("connected")
        client.subscribe([(self.topic, 0), (f"{self.topic}/availability", 0)])

    def on_message(self, client, userdata, msg):
        if msg.topic == f"{self.topic}/availability":
            available = availability_of(msg.payload)
            if available is not None and available != self.available:
                self.available = available
                self.report()
        elif msg.topic == self.topic:
            try:
                payload = json.loads(msg.payload)
            except (ValueError, RecursionError):
                return
            if not isinstance(payload, dict):
                return
            self.reading = reading(payload, int(time.time()))
            self.report()

    def report(self):
        emit(event="sensor", **self.reading, available=self.available)


# ---- main ------------------------------------------------------------------

def default_cache():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "desk-weather")


def command(line):
    """("refresh",) or ("radar", bool); ValueError otherwise."""
    msg = json.loads(line)
    if msg == {"cmd": "refresh"}:
        return ("refresh",)
    if isinstance(msg, dict) and set(msg) == {"cmd", "on"} and msg["cmd"] == "radar" \
            and isinstance(msg["on"], bool):
        return ("radar", msg["on"])
    raise ValueError("command")


def main():
    parser = argparse.ArgumentParser(prog="desk-weather")
    parser.add_argument("--config", default=CONFIG)
    parser.add_argument("--cache", default=None)
    if TESTING:
        parser.add_argument("--test-origin", required=True)
        parser.add_argument("--test-scale", type=float, default=1.0)
    args = parser.parse_args()
    origin, scale = None, 1.0
    if TESTING:
        if not re.fullmatch(r"http://127\.0\.0\.1:\d+", args.test_origin):
            raise SystemExit("desk-weather: --test-origin must be http://127.0.0.1:<port>")
        origin, scale = args.test_origin, args.test_scale

    config, problem = load_config(args.config)
    weather = sensor = None
    if problem:
        state, key = problem
        if state == "missing":
            emit(event="config", state="missing")
        else:
            emit(event="config", state="invalid", key=key)
    else:
        emit(event="config", state="ok")
        sensor = Sensor(config)
        sensor.start()
        weather = Weather(config, args.cache or default_cache(), Http(origin), scale)
        weather.start()

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            cmd = command(line)
        except (ValueError, RecursionError):
            say("ignored a line that is not a command")
            continue
        if weather is None:
            continue
        if cmd[0] == "refresh":
            weather.refresh()
        else:
            weather.radar(cmd[1])

    if sensor:
        sensor.stop()
    with LOCK:
        sys.stdout.flush()
        os._exit(0)


if __name__ == "__main__":
    main()
