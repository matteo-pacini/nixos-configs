"""desk-tokens: its pure functions, then the built helper against invented
transcripts in temporary trees, with the clock fixed and the time zone set per
case.

Usage: test-desk-tokens.py <desk-tokens> <desk-tokens.py> <prices.json> <work dir>

Every id, path, counter and price here is made up, except the shipped price
table, which is only checked for shape. Transcripts carry only the keys the
helper reads, plus a few it must ignore. The files it must never open (a
workflow's journal, .meta.json, tool-results, memory) hold valid-looking
replies with huge counters and are made unreadable, so opening one shows in
the totals or in the "unreadable" count.
"""

import importlib.util
import json
import os
import queue
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

HELPER, SOURCE, SHIPPED, WORK = sys.argv[1:5]

spec = importlib.util.spec_from_file_location("desk_tokens", SOURCE)
tok = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tok)

FAILURES = []
CHECKS = [0]
NOW = "2026-11-17T12:00:00Z"


def check(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILURES.append(name)
        print(f"FAIL {name}: {detail}")


def eq(name, got, want):
    check(name, got == want, f"got {got!r}, want {want!r}")


def near(name, got, want):
    check(name, got is not None and abs(got - want) < 1e-9, f"got {got!r}, want {want!r}")


def epoch(text):
    return int(datetime.fromisoformat(text).timestamp())


def uid(n):
    return f"{n:08x}-0000-4000-8000-000000000000"


REPOS = "/home/user/Repositories"
ALPHA = REPOS + "/alpha"


def rec(mid, rid, ts, session, out=0, inp=1, read=0, w5=0, w1=0, model="claude-opus-5-5",
        cwd=ALPHA, side=False, parts=True, total_write=None):
    usage = {"input_tokens": inp, "output_tokens": out, "cache_read_input_tokens": read,
             "cache_creation_input_tokens": w5 + w1 if total_write is None else total_write,
             "service_tier": "standard"}
    if parts:
        usage["cache_creation"] = {"ephemeral_5m_input_tokens": w5, "ephemeral_1h_input_tokens": w1}
    message = {"model": model, "role": "assistant", "usage": usage,
               "content": [{"type": "text", "text": "an invented reply"}]}
    if mid:
        message["id"] = mid
    obj = {"type": "assistant", "timestamp": ts, "sessionId": session, "isSidechain": side,
           "cwd": cwd, "message": message, "gitBranch": "invented-branch"}
    if rid:
        obj["requestId"] = rid
    if side:
        obj["agentId"] = "a0"
    return json.dumps(obj) + "\n"


def noise(size=2000):
    return json.dumps({"type": "user", "message": {"role": "user", "content": "x" * size}}) + "\n"


def put(path, *lines, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write("".join(lines))


class Helper:
    def __init__(self, projects, state, now=NOW, tz="UTC", prices=None, default_prices=False):
        env = {"PATH": os.environ.get("PATH", ""), "TZ": tz, "TZDIR": os.environ.get("TZDIR", ""),
               "HOME": os.path.join(WORK, "home")}
        args = [HELPER, "--projects", projects, "--state", state, "--now", now]
        if not default_prices:
            args += ["--prices", prices or TEST_PRICES]
        self.p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, text=True)
        self.q = queue.Queue()
        self.events, self.seen, self.times = [], [], []
        self.next_id = 1
        threading.Thread(target=self.pump, daemon=True).start()

    def pump(self):
        for line in self.p.stdout:
            self.q.put(json.loads(line))
        self.q.put(None)

    def get(self, timeout=60):
        m = self.q.get(timeout=timeout)
        if m is not None:
            self.seen.append(m)
            if "event" in m:
                self.events.append(m)
                self.times.append(time.monotonic())
        return m

    def until(self, pred, timeout=60):
        while True:
            m = self.get(timeout)
            if m is None:
                raise RuntimeError("helper ended early")
            if pred(m):
                return m

    def done(self):
        return self.until(lambda m: m.get("event") == "progress" and m["state"] == "done")

    def send(self, req):
        req = dict(req, id=self.next_id)
        self.next_id += 1
        self.p.stdin.write(json.dumps(req) + "\n")
        self.p.stdin.flush()
        return req["id"]

    def ask(self, req, **kw):
        i = self.send(dict(req, **kw))
        return self.until(lambda m: m.get("answer") is not None and m.get("id") == i)

    def close(self):
        self.p.stdin.close()
        rc = self.p.wait(timeout=60)
        while self.get(5) is not None:
            pass
        return rc


def strip(obj):
    if isinstance(obj, dict):
        return {k: strip(v) for k, v in obj.items() if k not in ("id", "progress")}
    if isinstance(obj, list):
        return [strip(v) for v in obj]
    return obj


def summary(h):
    return strip([h.ask({"req": "overview"}), h.ask({"req": "projects", "period": "30d"}),
                  h.ask({"req": "days"})])


def run(tree, state, now=NOW, tz="UTC", **kw):
    """A complete sync, then the summary; returns (summary, final progress, helper events)."""
    h = Helper(tree, state, now, tz, **kw)
    final = h.done()
    s = summary(h)
    eq(f"exit 0 ({os.path.basename(tree)})", h.close(), 0)
    return s, final, h


def one(tree, state, req, now=NOW, tz="UTC", **kw):
    h = Helper(tree, state, now, tz, **kw)
    h.done()
    a = h.ask(req)
    eq(f"exit 0 ({req['req']})", h.close(), 0)
    return a


def by_name(rows, name):
    return next((r for r in rows if r["name"] == name), None)


os.makedirs(WORK, exist_ok=True)
TEST_PRICES = os.path.join(WORK, "prices.json")
with open(TEST_PRICES, "w") as f:
    json.dump({"source": "invented", "checked": "2026-01-01", "models": {
        "claude-opus-5-5": {"input": 4, "output": 20, "cache_write_5m": 5, "cache_write_1h": 8, "cache_read": 0.2},
        "claude-haiku-5-5": {"input": 0.1, "output": 0.5, "cache_write_5m": 0.125, "cache_write_1h": 0.2,
                             "cache_read": 0.01,
                             "above": {"prompt_tokens": 100000, "input": 0.5, "output": 2.5,
                                       "cache_write_5m": 0.625, "cache_write_1h": 1, "cache_read": 0.05}},
        "claude-broken": {"input": 1}}}, f)


# --- Pure functions ----------------------------------------------------------

line = rec("msg_p1", "req_p1", "2026-11-17T10:00:00.000Z", uid(1), out=7, inp=2, read=30, w5=4, w1=5)
r = tok.parse_line(line.encode())
eq("parse: key", r["key"], "msg_p1:req_p1")
eq("parse: counters", [r[t] for t in tok.TYPES], [2, 7, 30, 4, 5])
eq("parse: time", r["ts"], epoch("2026-11-17T10:00:00Z"))
r = tok.parse_line(rec("m", "r", "2026-11-17T10:00:00.000Z", uid(1), w5=1, w1=2, total_write=700, parts=False).encode())
eq("parse: no cache_creation object, all 5-minute", (r["cache_write_5m"], r["cache_write_1h"]), (700, 0))
eq("parse: no usage bytes, not parsed", tok.parse_line(b'{"type": "assistant", broken\n'), None)
eq("parse: invalid JSON", tok.parse_line(b'{"type":"assistant","message":{"usage":\n'), "bad_lines")
eq("parse: user record with usage", tok.parse_line(
    b'{"type":"user","requestId":"r","message":{"id":"m","usage":{"output_tokens":5}}}\n'), None)
eq("parse: synthetic", tok.parse_line(rec("m", "r", "2026-11-17T10:00:00Z", uid(1), model="<synthetic>").encode()),
   "synthetic")
eq("parse: no message id", tok.parse_line(rec(None, "r", "2026-11-17T10:00:00Z", uid(1)).encode()), "no_id")
eq("parse: no request id", tok.parse_line(rec("m", None, "2026-11-17T10:00:00Z", uid(1)).encode()), "no_id")

eq("active: gaps under 10 minutes", tok.active_seconds([0, 300, 1200, 1500, 2400, 2999]), 300 + 300 + 599)
eq("active: exactly 10 minutes left out", tok.active_seconds([0, 600]), 0)
eq("active: none", tok.active_seconds([]), 0)

entries = [("a", "main", 1, 100, 1000.0), ("b", "main", 2, 50, 3000.0), ("c", "sub", 3, 70, 2000.0),
           ("d", "main", 4, 10, 500.0), ("e", "main", 5, 40, 4000.0)]
stored = {"a": (1, 100), "c": (3, 30), "d": (9, 5), "e": (5, 90)}
plan = tok.plan_reads(entries, stored)
eq("plan: newest first, unchanged skipped", [p[0] for p in plan], ["e", "b", "c", "d"])
eq("plan: starts (shrunk, new, appended, replaced)", [p[5] for p in plan], [0, 0, 30, 0])
B = {"today": 2500, "7d": 1500, "14d": 800, "30d": 0}
eq("plan: period cuts", tok.period_cuts(plan, B), {"today": 2, "7d": 3, "14d": 3, "30d": 4})

table = tok.load_prices(TEST_PRICES)["models"]
costs = tok.reply_costs((0, "s", "claude-opus-5-5", 0, 1000, 2000, 10000, 3000, 4000), table["claude-opus-5-5"])
check("prices: hand-computed cost per type",
      all(abs(g - w) < 1e-12 for g, w in zip(costs, (0.004, 0.04, 0.002, 0.015, 0.032))), str(costs))
eq("prices: an entry missing a rate is unpriced", "claude-broken" in table, False)
eq("prices: dated id takes its base id's row", tok.price_for("claude-opus-5-5-20261101", table) is table["claude-opus-5-5"], True)
eq("prices: other suffix is not a match", tok.price_for("claude-opus-5-5-fast", table), None)
eq("prices: unknown model unpriced", tok.price_for("claude-x", table), None)
HAIKU = table["claude-haiku-5-5"]
near("prices: Haiku at a 100000-token prompt, lower rates",
     sum(tok.reply_costs((0, "s", "claude-haiku-5-5", 0, 0, 1000, 100000, 0, 0), HAIKU)),
     (1000 * 0.5 + 100000 * 0.01) / 1e6)
near("prices: Haiku over 100000, every rate higher",
     sum(tok.reply_costs((0, "s", "claude-haiku-5-5", 0, 1, 1000, 100000, 0, 0), HAIKU)),
     (1 * 0.5 + 1000 * 2.5 + 100000 * 0.05) / 1e6)
near("prices: Haiku tier counts cache writes in the prompt",
     sum(tok.reply_costs((0, "s", "claude-haiku-5-5", 0, 0, 0, 99999, 1, 1), HAIKU)),
     (99999 * 0.05 + 0.625 + 1) / 1e6)
eq("cost object: none at all is priced", tok.cost_obj(0.0, 0, 0), {"usd": 0.0, "priced": True, "partial": False})
eq("cost object: only unpriced", tok.cost_obj(0.0, 0, 2), {"usd": 0.0, "priced": False, "partial": False})
eq("cost object: mixed", tok.cost_obj(1.5, 1, 2), {"usd": 1.5, "priced": True, "partial": True})

shipped = tok.load_prices(SHIPPED)
eq("shipped prices: six models",
   sorted(shipped["models"]), sorted(["claude-opus-5-5", "claude-opus-5", "claude-fable-5-2", "claude-fable-5-1",
                                      "claude-sonnet-5-5", "claude-haiku-5-5"]))
eq("shipped prices: Haiku tier", shipped["models"]["claude-haiku-5-5"].get("above", {}).get("prompt_tokens"), 100000)
check("shipped prices: source and checked", bool(shipped["source"]) and bool(shipped["checked"]))

src = open(SOURCE).read()
for word in ("urllib", "http.", "socket", "subprocess", "credentials"):
    check(f"source never names {word}", word not in src)

# Folding, on a real tree.
FS = os.path.join(WORK, "fs")
R = os.path.join(FS, "Repositories")
for d in ("alpha/.git", "alpha/sub/deep", "alpha-feature", "alpha/.claude/worktrees/agent-1", "beta/.git",
          "subm/.git", "subm/mod", "alpha-two/.git"):
    os.makedirs(os.path.join(R, d), exist_ok=True)
os.makedirs(os.path.join(FS, "plain"), exist_ok=True)
put(os.path.join(R, "alpha-feature/.git"), f"gitdir: {R}/alpha/.git/worktrees/alpha-feature\n")
put(os.path.join(R, "alpha/.claude/worktrees/agent-1/.git"), "gitdir: ../../../.git/worktrees/agent-1\n")
put(os.path.join(R, "subm/mod/.git"), "gitdir: ../.git/modules/mod\n")
A, A2 = os.path.join(R, "alpha"), os.path.join(R, "alpha-two")
known = {A, A2}
folds = {
    "checkout": (A, set(), (A, "alpha", "git", True)),
    "subdirectory": (A + "/sub/deep", set(), (A, "alpha", "git", True)),
    "sibling worktree by .git file": (R + "/alpha-feature", set(), (A, "alpha", "git", True)),
    ".claude worktree, relative gitdir": (A + "/.claude/worktrees/agent-1", set(), (A, "alpha", "git", True)),
    "submodule stands alone": (R + "/subm/mod", set(), (R + "/subm/mod", "mod", "git", True)),
    "removed worktree by name": (R + "/alpha-gone", known, (A, "alpha", "name", False)),
    "documented wrong fold: repo-x into repo": (R + "/alpha-x", known, (A, "alpha", "name", False)),
    "longest prefix wins": (R + "/alpha-two-gone", known, (A2, "alpha-two", "name", False)),
    "scratch key": ("/tmp/claude-1000/" + tok.encode(A) + "/s/scratchpad", known, (A, "alpha", "scratch", False)),
    "scratch key of a worktree": ("/tmp/claude-1000/" + tok.encode(R + "/alpha-feature") + "/x", known,
                                  (A, "alpha", "scratch", False)),
    "scratch key matching nothing": ("/tmp/claude-1000/-home-user-elsewhere/x", known,
                                     ("-home-user-elsewhere", "-home-user-elsewhere", "scratch", False)),
    "gone .claude/worktrees folds to its repo": (R + "/beta/.claude/worktrees/gone-1", set(),
                                                 (R + "/beta", "beta", "worktree", False)),
    "/tmp/tmp.*": ("/tmp/tmp.Ab12Cd", known, ("/tmp/tmp.*", "temporary directories", "temp", True)),
    "/tmp/tmp.* subdirectory": ("/tmp/tmp.Zz9/sub", known, ("/tmp/tmp.*", "temporary directories", "temp", True)),
    "plain directory": (FS + "/plain", known, (FS + "/plain", "plain", "alone", True)),
    "gone, matching nothing": (FS + "/gone-plain", known, (FS + "/gone-plain", "gone-plain", "gone", False)),
}
for name, (cwd, checkouts, want) in folds.items():
    eq(f"fold: {name}", tok.fold_cwd(cwd, checkouts), want)

# Day boundaries in this process, across both DST changes.
os.environ["TZ"] = "Europe/London"
time.tzset()
b = tok.bounds(epoch("2026-10-26T12:00:00+00:00"))
eq("bounds London: the day DST ends is 25 h", b["days"][13] - b["days"][12], 25 * 3600)
os.environ["TZ"] = "Pacific/Auckland"
time.tzset()
b = tok.bounds(epoch("2026-10-01T00:00:00+00:00"))
i = b["days"].index(epoch("2026-09-26T12:00:00+00:00"))
eq("bounds Auckland: the day DST starts is 23 h", b["days"][i + 1] - b["days"][i], 23 * 3600)
os.environ["TZ"] = "UTC"
time.tzset()

# --- The helper: duplicates, partial lines, sub-agents, skipped lines -------

TA = os.path.join(WORK, "tree-a")
SA = os.path.join(WORK, "state-a")
KEY = tok.encode(ALPHA)
S1, S2 = uid(1), uid(2)
main1 = os.path.join(TA, KEY, S1 + ".jsonl")
partial = rec("msg_08", "req_08", "2026-11-17T10:35:00.000Z", S1, out=100)
put(main1,
    rec("msg_01", "req_01", "2026-11-17T10:00:00.000Z", S1, out=5, inp=3, read=1000),
    rec("msg_01", "req_01", "2026-11-17T10:00:01.000Z", S1, out=30, inp=3, read=1000),
    rec("msg_01", "req_01", "2026-11-17T10:00:02.000Z", S1, out=20, inp=3, read=1000),
    json.dumps({"type": "user", "sessionId": S1, "message": {"role": "user", "content": "usage"}}) + "\n",
    json.dumps({"type": "user", "sessionId": S1, "requestId": "req_u1",
                "message": {"id": "msg_u1", "usage": {"output_tokens": 5000}}}) + "\n",
    rec("msg_02", "req_02", "2026-11-17T10:05:00.000Z", S1, out=10, w1=500),
    rec("msg_03", "req_03", "2026-11-17T10:20:00.000Z", S1, out=3, total_write=700, parts=False),
    rec("msg_04", "req_04", "2026-11-17T10:21:00.000Z", S1, out=1000, model="<synthetic>"),
    rec(None, "req_05", "2026-11-17T10:22:00.000Z", S1, out=2000),
    rec("msg_06", None, "2026-11-17T10:23:00.000Z", S1, out=2000),
    '{"type":"assistant","message":{"usage":{"output_tokens": 4000\n',
    rec("msg_07", "req_07", "2026-11-17T10:30:00.000Z", S1, out=7),
    partial[:40])

h = Helper(TA, SA)
final = h.done()
ov = h.ask({"req": "overview"})
eq("streaming duplicates: max wins, synthetic, no-id, user and invalid lines not counted",
   dict(ov["today"], cost=None), {"output": 30 + 10 + 3 + 7, "sessions": 1, "cache_read": 1000, "cost": None})
eq("skipped counts", final["skipped"], {"bad_lines": 1, "no_id": 2, "synthetic": 1})
m = ov["last30"]["models"][0]
eq("cache writes apart", (m["cache_write_5m"], m["cache_write_1h"]), (700, 500))
eq("exit 0 on EOF", h.close(), 0)
mode = os.stat(os.path.join(SA, "index.sqlite")).st_mode & 0o777
eq("index mode 0600", oct(mode), oct(0o600))
eq("state directory mode 0700", oct(os.stat(SA).st_mode & 0o777), oct(0o700))

put(main1, partial[40:], mode="a")
s, final, h = run(TA, SA)
eq("truncated line counted once completed", s[0]["today"]["output"], 150)
eq("only the completed line is read again", final["bytes_read"], len(partial.encode()))
s, final, h = run(TA, SA)
eq("second run, nothing changed: no file read", (final["files_total"], final["bytes_read"]), (0, 0))
eq("second run, same totals", s[0]["today"]["output"], 150)

put(main1, rec("msg_01", "req_01", "2026-11-17T10:00:03.000Z", S1, out=40, inp=3, read=1000),
    rec("msg_01", "req_01", "2026-11-17T10:00:04.000Z", S1, out=1, inp=3, read=1000), mode="a")
s, final, h = run(TA, SA)
eq("duplicate across the stored offset: max, not sum, not last", s[0]["today"]["output"], 160)
fresh, _, _ = run(TA, os.path.join(WORK, "state-a-fresh"))
eq("a reply grown across the offset is priced again: equal to a build from scratch", s, fresh)

base = os.path.join(TA, KEY, S1)
put(os.path.join(TA, KEY, S2 + ".jsonl"),
    rec("msg_02", "req_02", "2026-11-17T10:05:00.000Z", S2, out=10, w1=500),
    rec("msg_09", "req_09", "2026-11-17T10:40:00.000Z", S2, out=9))
WT = ALPHA + "/.claude/worktrees/agent-a1"
put(os.path.join(base, "subagents", "agent-a1.jsonl"),
    rec("msg_10", "req_10", "2026-11-17T10:10:00.000Z", S1, out=50, side=True, cwd=WT))
put(os.path.join(base, "subagents", "workflows", "wf1", "agent-a2.jsonl"),
    rec("msg_11", "req_11", "2026-11-17T10:12:00.000Z", S1, out=60, side=True))
never = [os.path.join(base, "subagents", "workflows", "wf1", "wf1.jsonl"),
         os.path.join(base, "subagents", "agent-a1.meta.json"),
         os.path.join(base, "tool-results", "t1.jsonl"),
         os.path.join(TA, KEY, "memory", "notes.jsonl")]
for n, path in enumerate(never):
    put(path, rec(f"msg_9{n}", f"req_9{n}", "2026-11-17T10:50:00.000Z", S1, out=999999), "\x00{garbage\n")
    os.chmod(path, 0)
s, final, h = run(TA, SA)
eq("files that are not transcripts never opened", final["unreadable"], 0)
eq("same reply in a fork, sub-agents and workflow sub-agents counted once",
   dict(s[0]["today"], cost=None), {"output": 160 + 9 + 50 + 60, "sessions": 2, "cache_read": 1000, "cost": None})
eq("sub-agent output", s[0]["last30"]["subagent_output"], 110)
alpha = by_name(s[1]["projects"], "alpha")
eq("sub-agent replies count in the parent's project", (alpha["output"], alpha["subagent_output"]), (279, 110))
d = one(TA, SA, {"req": "project", "project": None, "period": "7d"})
eq("project request needs an integer id", d.get("error"), "bad project")
pid = one(TA, SA, {"req": "projects", "period": "7d"})["projects"][0]["id"]
d = one(TA, SA, {"req": "project", "project": pid, "period": "7d"})
sessions = {x["id"]: x for x in d["sessions"]}
eq("session S1: output with sub-agents, main replies only, active time without them",
   {k: sessions[S1][k] for k in ("output", "replies", "active_seconds", "first_reply", "last_reply")},
   {"output": 40 + 10 + 3 + 7 + 100 + 110, "replies": 5, "active_seconds": 600,
    "first_reply": epoch("2026-11-17T10:00:00+00:00"), "last_reply": epoch("2026-11-17T10:35:00+00:00")})
eq("forked reply belongs to the smaller session id", (sessions[S2]["output"], sessions[S2]["replies"]), (9, 1))
eq("project totals", {k: d["totals"][k] for k in ("output", "share", "sessions", "subagent_output")},
   {"output": 279, "share": 1.0, "sessions": 2, "subagent_output": 110})
eq("project totals: models", [(m["model"], m["output"]) for m in d["totals"]["models"]], [("claude-opus-5-5", 279)])
eq("project: 14 days", (len(d["last14"]["days"]), d["last14"]["peak"]["output"]), (14, 279))
eq("unknown project", one(TA, SA, {"req": "project", "project": 9999, "period": "7d"}).get("error"),
   "unknown project")
eq("bad period", one(TA, SA, {"req": "projects", "period": "1y"}).get("error"), "bad period")
eq("unknown request", one(TA, SA, {"req": "nothing"}).get("error"), "unknown request")

con = sqlite3.connect(os.path.join(SA, "index.sqlite"))
tables = {t: [c[1] for c in con.execute(f"PRAGMA table_info({t})")]
          for (t,) in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
con.close()
eq("schema holds ids, paths, model names and numbers only", tables, {
    "files": ["path", "kind", "inode", "read_to"],
    "projects": ["id", "key", "name"],
    "folds": ["id", "cwd", "project", "how", "final"],
    "replies": ["key", "session", "ts", "model", "sub", "cwd", "input", "output", "cache_read",
                "cache_write_5m", "cache_write_1h", "usd_input", "usd_output", "usd_cache_read",
                "usd_cache_write_5m", "usd_cache_write_1h", "usd", "stale"],
    "meta": ["key", "value"]})

# --- Shrunk, replaced and deleted files -------------------------------------

TB = os.path.join(WORK, "tree-b")
KB = tok.encode(REPOS + "/beta")
b1, b2 = os.path.join(TB, KB, uid(11) + ".jsonl"), os.path.join(TB, KB, uid(12) + ".jsonl")
X = [rec(f"msg_x{i}", f"req_x{i}", f"2026-11-17T09:0{i}:00.000Z", uid(11), out=o, cwd=REPOS + "/beta")
     for i, o in ((1, 10), (2, 20), (3, 5))]
Y = [rec(f"msg_y{i}", f"req_y{i}", f"2026-11-17T08:0{i}:00.000Z", uid(12), out=o, cwd=REPOS + "/beta")
     for i, o in ((0, 3), (1, 100), (2, 1))]
put(b1, noise(), noise(), noise(), X[0], X[1])
put(b2, Y[1])
SB = os.path.join(WORK, "state-b")
run(TB, SB)
put(b1, X[0], X[1], X[2])
s, final, h = run(TB, SB)
fresh, _, _ = run(TB, os.path.join(WORK, "state-b-fresh-1"))
eq("shrunk file: totals equal a build from scratch", s, fresh)
eq("shrunk file: output", s[0]["today"]["output"], 135)
tmp = b2 + ".new"
put(tmp, Y[0], Y[1], Y[2], noise())
os.replace(tmp, b2)
s, final, h = run(TB, SB)
fresh, _, _ = run(TB, os.path.join(WORK, "state-b-fresh-2"))
eq("replaced file (new inode, longer): totals equal a build from scratch", s, fresh)
eq("replaced file: its first line read", s[0]["today"]["output"], 139)
os.remove(b1)
s, final, h = run(TB, SB)
eq("deleted file keeps its replies", s[0]["today"]["output"], 139)

con = sqlite3.connect(os.path.join(SB, "index.sqlite"))
con.execute("PRAGMA user_version = 99")
con.close()
s, final, h = run(TB, SB)
eq("schema version mismatch: rebuilt from scratch", s[0]["today"]["output"], 104)

# --- Time zones and days ------------------------------------------------------

TC = os.path.join(WORK, "tree-c")
KC = tok.encode(REPOS + "/gamma")
put(os.path.join(TC, KC, uid(21) + ".jsonl"),
    rec("msg_c1", "req_c1", "2026-11-16T23:30:00.000Z", uid(21), out=11, cwd=REPOS + "/gamma"),
    rec("msg_c2", "req_c2", "2026-11-17T08:00:00.000Z", uid(21), out=13, cwd=REPOS + "/gamma"))
s, _, _ = run(TC, os.path.join(WORK, "state-c-lon"), tz="Europe/London")
eq("London: 23:30 UTC on the 16th is yesterday", s[0]["today"]["output"], 13)
eq("London: days newest first", [x["output"] for x in s[2]["days"][:3]], [13, 11, 0])
eq("London: 14 days, zero days included", (len(s[0]["last14"]["days"]),
                                           sum(1 for x in s[0]["last14"]["days"] if x["output"] == 0)), (14, 12))
eq("London: today starts at local midnight", s[0]["bounds"]["today"], epoch("2026-11-17T00:00:00+00:00"))
eq("London: the 14 days oldest first, today last", s[0]["last14"]["days"][13]["start"], s[0]["bounds"]["today"])
s, _, _ = run(TC, os.path.join(WORK, "state-c-akl"), now="2026-11-17T09:00:00Z", tz="Pacific/Auckland")
eq("Auckland: 23:30 UTC on the 16th is today", s[0]["today"]["output"], 24)
eq("Auckland: today starts at local midnight", s[0]["bounds"]["today"], epoch("2026-11-16T11:00:00+00:00"))

TC2 = os.path.join(WORK, "tree-c2")
put(os.path.join(TC2, KC, uid(22) + ".jsonl"),
    rec("msg_d1", "req_d1", "2026-10-24T23:30:00.000Z", uid(22), out=1, cwd=REPOS + "/gamma"),
    rec("msg_d2", "req_d2", "2026-10-25T23:30:00.000Z", uid(22), out=2, cwd=REPOS + "/gamma"))
s, _, _ = run(TC2, os.path.join(WORK, "state-c2"), now="2026-10-26T12:00:00Z", tz="Europe/London")
eq("London, the 25-hour day: both ends in one day", [x["output"] for x in s[2]["days"][:3]], [0, 3, 0])
eq("London, the 25-hour day: its start", s[2]["days"][1]["start"], epoch("2026-10-24T23:00:00+00:00"))

TC3 = os.path.join(WORK, "tree-c3")
put(os.path.join(TC3, KC, uid(23) + ".jsonl"),
    rec("msg_e1", "req_e1", "2026-11-16T12:00:00.000Z", uid(23), out=6, cwd=REPOS + "/gamma"),
    rec("msg_e2", "req_e2", "2026-11-16T23:50:00.000Z", uid(23), out=5, cwd=REPOS + "/gamma"))
s, _, _ = run(TC3, os.path.join(WORK, "state-c3"), now="2026-11-17T00:05:00Z", tz="Europe/London")
ZERO = {"usd": 0.0, "priced": True, "partial": False}
eq("just after midnight: today empty, its cost zero and priced", s[0]["today"],
   {"output": 0, "sessions": 0, "cache_read": 0, "cost": ZERO})
eq("just after midnight: yesterday complete", s[2]["days"][1]["output"], 11)
p = one(TC3, os.path.join(WORK, "state-c3"), {"req": "projects", "period": "today"}, now="2026-11-17T00:05:00Z",
        tz="Europe/London")
eq("just after midnight: no project today, cost zero and priced",
   (p["ready"], p["projects"], p["output"], p["cost"], p["unpriced_models"]), (True, [], 0, ZERO, []))

# Auckland at 00:30 on the 17th is still the 16th in UTC.
TC4 = os.path.join(WORK, "tree-c4")
put(os.path.join(TC4, KC, uid(24) + ".jsonl"),
    rec("msg_f1", "req_f1", "2026-11-16T10:50:00.000Z", uid(24), out=3, cwd=REPOS + "/gamma"),
    rec("msg_f2", "req_f2", "2026-11-16T11:10:00.000Z", uid(24), out=4, cwd=REPOS + "/gamma"))
s, _, _ = run(TC4, os.path.join(WORK, "state-c4"), now="2026-11-16T11:30:00Z", tz="Pacific/Auckland")
eq("Auckland after local midnight, UTC date behind: today is local",
   (s[0]["bounds"]["today"], s[0]["today"]["output"], s[2]["days"][1]["output"]),
   (epoch("2026-11-16T11:00:00+00:00"), 4, 3))

# --- Distinct sessions across a window ------------------------------------

TD = os.path.join(WORK, "tree-d")
KD = tok.encode(REPOS + "/delta")
SD, SE = uid(31), uid(32)
put(os.path.join(TD, KD, SD + ".jsonl"), *[
    rec(f"msg_s{d}", f"req_s{d}", f"2026-11-{d}T10:00:00.000Z", SD, out=1, cwd=REPOS + "/delta")
    for d in (15, 16, 17)])
put(os.path.join(TD, KD, SE + ".jsonl"),
    rec("msg_t1", "req_t1", "2026-11-17T11:00:00.000Z", SE, out=1, cwd=REPOS + "/delta"))
s, _, _ = run(TD, os.path.join(WORK, "state-d"))
p = one(TD, os.path.join(WORK, "state-d"), {"req": "projects", "period": "7d"})
eq("a session active on three days counts once in 7 days", p["projects"][0]["sessions"], 2)
eq("and once in each of its days", [x["sessions"] for x in s[2]["days"][:4]], [2, 1, 1, 0])
eq("days: top project", s[2]["days"][0]["top"]["name"], "delta")
top7 = s[0]["top7"]
eq("overview: top projects", ([(p["name"], p["output"]) for p in top7["projects"]], top7["more"], top7["output"]),
   ([("delta", 4)], 0, 4))

# --- Active time read in three pieces ----------------------------------------

TE = os.path.join(WORK, "tree-e")
KE = tok.encode(REPOS + "/eps")
SX = uid(41)
t0 = epoch("2026-11-17T09:00:00+00:00")
lines = [rec(f"msg_a{i}", f"req_a{i}", datetime.fromtimestamp(t0 + o, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
             SX, out=1, cwd=REPOS + "/eps") for i, o in enumerate([0, 300, 1200, 1500, 2400, 2999])]
fe = os.path.join(TE, KE, SX + ".jsonl")
SEP = os.path.join(WORK, "state-e")
for piece in (lines[0:2], lines[2:4], lines[4:6]):
    put(fe, *piece, mode="a")
    run(TE, SEP)
pid = one(TE, SEP, {"req": "projects", "period": "today"})["projects"][0]["id"]
a = one(TE, SEP, {"req": "project", "project": pid, "period": "today"})["sessions"][0]
eq("active time, three pieces", (a["active_seconds"], a["replies"]), (1199, 6))
SEF = os.path.join(WORK, "state-e-fresh")
pid = one(TE, SEF, {"req": "projects", "period": "today"})["projects"][0]["id"]
eq("active time, one piece", one(TE, SEF, {"req": "project", "project": pid, "period": "today"})
   ["sessions"][0]["active_seconds"], 1199)

# --- Folds remembered and tried again ----------------------------------------

TG = os.path.join(WORK, "tree-g")
SG = os.path.join(WORK, "state-g")
os.makedirs(os.path.join(R, "zz-worktree"), exist_ok=True)
put(os.path.join(R, "zz-worktree/.git"), f"gitdir: {R}/alpha/.git/worktrees/zz-worktree\n")


def session_file(n, cwd, ts="2026-11-17T09:00:00.000Z", out=1):
    put(os.path.join(TG, tok.encode(cwd), uid(n) + ".jsonl"), rec(f"msg_g{n}", f"req_g{n}", ts, uid(n), out=out, cwd=cwd))


session_file(51, R + "/zz-worktree", out=10)
session_file(52, R + "/beta2-old", out=20)
run(TG, SG)
shutil.rmtree(os.path.join(R, "zz-worktree"))
os.makedirs(os.path.join(R, "beta2/.git"))
session_file(53, R + "/beta2", out=40)
session_file(54, R + "/alpha-gone2", out=5)
p = one(TG, SG, {"req": "projects", "period": "today"})
eq("a git fold is kept after the directory goes; name folds tried again",
   sorted((x["name"], x["output"]) for x in p["projects"]), [("alpha", 15), ("beta2", 60)])

# --- Prices through the helper ----------------------------------------------

TH = os.path.join(WORK, "tree-h")
KH = tok.encode(REPOS + "/eta")
put(os.path.join(TH, KH, uid(61) + ".jsonl"),
    rec("msg_h1", "req_h1", "2026-11-17T09:00:00.000Z", uid(61), inp=1000, out=2000, read=10000, w5=3000, w1=4000,
        cwd=REPOS + "/eta"),
    rec("msg_h2", "req_h2", "2026-11-17T09:01:00.000Z", uid(61), out=500, model="claude-opus-5", cwd=REPOS + "/eta"),
    rec("msg_h3", "req_h3", "2026-11-17T09:02:00.000Z", uid(61), inp=1, out=1000, read=100000,
        model="claude-haiku-5-5", cwd=REPOS + "/eta"))
s, _, _ = run(TH, os.path.join(WORK, "state-h"))
l30 = s[0]["last30"]
near("prices: estimate through the helper", l30["cost_usd"], 0.093 + (1 * 0.5 + 1000 * 2.5 + 100000 * 0.05) / 1e6)
eq("prices: unpriced model listed", l30["unpriced_models"], ["claude-opus-5"])
eq("prices: checked date passed on", l30["prices_checked"], "2026-01-01")
near("cache hit", l30["cache_hit"], 110000 / (110000 + 7000 + 1001 + 1))
s1, _, _ = run(TH, os.path.join(WORK, "state-h2"), default_prices=True)
s2, _, _ = run(TH, os.path.join(WORK, "state-h3"), prices=SHIPPED)
eq("built-in price table is the shipped one", s1, s2)
eq("shipped table prices every model here", s1[0]["last30"]["unpriced_models"], [])

# --- Cost in every answer -----------------------------------------------------
# In Auckland (UTC+13 in November) with now 09:00 UTC on the 17th, local
# today began at 11:00 UTC on the 16th. kappa's session has an Opus reply
# with both cache writes and a sub-agent reply today, two Haiku replies
# yesterday (one over the tier, one at it: summed by model they would be
# over), and one reply of an unpriced model today; lam has only an unpriced
# reply, the day before yesterday.

TK = os.path.join(WORK, "tree-k")
SK = os.path.join(WORK, "state-k")
KAPPA, LAM = REPOS + "/kappa", REPOS + "/lam"
K1, L1 = uid(81), uid(82)
put(os.path.join(TK, tok.encode(KAPPA), K1 + ".jsonl"),
    rec("msg_k1", "req_k1", "2026-11-16T23:30:00.000Z", K1, inp=1000, out=2000, read=10000, w5=3000, w1=4000,
        cwd=KAPPA),
    rec("msg_k2", "req_k2", "2026-11-16T10:30:00.000Z", K1, inp=1, out=1000, read=100000, model="claude-haiku-5-5",
        cwd=KAPPA),
    rec("msg_k3", "req_k3", "2026-11-16T10:40:00.000Z", K1, inp=0, out=1000, read=100000, model="claude-haiku-5-5",
        cwd=KAPPA),
    rec("msg_k5", "req_k5", "2026-11-17T02:00:00.000Z", K1, inp=1, out=50, model="claude-x", cwd=KAPPA))
put(os.path.join(TK, tok.encode(KAPPA), K1, "subagents", "agent-k4.jsonl"),
    rec("msg_k4", "req_k4", "2026-11-17T01:00:00.000Z", K1, inp=10, out=100, side=True, cwd=KAPPA))
put(os.path.join(TK, tok.encode(LAM), L1 + ".jsonl"),
    rec("msg_l1", "req_l1", "2026-11-14T12:00:00.000Z", L1, inp=1, out=70, model="claude-x", cwd=LAM))
NOW_K, TZ_K = "2026-11-17T09:00:00Z", "Pacific/Auckland"

OPUS_K1 = {"input": 0.004, "output": 0.04, "cache_read": 0.002, "cache_write_5m": 0.015, "cache_write_1h": 0.032}
HAIKU_OVER = (1 * 0.5 + 1000 * 2.5 + 100000 * 0.05) / 1e6
HAIKU_AT = (1000 * 0.5 + 100000 * 0.01) / 1e6
SUB_K4 = (10 * 4 + 100 * 20) / 1e6
BY_TYPE = {"input": 0.004 + (0.5 + 40) / 1e6, "output": 0.04 + (2500 + 500 + 2000) / 1e6,
           "cache_read": 0.002 + (5000 + 1000) / 1e6, "cache_write_5m": 0.015, "cache_write_1h": 0.032}
TODAY_K = sum(OPUS_K1.values()) + SUB_K4
YESTERDAY_K = HAIKU_OVER + HAIKU_AT
ALL_K = TODAY_K + YESTERDAY_K
UNPRICED = {"usd": 0.0, "priced": False, "partial": False}


def cost_is(name, got, usd, priced=True, partial=False):
    check(name, got is not None and abs(got["usd"] - usd) < 1e-12 and got["priced"] is priced
          and got["partial"] is partial, f"got {got!r}, want usd {usd}, priced {priced}, partial {partial}")


def by_type_is(name, got, want):
    check(name, set(got) == set(want) and all(abs(got[t] - want[t]) < 1e-12 for t in want), f"got {got!r}")


s, final, _ = run(TK, SK, now=NOW_K, tz=TZ_K)
ov, pr, dy = s
cost_is("cost: today, Opus and a sub-agent, one unpriced reply", ov["today"]["cost"], TODAY_K, partial=True)
days = ov["last14"]["days"]
cost_is("cost: yesterday, Haiku priced reply by reply", days[12]["cost"], YESTERDAY_K)
eq("cost: a day of unpriced replies only", days[11]["cost"], UNPRICED)
eq("cost: a zero day", days[10]["cost"], ZERO)
eq("cost: peak carries its day's cost", ov["last14"]["peak"], days[13])
l30 = ov["last30"]
cost_is("cost: 30 days", l30["cost"], ALL_K, partial=True)
by_type_is("cost: 30 days by type, 5-minute and 1-hour writes at their rates", l30["cost"]["by_type"], BY_TYPE)
near("cost: by type sums to usd", sum(l30["cost"]["by_type"].values()), l30["cost"]["usd"])
eq("cost: cost_usd is last30.cost.usd", l30["cost_usd"], l30["cost"]["usd"])
eq("cost: unpriced model listed", l30["unpriced_models"], ["claude-x"])
models = {m["model"]: m["cost"] for m in l30["models"]}
cost_is("cost: Opus model", models["claude-opus-5-5"], sum(OPUS_K1.values()) + SUB_K4)
cost_is("cost: Haiku model", models["claude-haiku-5-5"], YESTERDAY_K)
eq("cost: unpriced model alone", models["claude-x"], UNPRICED)
near("cost: model costs sum to the total", sum(c["usd"] for c in models.values()), l30["cost"]["usd"])
top = {p["name"]: p["cost"] for p in ov["top7"]["projects"]}
cost_is("cost: top project, mixed", top["kappa"], ALL_K, partial=True)
eq("cost: top project, unpriced only", top["lam"], UNPRICED)
cost_is("cost: all 7 days", ov["top7"]["cost"], ALL_K, partial=True)
cost_is("cost: projects page, the period", pr["cost"], ALL_K, partial=True)
eq("cost: projects page, unpriced listed", pr["unpriced_models"], ["claude-x"])
cost_is("cost: projects page, a row", by_name(pr["projects"], "kappa")["cost"], ALL_K, partial=True)
eq("cost: projects page, an unpriced row", by_name(pr["projects"], "lam")["cost"], UNPRICED)
want_days = {0: (TODAY_K, True, True), 1: (YESTERDAY_K, True, False), 2: (0.0, False, False), 3: (0.0, True, False)}
for i, (usd, priced, partial) in want_days.items():
    cost_is(f"cost: days page, day {i} (local days)", dy["days"][i]["cost"], usd, priced, partial)
p = one(TK, SK, {"req": "projects", "period": "today"}, now=NOW_K, tz=TZ_K)
cost_is("cost: projects today, local day", p["cost"], TODAY_K, partial=True)
eq("cost: projects today, the unpriced row is not there", [x["name"] for x in p["projects"]], ["kappa"])

ids = {x["name"]: x["id"] for x in one(TK, SK, {"req": "projects", "period": "30d"}, now=NOW_K, tz=TZ_K)["projects"]}
d = one(TK, SK, {"req": "project", "project": ids["kappa"], "period": "30d"}, now=NOW_K, tz=TZ_K)
cost_is("cost: project totals", d["totals"]["cost"], ALL_K, partial=True)
by_type_is("cost: project totals by type", d["totals"]["cost"]["by_type"], BY_TYPE)
eq("cost: project token sums per type", d["totals"]["tokens"],
   {"input": 1012, "output": 4150, "cache_read": 210000, "cache_write_5m": 3000, "cache_write_1h": 4000})
eq("cost: project unpriced listed", d["unpriced_models"], ["claude-x"])
pmodels = {m["model"]: m["cost"] for m in d["totals"]["models"]}
cost_is("cost: project model split, Haiku", pmodels["claude-haiku-5-5"], YESTERDAY_K)
eq("cost: project model split, unpriced", pmodels["claude-x"], UNPRICED)
cost_is("cost: session, sub-agent replies included", d["sessions"][0]["cost"], ALL_K, partial=True)
cost_is("cost: project's day, local", d["last14"]["days"][13]["cost"], TODAY_K, partial=True)
d = one(TK, SK, {"req": "project", "project": ids["lam"], "period": "30d"},
        now=NOW_K, tz=TZ_K)
eq("cost: unpriced project", (d["totals"]["cost"]["usd"], d["totals"]["cost"]["priced"], d["unpriced_models"],
                              d["sessions"][0]["cost"]), (0.0, False, ["claude-x"], UNPRICED))

# A changed price table reprices the stored costs without reading a
# transcript, and the old table brings the old figures back.
DEARER = os.path.join(WORK, "prices-dearer.json")
with open(TEST_PRICES) as f:
    dearer = json.load(f)
dearer["models"]["claude-opus-5-5"]["output"] = 40
with open(DEARER, "w") as f:
    json.dump(dearer, f)
s2, final, _ = run(TK, SK, now=NOW_K, tz=TZ_K, prices=DEARER)
eq("reprice: no transcript read", (final["files_total"], final["bytes_read"]), (0, 0))
cost_is("reprice: today follows the table", s2[0]["today"]["cost"], TODAY_K + (2000 + 100) * 20 / 1e6, partial=True)
fresh, _, _ = run(TK, os.path.join(WORK, "state-k-dearer"), now=NOW_K, tz=TZ_K, prices=DEARER)
eq("reprice: equal to a build from scratch at the new table", s2, fresh)
s3, final, _ = run(TK, SK, now=NOW_K, tz=TZ_K)
eq("reprice: back to the old table, the old figures", (s3, final["bytes_read"]), (s, 0))

# An index built by the previous schema (no cost columns, no meta table):
# the same index with them taken out again.
SK1 = os.path.join(WORK, "state-k-v1")
shutil.copytree(SK, SK1)
con = sqlite3.connect(os.path.join(SK1, "index.sqlite"))
con.execute("DROP INDEX replies_stale")
con.execute("DROP INDEX replies_window")
con.execute("DROP TABLE meta")
for c in tok.USD_COLS + ("usd", "stale"):
    con.execute(f"ALTER TABLE replies DROP COLUMN {c}")
con.execute("CREATE INDEX replies_ts ON replies (ts)")
con.execute("PRAGMA user_version = 1")
eq("schema 1 index: the previous layout", [c[1] for c in con.execute("PRAGMA table_info(replies)")],
   ["key", "session", "ts", "model", "sub", "cwd", "input", "output", "cache_read", "cache_write_5m",
    "cache_write_1h"])
con.close()
s4, final, _ = run(TK, SK1, now=NOW_K, tz=TZ_K)
eq("schema 1 index: upgraded in place, no transcript read", (final["files_total"], final["bytes_read"]), (0, 0))
eq("schema 1 index: totals equal a build from scratch", s4, s)
con = sqlite3.connect(os.path.join(SK1, "index.sqlite"))
eq("schema 1 index: now schema 2, the window index replacing the time index",
   (con.execute("PRAGMA user_version").fetchone()[0],
    sorted(n for (n,) in con.execute("SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL"))),
   (2, ["replies_session", "replies_stale", "replies_window"]))
con.close()

# --- First run: order, readiness, not ready, SIGTERM ------------------------

TF = os.path.join(WORK, "tree-f")
KF = tok.encode(REPOS + "/phi")
now_f = epoch("2026-11-17T12:00:00+00:00")
n = 70
ages = [(3600, 2), (3 * 86400, 2), (10 * 86400, 2), (20 * 86400, 300)]
total_files = 0
for age, count in ages:
    for _ in range(count):
        n += 1
        mtime = now_f - age
        ts = datetime.fromtimestamp(mtime - 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        path = os.path.join(TF, KF, uid(n) + ".jsonl")
        put(path, *[rec(f"msg_f{n}_{i}", f"req_f{n}_{i}", ts, uid(n), out=1, cwd=REPOS + "/phi")
                    for i in range(300)])
        os.utime(path, (mtime, mtime))
        total_files += 1

h = Helper(TF, os.path.join(WORK, "state-f1"))
h.until(lambda m: m.get("event") == "progress" and m["ready"]["today"])
early = h.ask({"req": "projects", "period": "30d"})
ov = h.ask({"req": "overview"})
h.done()
full = summary(h)
eq("exit 0", h.close(), 0)
eq("too early: not ready, with progress", (early["ready"], early.get("needs"), "progress" in early), (False, "30d", True))
eq("too early overview: today shown, 30 days not", (ov["today"] is not None, ov["last30"], ov["ready"]),
   (True, None, False))
prog = [e for e in h.events if e["event"] == "progress"]
first = {p: next(i for i, e in enumerate(prog) if e["ready"][p]) for p in ("today", "7d", "14d", "30d", "all")}
check("periods become ready in turn", first["today"] < first["7d"] < first["14d"] < first["30d"] <= first["all"],
      str(first))
eq("files read at each readiness",
   [prog[first[p]]["files_read"] for p in ("today", "7d", "14d")], [2, 4, 6])
busiest = max(sum(1 for u in h.times if t <= u < t + 1) for t in h.times)
check("progress at most about ten a second", busiest <= 16, f"{busiest} events in one second")
eq("first run reads every file", (prog[-1]["files_total"], prog[-1]["files_read"]), (total_files, total_files))

SF = os.path.join(WORK, "state-f2")
h = Helper(TF, SF)
h.until(lambda m: m.get("event") == "progress" and m["files_read"] >= 10 and m["state"] == "reading")
h.p.send_signal(signal.SIGTERM)
rc = h.p.wait(timeout=30)
eq("SIGTERM mid-sync: exit 0", rc, 0)
con = sqlite3.connect(os.path.join(SF, "index.sqlite"))
eq("SIGTERM mid-sync: index intact", con.execute("PRAGMA integrity_check").fetchone()[0], "ok")
con.close()
h = Helper(TF, SF)
start = h.until(lambda m: m.get("event") == "progress")
check("after SIGTERM: some files left to read, not all", 0 < start["files_total"] < total_files,
      str(start["files_total"]))
h.done()
eq("after SIGTERM: the next run completes to the same totals", summary(h), full)
eq("exit 0", h.close(), 0)

# EOF straight after a request: the request is answered, exit 0.
h = Helper(TF, os.path.join(WORK, "state-f3"))
i = h.send({"req": "days"})
rc = h.close()
eq("EOF: exit 0", rc, 0)
eq("EOF: the request was answered", any(m.get("answer") == "days" and m.get("id") == i for m in h.seen), True)

print(f"{CHECKS[0] - len(FAILURES)}/{CHECKS[0]} checks passed")
sys.exit(1 if FAILURES else 0)
