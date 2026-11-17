"""Token helper for the Quickshell token panel.

Counts Claude Code's replies from its transcripts into an index of its own and
answers the panel's questions about them: output per local day, tokens per
model, per project and per session, and an estimate at API list prices.
Reports to its parent as JSON lines on stdout; takes requests as JSON lines on
stdin. Every time is integer epoch seconds (UTC); counts are tokens; money is
USD.

Usage: desk-tokens [--projects DIR] [--state DIR] [--prices FILE] [--now TIME]

--projects: the transcripts' root (default $CLAUDE_CONFIG_DIR/projects, else
    ~/.claude/projects). A missing root is not an error: the answers are empty.
--state: where index.sqlite lives (default $XDG_STATE_HOME/desk/tokens, else
    ~/.local/state/desk/tokens). Created 0700, the index 0600.
--prices: the price table (default the one built into the package).
--now: fixes the clock, as epoch seconds or ISO 8601 with a zone (also
    $DESK_TOKENS_NOW). For tests.

Days are calendar days in the process's local time zone (TZ, else the
system's). "today" is the local day holding now; "7d", "14d" and "30d" are
today and the 6, 13 or 29 local days before it. A day may be 23 or 25 hours
long. A window ends at the start of tomorrow.

What is read: only *.jsonl files at <key>/<session>.jsonl,
<key>/<session>/subagents/agent-*.jsonl and
<key>/<session>/subagents/workflows/<name>/agent-*.jsonl under the root. A
line is parsed only if its bytes contain "usage", and only an assistant
record's counters, model, timestamp, ids, sidechain flag, session and working
directory are kept. Nothing from a transcript is ever printed.

stdout, events:
  {"event": "progress", "state": "starting" | "reading" | "done",
      "files_read", "files_total", "bytes_read", "bytes_total",
      "ready": {"today", "7d", "14d", "30d", "all": bool},
      "skipped": {"bad_lines", "no_id", "synthetic"}, "unreadable", "now"}
      During a sync, at most every 0.1 s, at once when a period becomes
      complete, and once with "done". The totals count the files and bytes
      this sync reads. Files are read newest first, so the periods become
      complete in order; "all" only at "done".
  {"event": "bad-input"}  a stdin line that is not a JSON object
  {"event": "error", "kind": str}  a sync failed (the exception's class only)

stdout, answers (one per request, "id" echoed; every answer carries "now"
and "bounds": {"today", "tomorrow", "7d", "14d", "30d", "days": [14 day
starts, oldest first]}):
  Beside each token quantity an answer carries "cost": {"usd", "priced",
  "partial"}, the estimate at API list prices summed reply by reply: "priced"
  is false when there were replies and none had a price (then "usd" is 0.0),
  "partial" true when some had none. The 30-day and the project totals add
  "by_type": {type: USD}; "unpriced_models" lists the period's models with no
  price.
  A request whose period is not complete yet is answered
  {"answer", "id", "ready": false, "needs": period, "progress": {...}}; ask
  again once a progress event shows that period ready. "overview" is never
  refused: its sections are null until their period is complete.

stdin:
  {"req": "overview", "id"}
  {"req": "projects", "id", "period": "today" | "7d" | "30d"}
  {"req": "project", "id", "project": int, "period": "today" | "7d" | "30d"}
      needs the whole sync ("all")
  {"req": "days", "id"}  needs "14d"
  {"req": "refresh", "id"}  answered at once, then a new sync's events

On stdin EOF the running sync is finished and the process exits 0. On
SIGTERM the sync stops; what was not committed is rolled back, and the next
run reads it again.
"""

import argparse
import bisect
import hashlib
import json
import os
import re
import signal
import sqlite3
import sys
import threading
import time
from datetime import datetime, timedelta

PRICES = "@prices@"
SCHEMA = 2
# Gaps between a session's main-conversation replies count as active time
# only when shorter than this.
ACTIVE_GAP = 600
PROGRESS_EVERY = 0.1
COMMIT_EVERY = 0.5
COMMIT_BYTES = 64 << 20
PERIODS = ("today", "7d", "14d", "30d")
DAYS_BACK = {"today": 0, "7d": 6, "14d": 13, "30d": 29}
PAGE_PERIODS = ("today", "7d", "30d")
TYPES = ("input", "output", "cache_read", "cache_write_5m", "cache_write_1h")
# A window row: the reply's fields, then its total cost (None when unpriced).
TS, SESSION, MODEL, SUB, INPUT, OUTPUT, READ, W5, W1, USD = range(10)
RAW = "ts, session, model, sub, input, output, cache_read, cache_write_5m, cache_write_1h"
USD_COLS = tuple("usd_" + t for t in TYPES)
COLS = RAW + ", usd"

# Added to a schema-1 index in place (open_index), so these are the same
# statements the tables below end with. replies_window covers every column a
# window reads, so a window query never visits the table.
COST_COLUMNS = "".join(f"ALTER TABLE replies ADD COLUMN {c} REAL;\n" for c in USD_COLS + ("usd",)) + f"""
ALTER TABLE replies ADD COLUMN stale INTEGER NOT NULL DEFAULT 1;
CREATE INDEX replies_stale ON replies (stale) WHERE stale = 1;
DROP INDEX IF EXISTS replies_ts;
CREATE INDEX replies_window ON replies ({COLS}, {", ".join(USD_COLS)});
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""

# replies.usd_*: the reply's cost per type at the rates of the price table
# whose hash is meta's "prices" row, and usd their sum; all NULL when its
# model is unpriced. stale = 1 marks a reply whose counters changed since it
# was priced; no committed row is stale.
TABLES = """
CREATE TABLE files (path TEXT PRIMARY KEY, kind TEXT NOT NULL,
    inode INTEGER NOT NULL, read_to INTEGER NOT NULL);
