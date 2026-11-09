"""Fuel price poller and monthly fuel cost model for the HA car view.

fuel-price poll   Fetch one station's E10 price from the UK Fuel Finder API
                  and write it to $STATE_DIRECTORY/e10.json.
fuel-price cost   Work out per-month fuel spend and a projection from the
                  car's history in VictoriaMetrics, and write it to
                  $STATE_DIRECTORY/cost.json.

Credentials come from systemd credentials: "fuel-finder" holds
FUEL_FINDER_CLIENT_ID and FUEL_FINDER_CLIENT_SECRET, "fuel-finder-station"
holds FUEL_FINDER_NODE_ID.
"""

import calendar
import csv
import datetime as dt
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from bisect import bisect_right
from pathlib import Path

API = "https://www.fuel-finder.service.gov.uk/api/v1"
VM = "http://127.0.0.1:8428"
NATIONAL_PAGE = "https://www.gov.uk/government/statistics/weekly-road-fuel-prices"
HEADERS = {"User-Agent": "nexus-fuel-price/1.0", "Accept": "application/json"}
UTC = dt.timezone.utc
DAY = 86400

# A rise in the tank reading bigger than this between two samples is a fill.
# The car reports whole litres, and the reading wobbles by one or two.
FILL_MIN_LITRES = 5
# Driving pace for the projection is averaged over this window.
PACE_WINDOW_DAYS = 90
# Projected months shown after the current one.
PROJECT_AHEAD = 2

CAR = "sensor.volvo_xc40_"
LOCAL_PRICE = "sensor.fuel_price_e10_local_value"

STATE = Path(os.environ.get("STATE_DIRECTORY", "."))


def http(url, data=None, headers=None, timeout=60):
    req = urllib.request.Request(url, data=data, headers={**HEADERS, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def write_json(path, obj):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj))
    tmp.replace(path)


def credential(name):
    values = {}
    text = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text()
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            values[key.strip()] = value.strip()
    return values


def poll():
    creds = credential("fuel-finder") | credential("fuel-finder-station")
    node = creds["FUEL_FINDER_NODE_ID"]
    token = json.loads(http(
        f"{API}/oauth/generate_access_token",
        json.dumps({
            "client_id": creds["FUEL_FINDER_CLIENT_ID"],
            "client_secret": creds["FUEL_FINDER_CLIENT_SECRET"],
        }).encode(),
        {"Content-Type": "application/json"},
    ))["data"]["access_token"]

    out = STATE / "e10.json"
    since = STATE / "since"
    started = dt.datetime.now(UTC)
    params = {}
    # Ask only for prices changed since the last run. e10.json is rewritten
    # only when the station shows up, so once a day without a change this
    # falls back to the full snapshot (about 17 batches) to resync.
    if out.exists() and since.exists() and time.time() - out.stat().st_mtime < DAY:
        start = dt.datetime.fromisoformat(since.read_text()) - dt.timedelta(minutes=5)
        params["effective-start-timestamp"] = start.strftime("%Y-%m-%d %H:%M:%S")

    found = None
    batch = 1
    while True:
        query = urllib.parse.urlencode({"batch-number": batch, **params})
        try:
            rows = json.loads(http(
                f"{API}/pfs/fuel-prices?{query}",
                headers={"Authorization": f"Bearer {token}"},
            ))
        except urllib.error.HTTPError as err:
            # 404 marks the end of the batches; on batch 1 of an incremental
            # query it means nothing changed.
            if err.code == 404:
                break
            raise
        if not rows:
            break
        for row in rows:
            if row.get("node_id") == node:
                found = row
        batch += 1
        time.sleep(2.1)  # the API rate-limits bursts; stay above 2 s apart

    if found:
        e10 = next(p for p in found["fuel_prices"] if p["fuel_type"] == "E10")
        write_json(out, {
            "price": e10["price"],
            "changed": e10["price_change_effective_timestamp"],
            "station": found["trading_name"],
        })
    elif not params:
        sys.exit(f"station {node} not in the full snapshot")
    since.write_text(started.isoformat())


def vm_series(name):
    """All raw samples of a metric as sorted (unix seconds, value) pairs."""
    query = urllib.parse.urlencode({"match[]": '{__name__="%s"}' % name})
    points = []
    for line in http(f"{VM}/api/v1/export?{query}").splitlines():
        series = json.loads(line)
        points += zip((t / 1000 for t in series["timestamps"]), series["values"])
    return sorted(points)