CREATE TABLE projects (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL);
CREATE TABLE folds (id INTEGER PRIMARY KEY, cwd TEXT NOT NULL UNIQUE,
    project INTEGER REFERENCES projects (id), how TEXT,
    final INTEGER NOT NULL DEFAULT 0);
CREATE TABLE replies (key TEXT PRIMARY KEY, session TEXT NOT NULL,
    ts INTEGER NOT NULL, model TEXT NOT NULL, sub INTEGER NOT NULL,
    cwd INTEGER NOT NULL REFERENCES folds (id), input INTEGER NOT NULL,
    output INTEGER NOT NULL, cache_read INTEGER NOT NULL,
    cache_write_5m INTEGER NOT NULL, cache_write_1h INTEGER NOT NULL);
CREATE INDEX replies_session ON replies (session);
""" + COST_COLUMNS

# A reply seen again (a later streaming line, a resumed or forked session)
# merges by per-field maximum; which session it belongs to must not depend
# on the order files are read in, so the smallest session id wins.
UPSERT = """
INSERT INTO replies (key, session, ts, model, sub, cwd, input, output,
    cache_read, cache_write_5m, cache_write_1h)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (key) DO UPDATE SET
    session = min(session, excluded.session),
    cwd = CASE WHEN excluded.session < session THEN excluded.cwd ELSE cwd END,
    ts = min(ts, excluded.ts),
    model = max(model, excluded.model),
    sub = min(sub, excluded.sub),
    input = max(input, excluded.input),
    output = max(output, excluded.output),
    cache_read = max(cache_read, excluded.cache_read),
    cache_write_5m = max(cache_write_5m, excluded.cache_write_5m),
    cache_write_1h = max(cache_write_1h, excluded.cache_write_1h),
    stale = 1
"""


class Stopped(Exception):
    pass


class Terminated(Exception):
    pass


# Time


def parse_time(text):
    """Epoch seconds of an ISO 8601 time with a zone ("...Z" included), or
    None."""
    if not isinstance(text, str):
        return None
    try:
        t = datetime.fromisoformat(text)
    except ValueError:
        return None
    if t.tzinfo is None:
        return None
    return int(t.timestamp())


def local_midnight(day):
    return int(time.mktime((day.year, day.month, day.day, 0, 0, 0, 0, 0, -1)))


def bounds(now):
    """The local days around `now`: the first second of today, tomorrow, each
    period ("7d" is today and the 6 days before it) and the last 14 days
    ("days", oldest first)."""
    today = datetime.fromtimestamp(now).date()
    b = {"now": now, "tomorrow": local_midnight(today + timedelta(days=1)),
         "days": [local_midnight(today - timedelta(days=13 - i)) for i in range(14)]}
    for period, back in DAYS_BACK.items():
        b[period] = local_midnight(today - timedelta(days=back))
    return b


# Transcripts


def count(value):
    if isinstance(value, int) and not isinstance(value, bool) and value > 0:
        return value
    return 0


def parse_line(raw):
    """One transcript line (bytes, newline included) to a reply, or why it is
    not one: None (not a reply), "bad_lines" (not JSON, or no usable time),
    "no_id" (no message.id or requestId) or "synthetic".

    A reply: {"key": "<message.id>:<requestId>", "session", "ts", "model",
    "sidechain", "cwd"} and the five counters. With no cache_creation object,
    the whole cache_creation_input_tokens counts as 5-minute writes."""
    if b'"usage"' not in raw:
        return None
    try:
        obj = json.loads(raw)
    except ValueError:
        return "bad_lines"
    if not isinstance(obj, dict) or obj.get("type") != "assistant":
        return None
    msg = obj.get("message")
    usage = msg.get("usage") if isinstance(msg, dict) else None
    if not isinstance(usage, dict):
        return None
    model = msg.get("model")
    if model == "<synthetic>":
        return "synthetic"
    mid, rid = msg.get("id"), obj.get("requestId")
    if not (isinstance(mid, str) and mid and isinstance(rid, str) and rid):
        return "no_id"
    ts = parse_time(obj.get("timestamp"))
    if ts is None:
        return "bad_lines"
    parts = usage.get("cache_creation")
    if isinstance(parts, dict):
        w5 = count(parts.get("ephemeral_5m_input_tokens"))
        w1 = count(parts.get("ephemeral_1h_input_tokens"))
    else:
        w5, w1 = count(usage.get("cache_creation_input_tokens")), 0
    session, cwd = obj.get("sessionId"), obj.get("cwd")
    return {
        "key": mid + ":" + rid,
        "session": session if isinstance(session, str) and session else None,
        "ts": ts,
        "model": model if isinstance(model, str) and model else "unknown",
        "sidechain": obj.get("isSidechain") is True,
        "cwd": cwd if isinstance(cwd, str) else "",
        "input": count(usage.get("input_tokens")),
        "output": count(usage.get("output_tokens")),
        "cache_read": count(usage.get("cache_read_input_tokens")),
        "cache_write_5m": w5,
        "cache_write_1h": w1,
    }


def subdirs(path):
    try:
        with os.scandir(path) as it:
            return [e for e in it if e.is_dir(follow_symlinks=False)]
    except OSError:
        return []


def jsonl_files(path, agents=False):
    try:
        with os.scandir(path) as it:
            return [e.path for e in it
                    if e.name.endswith(".jsonl")
                    and (not agents or e.name.startswith("agent-"))
                    and e.is_file(follow_symlinks=False)]
    except OSError:
        return []


def transcript_files(root):
    """Every transcript under root as (path, kind), kind "main", "sub" or
    "workflow". Nothing else under root is listed: not .meta.json, not a
    workflow's journal (<name>/<name>.jsonl, no agent- prefix), not
    tool-results or memory."""
    found = []
    for key in subdirs(root):
        found += [(p, "main") for p in jsonl_files(key.path)]
        for session in subdirs(key.path):
            sub = os.path.join(session.path, "subagents")
            found += [(p, "sub") for p in jsonl_files(sub, agents=True)]
            for flow in subdirs(os.path.join(sub, "workflows")):
                found += [(p, "workflow") for p in jsonl_files(flow.path, agents=True)]
    return found


def session_of_path(path, kind):
    """The session a transcript belongs to by its place in the tree: the
    file's name for a main transcript, the directory above subagents/ for a
    sub-agent's."""
    if kind == "main":
        return os.path.basename(path)[:-len(".jsonl")]
    parts = path.split(os.sep)
    return parts[len(parts) - 2 - parts[::-1].index("subagents")]


def plan_reads(entries, stored):
    """Which transcripts to read and from which byte, newest first.

    entries: [(path, kind, inode, size, mtime)]; stored: {path: (inode,
    read_to)} from the index. Returns [(path, kind, inode, size, mtime,
    start)]. A file is skipped when its inode is the stored one and its size
    is the stored offset; read from 0 when new, replaced (another inode) or
    shorter than the offset; otherwise from the offset."""
    plan = []
    for path, kind, inode, size, mtime in entries:
        old = stored.get(path)
        if old is None or old[0] != inode or size < old[1]:
            start = 0
        elif size == old[1]:
            continue
        else:
            start = old[1]
        plan.append((path, kind, inode, size, mtime, start))
    plan.sort(key=lambda e: (-e[4], e[0]))
    return plan


def period_cuts(plan, b):
    """For each period, how many files at the head of the plan must be read
    before it is complete: those last written at or after its first second.
    A file last written before a period began cannot hold its replies."""
    return {p: sum(1 for e in plan if e[4] >= b[p]) for p in PERIODS}


# Folding: a working directory to its project


TEMP = re.compile(r"/tmp/tmp\.[^/]+(/|$)")
SCRATCH = re.compile(r"/tmp/claude-\d+/([^/]+)")
CLAUDE_WORKTREES = "/.claude/worktrees/"


def encode(path):
    """A path as Claude Code names its project directories: every character
    that is not an ASCII letter or digit becomes "-"."""
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def gitdir_of(gitfile):
    try:
        with open(gitfile, "rb") as f:
            first = f.read(4096).split(b"\n", 1)[0].decode()
    except (OSError, UnicodeDecodeError):
        return None
    if not first.startswith("gitdir:"):
        return None
    target = first[len("gitdir:"):].strip()
    return os.path.normpath(os.path.join(os.path.dirname(gitfile), target))


def git_root(path):
    """The project of an existing directory by its nearest .git: a .git
    directory's checkout, the main checkout of a worktree whose .git file
    points into <repo>/.git/worktrees/, or the directory of any other .git
    file (a submodule). None with no .git up to /."""
    d = path
    while True:
        g = os.path.join(d, ".git")
        if os.path.isdir(g):
            return d
        if os.path.isfile(g):
            target = gitdir_of(g) or ""
            i = target.rfind("/.git/worktrees/")
            return target[:i] if i > 0 else d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def by_name(encoded, checkouts):
    """The checkout whose encoded path is the longest prefix of `encoded`
    ending where a "-" follows (or the whole of it), or None."""
    best, length = None, -1
    for c in checkouts:
        e = encode(c)
        if (encoded == e or encoded.startswith(e + "-")) and len(e) > length:
            best, length = c, len(e)
    return best


def name_of(path):
    return os.path.basename(path.rstrip("/")) or path


def fold_cwd(cwd, checkouts):
    """A working directory to its project: (key, name, how, final).

    checkouts are the repositories known from directories folded by git. In
    order: /tmp/tmp.* is "temporary directories"; a /tmp/claude-<uid>/<key>/
    scratch path folds by name on <key>; an existing directory by git, else
    it is its own project; a gone <repo>/.claude/worktrees/<name> folds as
    <repo>; any other gone directory by name; what matches nothing is its own
    project. A fold read from the file system ("temp", "git", "alone") is
    final; one made by name is tried again later, as checkouts become known.
    """
    if not cwd:
        return ("", "unknown directory", "none", True)
    if TEMP.match(cwd):
        return ("/tmp/tmp.*", "temporary directories", "temp", True)
    m = SCRATCH.match(cwd)
    if m:
        repo = by_name(m.group(1), checkouts)
        if repo:
            return (repo, name_of(repo), "scratch", False)
        return (m.group(1), m.group(1), "scratch", False)
    if os.path.isdir(cwd):
        root = git_root(cwd)
        if root:
            return (root, name_of(root), "git", True)
        return (cwd, name_of(cwd), "alone", True)
    i = cwd.find(CLAUDE_WORKTREES)
    if i > 0:
        key, name, _, _ = fold_cwd(cwd[:i], checkouts)
        return (key, name, "worktree", False)
    repo = by_name(encode(cwd), checkouts)
    if repo:
        return (repo, name_of(repo), "name", False)
    return (cwd, name_of(cwd), "gone", False)