def national_prices():
    """Weekly UK average unleaded pump price, (unix seconds, pence/litre)."""
    path = STATE / "national.csv"
    if not path.exists() or time.time() - path.stat().st_mtime > DAY:
        page = http(NATIONAL_PAGE).decode()
        # The file's URL changes with every weekly release.
        match = re.search(r'https://assets\.publishing\.service\.gov\.uk/[^"]*2018[^"]*\.csv', page)
        if not match:
            sys.exit("no 2018-onwards CSV on the weekly road fuel prices page")
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(http(match.group(0)))
        tmp.replace(path)
    rows = csv.reader(io.StringIO(path.read_text(encoding="utf-8-sig")))
    next(rows)
    return sorted(
        (dt.datetime.strptime(r[0], "%d/%m/%Y").replace(tzinfo=UTC).timestamp(), float(r[1]))
        for r in rows if len(r) > 1 and r[1]
    )


def at(series, ts):
    """Value of a step series at ts, or None before its first sample."""
    i = bisect_right(series, (ts, float("inf")))
    return series[i - 1][1] if i else None


def month_start(year, month):
    year, month = year + (month - 1) // 12, (month - 1) % 12 + 1
    return dt.datetime(year, month, 1, tzinfo=UTC)


def cost():
    # Months run in UTC; at most an hour off London time at a month edge.
    now = dt.datetime.now(UTC)
    fuel = vm_series(CAR + "fuel_amount_value")
    odo = vm_series(CAR + "odometer_value")
    usage = vm_series(CAR + "trip_manual_average_fuel_consumption_value")
    local = vm_series(LOCAL_PRICE)
    national = national_prices()
    if not fuel or not odo or not usage:
        sys.exit("no car history in VictoriaMetrics")

    current = STATE / "e10.json"
    price_now = json.loads(current.read_text())["price"] if current.exists() else at(local, now.timestamp())
    if price_now is None:
        sys.exit("no local price yet; run fuel-price poll first")

    # How far the local station sits from the national average. Measured on
    # the national weeks the local history covers; until it covers one, use
    # today's local price against the latest national week.
    gaps = [at(local, t) - p for t, p in national if at(local, t) is not None]
    offset = sum(gaps) / len(gaps) if gaps else price_now - national[-1][1]

    def price_at(ts):
        local_price = at(local, ts)
        if local_price is not None:
            return local_price
        return at(national, ts) + offset

    first = dt.datetime.fromtimestamp(odo[0][0], UTC)
    months = []
    y, m = first.year, first.month
    while month_start(y, m) <= now:
        start, end = month_start(y, m).timestamp(), month_start(y, m + 1).timestamp()
        km_start = at(odo, start) or odo[0][1]
        km_end = at(odo, min(end, now.timestamp()))
        months.append({
            "month": f"{y:04d}-{m:02d}",
            "km": round(km_end - km_start),
            "litres": 0,
            "cost": 0.0,
            "fills": 0,
        })
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)

    by_month = {row["month"]: row for row in months}
    for (_, before), (ts, after) in zip(fuel, fuel[1:]):
        if after - before > FILL_MIN_LITRES:
            row = by_month.get(dt.datetime.fromtimestamp(ts, UTC).strftime("%Y-%m"))
            if row is None:
                continue
            row["litres"] += after - before
            row["cost"] += (after - before) * price_at(ts) / 100
            row["fills"] += 1
    for row in months:
        row["cost"] = round(row["cost"], 2)

    window_start = max(odo[0][0], now.timestamp() - PACE_WINDOW_DAYS * DAY)
    km_per_day = (odo[-1][1] - at(odo, window_start)) / max((now.timestamp() - window_start) / DAY, 1)
    l_per_100km = usage[-1][1]

    estimates = []
    for ahead in range(PROJECT_AHEAD + 1):
        start = month_start(now.year, now.month + ahead)
        days = calendar.monthrange(start.year, start.month)[1]
        estimates.append({
            "month": start.strftime("%Y-%m"),
            "cost": round(km_per_day * days * l_per_100km / 100 * price_now / 100, 2),
        })

    prices = [
        [int(t * 1000), round(price_at(t), 1)]
        for t, _ in national if t >= month_start(first.year, first.month).timestamp()
    ]
    prices.append([int(now.timestamp() * 1000), price_now])

    write_json(STATE / "cost.json", {
        "estimate_month": estimates[0]["cost"],
        "price": price_now,
        "offset": round(offset, 1),
        "km_per_month": round(km_per_day * 30.44),
        "l_per_100km": l_per_100km,
        "months": months,
        "estimates": estimates,
        "prices": prices,
    })


if __name__ == "__main__":
    {"poll": poll, "cost": cost}[sys.argv[1]]()