def fold_pass(conn):
    """Folds every working directory not folded for good yet. Run inside the
    transaction that added them, so a committed reply always has a project."""
    rows = conn.execute("SELECT id, cwd FROM folds WHERE final = 0").fetchall()
    if not rows:
        return
    checkouts = {k for (k,) in conn.execute(
        "SELECT DISTINCT p.key FROM folds f JOIN projects p ON p.id = f.project WHERE f.how = 'git'")}
    folded = {i: fold_cwd(cwd, checkouts) for i, cwd in rows}
    found = {f[0] for f in folded.values() if f[2] == "git"} - checkouts
    if found:
        checkouts |= found
        folded = {i: fold_cwd(cwd, checkouts) for i, cwd in rows}
    for i, (key, name, how, final) in folded.items():
        conn.execute("INSERT OR IGNORE INTO projects (key, name) VALUES (?, ?)", (key, name))
        pid = conn.execute("SELECT id FROM projects WHERE key = ?", (key,)).fetchone()[0]
        conn.execute("UPDATE folds SET project = ?, how = ?, final = ? WHERE id = ?",
                     (pid, how, int(final), i))


# Index


def open_index(state):
    """The index at <state>/index.sqlite. A schema-1 index (no costs) gains the
    cost columns in place, every reply marked for pricing; any other version
    but SCHEMA is rebuilt from scratch. Returns (connection, path)."""
    os.makedirs(state, mode=0o700, exist_ok=True)
    os.chmod(state, 0o700)
    path = os.path.join(state, "index.sqlite")
    conn = sqlite3.connect(path, isolation_level=None)
    try:
        version = conn.execute("PRAGMA user_version").fetchone()[0]
    except sqlite3.DatabaseError:
        version = None
    if version == 1:
        conn.executescript(f"BEGIN;\n{COST_COLUMNS}PRAGMA user_version = {SCHEMA};\nCOMMIT;")
    elif version != SCHEMA:
        conn.close()
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(path + suffix)
            except FileNotFoundError:
                pass
        conn = sqlite3.connect(path, isolation_level=None)
        # user_version last: a schema cut short stays at 0 and is rebuilt.
        conn.executescript(TABLES + f"PRAGMA user_version = {SCHEMA};")
    conn.execute("PRAGMA journal_mode = WAL")
    os.chmod(path, 0o600)
    return conn, path


def connect(path):
    conn = sqlite3.connect(path, isolation_level=None)
    conn.execute("PRAGMA synchronous = NORMAL")
    return conn


# Queries and the pure aggregates behind the answers


def window(conn, start, end, by_type=False):
    """The replies from start to end as rows indexed by TS ... USD; with
    by_type, each row ends with its cost per type in TYPES order."""
    cols = COLS + ", " + ", ".join(USD_COLS) if by_type else COLS
    return conn.execute(f"SELECT {cols} FROM replies WHERE ts >= ? AND ts < ?", (start, end)).fetchall()


def session_projects(conn):
    """{session: project id}: the project of the working directory of the
    session's first main-conversation reply, or of its first reply when it
    has none."""
    return {s: p for s, p, _ in conn.execute(
        "SELECT r.session, f.project, min(r.sub * 10000000000000 + r.ts)"
        " FROM replies r JOIN folds f ON f.id = r.cwd GROUP BY r.session")}


def project_names(conn):
    return dict(conn.execute("SELECT id, name FROM projects"))


def model_sums(rows):
    """{model: {type: tokens}} over rows."""
    sums = {}
    for r in rows:
        s = sums.get(r[MODEL])
        if s is None:
            s = sums[r[MODEL]] = dict.fromkeys(TYPES, 0)
        s["input"] += r[INPUT]
        s["output"] += r[OUTPUT]
        s["cache_read"] += r[READ]
        s["cache_write_5m"] += r[W5]
        s["cache_write_1h"] += r[W1]
    return sums


def model_list(outputs):
    """[{"model", "output"}] by output, then name; models with no output are
    left out."""
    return [{"model": m, "output": o}
            for m, o in sorted(outputs.items(), key=lambda i: (-i[1], i[0])) if o > 0]


DATED = re.compile(r"-\d{8}$")


def price_for(model, table):
    """The table's entry for a model: its own id, or the id it carries with a
    -YYYYMMDD date suffix. None when unpriced."""
    p = table.get(model)
    if p is None and DATED.search(model):
        p = table.get(DATED.sub("", model))
    return p


def reply_costs(row, p):
    """USD per type for one reply, in TYPES order, at the entry p's
    per-million rates. A tier ("above") applies to the whole reply when its
    prompt (fresh input, cache reads and both cache writes) is longer than
    the tier's prompt_tokens."""
    prompt = row[INPUT] + row[READ] + row[W5] + row[W1]
    tier = p.get("above")
    if tier is not None and prompt > tier["prompt_tokens"]:
        p = tier
    return (row[INPUT] * p["input"] / 1e6, row[OUTPUT] * p["output"] / 1e6, row[READ] * p["cache_read"] / 1e6,
            row[W5] * p["cache_write_5m"] / 1e6, row[W1] * p["cache_write_1h"] / 1e6)


def price_hash(table):
    """A digest of a loaded price table's rates: what the stored costs were
    computed with."""
    return hashlib.sha256(json.dumps(table, sort_keys=True).encode()).hexdigest()


def price_stale(conn, table):
    """Prices every reply marked stale, reply by reply; an unpriced model's
    replies get NULL costs. Runs inside the caller's transaction."""
    entries = {}
    done = []
    for row in conn.execute(f"SELECT {RAW}, rowid FROM replies WHERE stale = 1"):
        model = row[MODEL]
        if model not in entries:
            entries[model] = price_for(model, table)
        p = entries[model]
        costs = reply_costs(row, p) if p is not None else None
        done.append((*(costs or (None,) * 5), sum(costs) if costs else None, row[-1]))
    conn.executemany("UPDATE replies SET " + ", ".join(c + " = ?" for c in USD_COLS)
                     + ", usd = ?, stale = 0 WHERE rowid = ?", done)


def follow_prices(conn, table):
    """Makes the stored costs those of `table`: when its hash is not the one
    they were computed with, every reply is priced again, in one transaction
    and without reading a transcript."""
    digest = price_hash(table)
    conn.execute("BEGIN IMMEDIATE")
    old = conn.execute("SELECT value FROM meta WHERE key = 'prices'").fetchone()
    if old is None or old[0] != digest:
        conn.execute("UPDATE replies SET stale = 1")
        conn.execute("INSERT INTO meta (key, value) VALUES ('prices', ?)"
                     " ON CONFLICT (key) DO UPDATE SET value = excluded.value", (digest,))
    price_stale(conn, table)
    conn.execute("COMMIT")


class Cost:
    """The estimate of a set of window rows at API list prices."""

    __slots__ = ("usd", "priced", "unpriced", "models")

    def __init__(self, rows=()):
        self.usd, self.priced, self.unpriced, self.models = 0.0, 0, 0, set()
        for r in rows:
            self.add(r)

    def add(self, r):
        if r[USD] is None:
            self.unpriced += 1
            self.models.add(r[MODEL])
        else:
            self.priced += 1
            self.usd += r[USD]

    def obj(self):
        return cost_obj(self.usd, self.priced, self.unpriced)


def cost_obj(usd, priced, unpriced):
    """{"usd", "priced", "partial"} from the sum over priced replies and the
    counts of priced and unpriced replies. No replies at all is priced."""
    return {"usd": usd, "priced": priced > 0 or unpriced == 0, "partial": priced > 0 and unpriced > 0}


def type_costs(rows):
    """{type: USD} over the priced rows of a window fetched with by_type."""
    cols = list(zip(*rows)) or [()] * (USD + 1 + len(TYPES))
    # filter(None, …) drops the unpriced rows' None (and zeros, which add nothing).
    return {t: float(sum(filter(None, cols[USD + 1 + i]))) for i, t in enumerate(TYPES)}


def type_sums(rows):
    """{type: tokens} over rows."""
    cols = list(zip(*rows)) or [()] * (W1 + 1)
    return {t: sum(cols[INPUT + i]) for i, t in enumerate(TYPES)}


def daily(rows, starts, end):
    """[{"start", "output", "cost"}] per day; starts are the days' first
    seconds, oldest first, and end the last day's end."""
    out = [0] * len(starts)
    costs = [Cost() for _ in starts]
    for r in rows:
        if starts[0] <= r[TS] < end:
            i = bisect.bisect_right(starts, r[TS]) - 1
            out[i] += r[OUTPUT]
            costs[i].add(r)
    return [{"start": s, "output": o, "cost": c.obj()} for s, o, c in zip(starts, out, costs)]


def peak(days):
    """The day with the most output (the oldest of equals), or None when every
    day is zero."""
    best = None
    for d in days:
        if d["output"] > 0 and (best is None or d["output"] > best["output"]):
            best = d
    return best


def active_seconds(times):
    """Sum of the gaps shorter than ACTIVE_GAP between sorted times."""
    return sum(b - a for a, b in zip(times, times[1:]) if b - a < ACTIVE_GAP)


def by_project(rows, projects):
    acc = {}
    for r in rows:
        pid = projects.get(r[SESSION])
        a = acc.get(pid)
        if a is None:
            a = acc[pid] = {"output": 0, "subagent_output": 0, "models": {}, "sessions": set(), "last_reply": 0,
                            "cost": Cost()}
        a["output"] += r[OUTPUT]
        a["cost"].add(r)
        if r[SUB]:
            a["subagent_output"] += r[OUTPUT]
        a["models"][r[MODEL]] = a["models"].get(r[MODEL], 0) + r[OUTPUT]
        a["sessions"].add(r[SESSION])
        a["last_reply"] = max(a["last_reply"], r[TS])
    return acc


def project_rows(rows, projects, names):
    """Every project with output in rows, by output (then name)."""
    out = []
    for pid, a in by_project(rows, projects).items():
        if a["output"] <= 0:
            continue
        out.append({"id": pid, "name": names.get(pid, ""), "output": a["output"],
                    "subagent_output": a["subagent_output"], "models": model_list(a["models"]),
                    "sessions": len(a["sessions"]), "last_reply": a["last_reply"], "cost": a["cost"].obj()})
    out.sort(key=lambda p: (-p["output"], p["name"], p["id"]))
    return out


def last30(rows, prices):
    sums = model_sums(rows)
    totals = dict.fromkeys(TYPES, 0)
    for s in sums.values():
        for t in TYPES:
            totals[t] += s[t]
    seen = totals["cache_read"] + totals["cache_write_5m"] + totals["cache_write_1h"] + totals["input"]
    sub = sum(r[OUTPUT] for r in rows if r[SUB])
    cost, per_model = Cost(), {}
    for r in rows:
        cost.add(r)
        c = per_model.get(r[MODEL])
        if c is None:
            c = per_model[r[MODEL]] = Cost()
        c.add(r)
    models = [dict(model=m, tokens=sum(s.values()), **s, cost=per_model[m].obj()) for m, s in sums.items()]
    models.sort(key=lambda m: (-m["tokens"], m["model"]))
    return {"models": models, "totals": totals,
            "cache_hit": totals["cache_read"] / seen if seen else None,
            "subagent_output": sub,
            "subagent_share": sub / totals["output"] if totals["output"] else None,
            "cost": dict(cost.obj(), by_type=type_costs(rows)),
            "cost_usd": cost.usd, "unpriced_models": sorted(cost.models),
            "prices_checked": prices["checked"]}


def overview(conn, b, ready, prices):
    out = {"today": None, "last14": None, "last30": None, "top7": None}
    end = b["tomorrow"]
    if ready["today"]:
        rows = window(conn, b["today"], end)
        out["today"] = {"output": sum(r[OUTPUT] for r in rows),
                        "sessions": len({r[SESSION] for r in rows}),
                        "cache_read": sum(r[READ] for r in rows),
                        "cost": Cost(rows).obj()}
    if ready["14d"]:
        days = daily(window(conn, b["14d"], end), b["days"], end)
        out["last14"] = {"days": days, "peak": peak(days)}
    if ready["30d"]:
        out["last30"] = last30(window(conn, b["30d"], end, by_type=True), prices)
    if ready["7d"]:
        rows = window(conn, b["7d"], end)
        ranked = project_rows(rows, session_projects(conn), project_names(conn))
        out["top7"] = {"projects": [{"id": p["id"], "name": p["name"], "output": p["output"], "cost": p["cost"]}
                                    for p in ranked[:4]],
                       "more": max(0, len(ranked) - 4),
                       "output": sum(p["output"] for p in ranked),
                       "cost": Cost(rows).obj()}
    return out


def projects_page(conn, b, period):
    rows = window(conn, b[period], b["tomorrow"])
    cost = Cost(rows)
    return {"period": period, "output": sum(r[OUTPUT] for r in rows), "cost": cost.obj(),
            "unpriced_models": sorted(cost.models),
            "projects": project_rows(rows, session_projects(conn), project_names(conn))}


def project_detail(conn, b, pid, period):
    names = project_names(conn)
    if pid not in names:
        return {"error": "unknown project"}
    sp = session_projects(conn)
    mine = {s for s, p in sp.items() if p == pid}
    end = b["tomorrow"]
    rows = window(conn, b[period], end, by_type=True)
    own = [r for r in rows if r[SESSION] in mine]
    every = sum(r[OUTPUT] for r in rows)
    output = sum(r[OUTPUT] for r in own)
    outputs, costs = {}, {}
    for r in own:
        outputs[r[MODEL]] = outputs.get(r[MODEL], 0) + r[OUTPUT]
        c = costs.get(r[MODEL])
        if c is None:
            c = costs[r[MODEL]] = Cost()
        c.add(r)
    models = model_list(outputs)
    for m in models:
        m["cost"] = costs[m["model"]].obj()
    cost = Cost(own)
    totals = {"output": output, "share": output / every if every else None,
              "sessions": len({r[SESSION] for r in own}),
              "subagent_output": sum(r[OUTPUT] for r in own if r[SUB]),
              "models": models, "tokens": type_sums(own),
              "cost": dict(cost.obj(), by_type=type_costs(own))}
    own14 = [r for r in window(conn, b["14d"], end) if r[SESSION] in mine]
    days = daily(own14, b["days"], end)
    stats = [s for s in conn.execute(
        "SELECT session, min(ts), max(ts), sum(output), total(usd), count(usd), count(*) - count(usd)"
        " FROM replies GROUP BY session") if s[0] in mine]
    stats.sort(key=lambda s: (-s[2], s[0]))
    sessions = []
    for session, first, last, out, usd, priced, unpriced in stats[:6]:
        times = [t for (t,) in conn.execute(
            "SELECT ts FROM replies WHERE session = ? AND sub = 0 ORDER BY ts", (session,))]
        sessions.append({"id": session, "first_reply": first, "last_reply": last, "output": out,
                         "replies": len(times), "active_seconds": active_seconds(times),
                         "cost": cost_obj(usd, priced, unpriced)})
    return {"project": {"id": pid, "name": names[pid]}, "period": period, "totals": totals,
            "unpriced_models": sorted(cost.models),
            "last14": {"days": days, "peak": peak(days)}, "sessions": sessions}


def days_page(conn, b):
    end = b["tomorrow"]
    rows = window(conn, b["14d"], end)
    sp, names = session_projects(conn), project_names(conn)
    starts = b["days"]
    days = [{"output": 0, "sessions": set(), "projects": {}, "cost": Cost()} for _ in starts]
    for r in rows:
        if not starts[0] <= r[TS] < end:
            continue
        d = days[bisect.bisect_right(starts, r[TS]) - 1]
        d["output"] += r[OUTPUT]
        d["cost"].add(r)
        d["sessions"].add(r[SESSION])
        pid = sp.get(r[SESSION])
        d["projects"][pid] = d["projects"].get(pid, 0) + r[OUTPUT]
    out = []
    for start, d in reversed(list(zip(starts, days))):
        ranked = sorted(((o, names.get(p, ""), p) for p, o in d["projects"].items() if o > 0),
                        key=lambda x: (-x[0], x[1], x[2]))
        top = {"id": ranked[0][2], "name": ranked[0][1], "output": ranked[0][0]} if ranked else None
        out.append({"start": start, "output": d["output"], "sessions": len(d["sessions"]), "top": top,
                    "cost": d["cost"].obj()})
    return {"days": out}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0


def rates(p):
    if isinstance(p, dict) and all(number(p.get(t)) for t in TYPES):
        return {t: float(p[t]) for t in TYPES}
    return None


def load_prices(path):
    """{"source", "checked", "models": {model: {type: USD per million,
    "above"?: {"prompt_tokens", type: ...}}}}. A model whose entry, or whose
    tier, lacks a number for any type is left out (unpriced); an unreadable
    file prices nothing."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    models = {}
    table = data.get("models")
    for name, p in (table.items() if isinstance(table, dict) else ()):
        base = rates(p)
        if base is None:
            continue
        if "above" in p:
            tier = rates(p["above"])
            if tier is None or not number(p["above"].get("prompt_tokens")):
                continue
            base["above"] = dict(tier, prompt_tokens=p["above"]["prompt_tokens"])
        models[name] = base
    text = {k: data.get(k) if isinstance(data.get(k), str) else None for k in ("source", "checked")}
    return {"source": text["source"], "checked": text["checked"], "models": models}


# The process


class Out:
    def __init__(self):
        self.lock = threading.Lock()

    def send(self, obj):
        line = json.dumps(obj, separators=(",", ":")) + "\n"
        with self.lock:
            try:
                sys.stdout.write(line)
                sys.stdout.flush()
            except OSError:
                pass


class Syncer(threading.Thread):
    """Reads the transcripts into the index, one sync at a time, on its own
    connection. Commits at least every COMMIT_EVERY seconds or COMMIT_BYTES,
    and before a period is reported complete."""

    def __init__(self, root, db, clock, out, table):
        super().__init__(name="sync")
        self.root, self.db, self.clock, self.out, self.table = root, db, clock, out, table
        self.lock = threading.Lock()
        self.cv = threading.Condition()
        self.wanted = False
        self.closing = False
        self.stopping = threading.Event()
        self.progress = self.fresh_progress()

    @staticmethod
    def fresh_progress():
        return {"state": "starting", "files_read": 0, "files_total": 0, "bytes_read": 0, "bytes_total": 0,
                "ready": {p: False for p in PERIODS + ("all",)},
                "skipped": {"bad_lines": 0, "no_id": 0, "synthetic": 0}, "unreadable": 0}

    def snapshot(self):
        with self.lock:
            return json.loads(json.dumps(self.progress))

    def emit(self):
        self.out.send(dict(event="progress", now=self.clock(), **self.snapshot()))

    def request(self):
        with self.cv:
            self.wanted = True
            self.cv.notify()

    def finish(self):
        with self.cv:
            self.closing = True
            self.cv.notify()

    def stop(self):
        self.stopping.set()
        self.finish()

    def run(self):
        conn = connect(self.db)
        try:
            while True:
                with self.cv:
                    while not self.wanted and not self.closing:
                        self.cv.wait()
                    if not self.wanted or self.stopping.is_set():
                        return
                    self.wanted = False
                try:
                    self.sync(conn)
                except Stopped:
                    conn.rollback()
                    return
                except Exception as e:
                    if conn.in_transaction:
                        conn.rollback()
                    self.out.send({"event": "error", "kind": type(e).__name__})
        finally:
            conn.close()

    def commit(self, conn):
        fold_pass(conn)
        price_stale(conn, self.table)
        conn.execute("COMMIT")

    def sync(self, conn):
        b = bounds(self.clock())
        entries = []
        for path, kind in transcript_files(self.root):
            try:
                st = os.stat(path)
            except OSError:
                continue
            entries.append((path, kind, st.st_ino, st.st_size, st.st_mtime))
        stored = {p: (i, r) for p, i, r in conn.execute("SELECT path, inode, read_to FROM files")}
        plan = plan_reads(entries, stored)
        cuts = period_cuts(plan, b)
        with self.lock:
            self.progress = self.fresh_progress()
            self.progress.update(state="reading", files_total=len(plan),
                                 bytes_total=sum(e[3] - e[5] for e in plan))
            for p in PERIODS:
                self.progress["ready"][p] = cuts[p] == 0
        self.emit()
        self.cwds = {}
        conn.execute("BEGIN")
        last_commit = last_emit = time.monotonic()
        pending = 0
        for i, (path, kind, inode, size, mtime, start) in enumerate(plan):
            if any(cuts[p] <= i and not self.progress["ready"][p] for p in PERIODS):
                self.commit(conn)
                with self.lock:
                    for p in PERIODS:
                        self.progress["ready"][p] = cuts[p] <= i
                self.emit()
                conn.execute("BEGIN")
                last_commit = last_emit = time.monotonic()
                pending = 0
            n = self.read_file(conn, path, kind, inode, start)
            pending += n
            with self.lock:
                self.progress["files_read"] += 1
                self.progress["bytes_read"] += n
            now = time.monotonic()
            if now - last_commit >= COMMIT_EVERY or pending >= COMMIT_BYTES:
                self.commit(conn)
                conn.execute("BEGIN")
                last_commit, pending = now, 0
            if now - last_emit >= PROGRESS_EVERY:
                self.emit()
                last_emit = now
        present = {e[0] for e in entries}
        # A vanished transcript keeps its replies: Claude Code deletes old
        # transcripts, and then the index holds the only count.
        conn.executemany("DELETE FROM files WHERE path = ?", [(p,) for p in stored if p not in present])
        self.commit(conn)
        with self.lock:
            self.progress["state"] = "done"
            for p in self.progress["ready"]:
                self.progress["ready"][p] = True
        self.emit()

    def cwd_id(self, conn, cwd):
        i = self.cwds.get(cwd)
        if i is None:
            conn.execute("INSERT OR IGNORE INTO folds (cwd) VALUES (?)", (cwd,))
            i = self.cwds[cwd] = conn.execute("SELECT id FROM folds WHERE cwd = ?", (cwd,)).fetchone()[0]
        return i

    def read_file(self, conn, path, kind, inode, start):
        """Reads one transcript's complete lines from `start` into the index
        and records the offset after the last one. Returns the bytes read."""
        hint = session_of_path(path, kind)
        try:
            f = open(path, "rb")
        except OSError:
            with self.lock:
                self.progress["unreadable"] += 1
            return 0
        with f:
            actual = os.fstat(f.fileno()).st_ino
            if actual != inode:
                start = 0
            f.seek(start)
            pos = start
            for raw in f:
                if self.stopping.is_set():
                    raise Stopped()
                # A line still being written is left for the next sync.
                if not raw.endswith(b"\n"):
                    break
                pos += len(raw)
                r = parse_line(raw)
                if r is None:
                    continue
                if isinstance(r, str):
                    with self.lock:
                        self.progress["skipped"][r] += 1
                    continue
                conn.execute(UPSERT, (
                    r["key"], r["session"] or hint, r["ts"], r["model"], int(kind != "main" or r["sidechain"]),
                    self.cwd_id(conn, r["cwd"]), r["input"], r["output"], r["cache_read"],
                    r["cache_write_5m"], r["cache_write_1h"]))
        conn.execute(
            "INSERT INTO files (path, kind, inode, read_to) VALUES (?, ?, ?, ?)"
            " ON CONFLICT (path) DO UPDATE SET kind = excluded.kind, inode = excluded.inode,"
            " read_to = excluded.read_to", (path, kind, actual, pos))
        return pos - start


def needs(req):
    """The readiness a request needs: a period, "all", None for overview, or
    an error text."""
    kind = req.get("req")
    if kind == "overview":
        return None
    if kind == "days":
        return "14d"
    if kind in ("projects", "project"):
        if req.get("period") not in PAGE_PERIODS:
            return "error:bad period"
        if kind == "project":
            pid = req.get("project")
            if not isinstance(pid, int) or isinstance(pid, bool):
                return "error:bad project"
            return "all"
        return req["period"]
    return "error:unknown request"


def answer(conn, req, b, progress, prices):
    kind = req.get("req")
    base = {"answer": kind, "id": req.get("id"), "now": b["now"],
            "bounds": {k: b[k] for k in ("today", "tomorrow", "7d", "14d", "30d", "days")}}
    need = needs(req)
    if need is not None and need.startswith("error:"):
        return dict(base, error=need[len("error:"):])
    ready = progress["ready"]
    if kind == "overview":
        return dict(base, ready=ready["30d"], progress=progress, **overview(conn, b, ready, prices))
    if not ready[need]:
        return dict(base, ready=False, needs=need, progress=progress)
    if kind == "projects":
        return dict(base, ready=True, **projects_page(conn, b, req["period"]))
    if kind == "project":
        return dict(base, ready=True, **project_detail(conn, b, req["project"], req["period"]))
    return dict(base, ready=True, **days_page(conn, b))


def default_projects():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "projects")


def default_state():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "desk", "tokens")


def parse_now(text):
    try:
        return int(float(text))
    except ValueError:
        return parse_time(text)


def on_term(signum, frame):
    raise Terminated()


def main():
    ap = argparse.ArgumentParser(prog="desk-tokens")
    ap.add_argument("--projects", default=None)
    ap.add_argument("--state", default=None)
    ap.add_argument("--prices", default=PRICES)
    ap.add_argument("--now", default=os.environ.get("DESK_TOKENS_NOW"))
    args = ap.parse_args()
    os.umask(0o077)
    fixed = None
    if args.now:
        fixed = parse_now(args.now)
        if fixed is None:
            ap.error("--now: epoch seconds or ISO 8601 with a zone")

    def clock():
        return fixed if fixed is not None else int(time.time())

    prices = load_prices(args.prices)
    conn, db = open_index(args.state or default_state())
    follow_prices(conn, prices["models"])
    out = Out()
    syncer = Syncer(args.projects or default_projects(), db, clock, out, prices["models"])
    signal.signal(signal.SIGTERM, on_term)
    syncer.start()
    syncer.request()
    try:
        while True:
            line = sys.stdin.readline()
            if not line:
                break
            if not line.strip():
                continue
            try:
                req = json.loads(line)
            except ValueError:
                req = None
            if not isinstance(req, dict):
                out.send({"event": "bad-input"})
                continue
            if req.get("req") == "refresh":
                syncer.request()
                out.send({"answer": "refresh", "id": req.get("id"), "now": clock()})
                continue
            out.send(answer(conn, req, bounds(clock()), syncer.snapshot(), prices))
        syncer.finish()
        while syncer.is_alive():
            syncer.join(0.2)
    except Terminated:
        syncer.stop()
        syncer.join(5)
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
