"""Fleet helper for the Quickshell fleet panel.

Reads what each host of the SSH mesh runs and what its comin is doing, reads
the deploy pipeline from GitHub, and runs the few deploy actions the panel
offers. Reports to its parent as JSON lines on stdout; takes commands as JSON
lines on stdin. Times are UTC, ISO 8601 with milliseconds and "Z".

Usage: desk-fleet [--config FILE] [--gh PATH] [--tmux PATH] [--runtime DIR]
                  [--read-only]

--config: JSON {"repo": "owner/name", "hosts": [{"label", "alias", "darwin",
    "device", "local"}]}, this machine first. Generated from lib/ssh-mesh.nix.
--runtime: where the private tmux socket and the actions' exit codes live
    (default $XDG_RUNTIME_DIR/desk-fleet).
--read-only: probes as usual; switch, boot, mode and reboot are refused
    ("read-only") and run nothing. diff, ssh, attach, refresh, open and
    closed still work.

stdout:
  {"event": "hello", "repo": str, "read_only": bool,
      "hosts": [{"host", "alias", "darwin", "device", "local"}]}
  {"event": "round", "state": "started" | "done", "at": t}
      A probe of every host and GitHub; "done" when the last answer landed.
  {"event": "probing", "host": str}
  {"event": "host", ...}  One host's row, see host_row(). Sent after every
      probe of that host, and again for every host when GitHub's facts or a
      followed deploy change what the row says. Each of its "lines" has the
      full "text" and "first", the text's first line (an error can run to
      many lines; "first" is what a folded row shows).
  {"event": "github", "state": "ok", "master": sha, "deploy": sha,
      "ahead": int | null, "testing_branches": [str],
      "run": {"status", "conclusion", "url", "head_sha", "title",
              "created_at"} | null, "at": t}
  {"event": "github", "state": "error", "error": str, "at": t}
  {"event": "action", "id": N | null, "host": str?, "action": str?,
      "state": "started" | "running" | "ok" | "failed" | "refused",
      "reason": str?, "why": str?, "tail": [str]?, "exit": int?}
      "running" repeats while the output changes (at most every 2 s);
      "tail" is the last lines of the action's terminal.
  {"event": "message", "host": str, "kind": "sudo-password", "text": str}
  {"event": "bad-input", "line": str}, {"event": "exit"}

stdin (every command may carry "id": N, echoed in its "action" events):
  {"cmd": "refresh"}                      probe everything now
  {"cmd": "open"} / {"cmd": "closed"}     the panel is shown / hidden
  {"cmd": "switch", "host", "generation": uuid?}
  {"cmd": "boot", "host", "generation": uuid}
  {"cmd": "mode", "host", "value": "manual" | "boot" | "switch"}
  {"cmd": "reboot", "host"}
  {"cmd": "diff", "host"}                 opens in Ghostty at once
  {"cmd": "ssh", "host"}                  opens in Ghostty at once
  {"cmd": "attach", "host"}               the host's last action in Ghostty

A host command runs only if the host's latest row allows it
(row["actions"][cmd]["allowed"]); "switch" and "boot" must name the
generation the row holds, if any, so a newer one is never deployed unseen.
Switch, boot, mode and reboot run in a tmux session of their own, on a
private socket, with no window; "attach" shows it. A reboot of this machine
is a plain `systemctl reboot` (logind allows it from the active session);
another host's is `sudo -n systemctl reboot`, and if sudo wants a password,
`sudo systemctl reboot` in the same session, opened in Ghostty. Nothing but the commands
built in run_action() ever reaches a host. When stdin closes the process
exits; sessions still running are left to finish.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

CONFIG = "@config@"
TMUX = "@tmux@"
GH = "@gh@"

INTERVAL_CLOSED = 300
INTERVAL_OPEN = 60
FOLLOW_EVERY = 5
FOLLOW_IDLE = 20
FOLLOW_MIN = 10
FOLLOW_CAP = 30 * 60
PROBE_TIMEOUT = 30
GH_TIMEOUT = 30
TAIL_LINES = 15

# Read only. comin status comes last: when it hangs, the facts before it
# still arrive and the host reads "No comin".
PROBE = "; ".join([
    "echo @@booted", "readlink -f /run/booted-system 2>/dev/null",
    "echo @@current", "readlink -f /run/current-system 2>/dev/null",
    "echo @@bkernel", "readlink -f /run/booted-system/kernel 2>/dev/null",
    "echo @@ckernel", "readlink -f /run/current-system/kernel 2>/dev/null",
    "echo @@profile",
    "stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || stat -f %m /nix/var/nix/profiles/system 2>/dev/null",
    "echo @@efi",
    "ls /sys/firmware/efi/efivars 2>/dev/null | grep -E '^Loader(EntryDefault|EntryOneShot)-'",
    "echo @@mode", "comin-deploy mode 2>/dev/null",
    "echo @@status", "comin status --json 2>/dev/null",
    "echo", "echo @@end",
])

STORE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+(/[A-Za-z0-9+._?=-]+)*")
# A system: the only path that reaches a host's shell (the diff).
SYSTEM_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-[A-Za-z0-9+._?=-]+")
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

# id -> (label, colour, counted in the bar's number)
CHIPS = {
    "offline": ("Offline", "dim", False),
    "no-comin": ("No comin", "dim", False),
    "deploy-failed": ("Deploy failed", "red", True),
    "build-failed": ("Build failed", "red", True),
    "fetch-failed": ("Fetch failed", "red", True),
    "suspended": ("Suspended", "orange", False),
    "deploying": ("Deploying", "cyan", False),
    "building": ("Building", "cyan", False),
    "pending": ("Pending", "purple", True),
    "testing": ("Testing", "pink", False),
    "by-hand": ("By hand", "yellow", False),
    "behind": ("Behind", "orange", True),
    "reboot": ("Reboot", "orange", True),
    "reboot-kernel": ("Reboot (kernel)", "orange", True),
    "up-to-date": ("Up to date", "green", False),
}
HOST_ACTIONS = ("switch", "boot", "mode", "reboot", "diff", "ssh")

LOCK = threading.Lock()


# ---- the state model: pure, no I/O ----

def iso(dt):
    return dt.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_time(s):
    """A datetime from comin's RFC 3339 (nanoseconds) or GitHub's times, or None."""
    if not isinstance(s, str) or not s:
        return None
    m = re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)", s)
    if not m:
        return None
    frac = (m.group(2) or ".0")[:7]
    zone = "+00:00" if m.group(3) == "Z" else m.group(3)
    try:
        return datetime.fromisoformat(m.group(1) + frac + zone)
    except ValueError:
        return None


def ago(t, now):
    if t is None:
        return ""
    s = (now - t).total_seconds()
    if s < 0:
        return "just now"
    m = int(s // 60)
    if m < 1:
        return "just now"
    if m < 60:
        return f"{m}m ago"
    h = m // 60
    return f"{h}h ago" if h < 48 else f"{h // 24}d ago"


def lasted(t, now):
    if t is None:
        return ""
    s = max(0, int((now - t).total_seconds()))
    return f"{s}s" if s < 60 else f"{s // 60}m"


def short(sha):
    return sha[:7] if isinstance(sha, str) and sha else "?"


def store_path(s):
    s = (s or "").strip()
    return s if STORE_PATH.fullmatch(s) else None


def store_hash(path):
    return path[len("/nix/store/"):][:7] if path else "?"


def get(d, *keys):
    for k in keys:
        if not isinstance(d, dict):
            return None
        d = d.get(k)
    return d


def sections(text):
    out, key = {}, None
    for line in text.split("\n"):
        m = re.fullmatch(r"@@([a-z]+)", line.strip())
        if m:
            key = m.group(1)
            out[key] = []
        elif key:
            out[key].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}


def parse_probe(text):
    """The facts in a probe's output (PROBE). Anything missing or malformed is None."""
    s = sections(text)
    status = None
    if s.get("status"):
        try:
            status = json.loads(s["status"])
        except (ValueError, RecursionError):
            status = None
        if not isinstance(status, dict):
            status = None
    profile = s.get("profile", "")
    mode = s.get("mode", "")
    return {
        "complete": "end" in s,
        "booted": store_path(s.get("booted")),
        "current": store_path(s.get("current")),
        "booted_kernel": store_path(s.get("bkernel")),
        "current_kernel": store_path(s.get("ckernel")),
        "profile_time": int(profile) if profile.isdigit() else None,
        "efi_override": [x for x in s.get("efi", "").split("\n") if x],
        "mode": mode if mode in ("manual", "boot", "switch") else None,
        "status": status,
    }


def is_testing(gen):
    return get(gen, "selected_branch_is_testing") is True


def branch_of(gen):
    return get(gen, "selected_branch_name") or "?"


def gen_time(gen):
    return parse_time(get(gen, "build_ended_at")) or parse_time(get(gen, "eval_ended_at"))


def dep_time(dep):
    return parse_time(get(dep, "ended_at")) or parse_time(get(dep, "created_at"))


def newest(items, key):
    best, best_t = None, None
    for it in items:
        t = key(it)
        if best is None or (t is not None and (best_t is None or t > best_t)):
            best, best_t = it, t
    return best


def comin_facts(st, current):
    """Everything the row needs from `comin status --json`."""
    store = get(st, "store") or {}
    # comin invents "dummy" deployments (no generation uuid) for a booted or
    # switched system it did not deploy: those are not systems comin knows.
    deps = [d for d in (store.get("deployments") or [])
            if isinstance(d, dict) and get(d, "generation", "uuid")]
    gens = [g for g in (store.get("generations") or []) if isinstance(g, dict) and g.get("uuid")]
    building_gen = get(st, "builder", "generation")
    if isinstance(building_gen, dict) and building_gen.get("uuid") \
            and building_gen["uuid"] not in {g["uuid"] for g in gens}:
        gens.append(building_gen)
    done = [d for d in deps if d.get("status") == "done"]
    # What comin last made the boot default: its newest finished boot or
    # switch deployment (the same set comin keeps as boot entries).
    entries = [d for d in deps if d.get("operation") in ("boot", "switch")]
    staged = newest([d for d in entries if d.get("status") == "done"], dep_time)
    staged_at = dep_time(staged) if staged else None
    later_failed = [d for d in entries if d.get("status") == "failed" and staged_at
                    and dep_time(d) and dep_time(d) > staged_at]
    held_uuid = get(st, "deploy_confirmer", "submitted") or ""
    held = None
    if held_uuid:
        held = next((g for g in gens if g["uuid"] == held_uuid), None) or {"uuid": held_uuid}
    return {
        "deps": deps, "gens": gens, "done": done, "staged": staged,
        "failed_after_staged": bool(later_failed), "held": held,
        "deployment": get(st, "deployer", "deployment"),
        "builder_gen": building_gen if isinstance(building_gen, dict) else None,
        "evaluating": get(st, "builder", "is_evaluating") is True,
        "building": get(st, "builder", "is_building") is True,
        "deploying": get(st, "deployer", "is_deploying") is True,
        "queued": get(st, "deployer", "generation_to_deploy"),
        "queued_op": get(st, "deployer", "operation") or "",
        "suspended": any(x is True for x in (get(st, "is_suspended"), get(st, "deployer", "is_suspended"),
                                             get(st, "store", "deployer", "is_suspended"))),
        "suspend_reason": get(st, "store", "deployer", "suspend_reason") or "",
        "repo": get(st, "fetcher", "repository_status") or {},
    }


def runs_of(f, c, now):
    """Where the running system came from: the `runs` line."""
    cur = f["current"]
    if cur is None:
        return {"source": "unknown", "text": "unknown: /run/current-system unreadable"}
    dep = newest([d for d in c["done"] if get(d, "generation", "out_path") == cur], dep_time)
    same = [g for g in c["gens"] if g.get("out_path") == cur]
    if dep is not None:
        g = dep["generation"]
        testing = is_testing(g)
        commit, same_as = g.get("selected_commit_id"), None
        # A newer commit of the same branch that built this very system.
        newer = newest([x for x in same if is_testing(x) == testing and branch_of(x) == branch_of(g)
                        and gen_time(x) and dep_time(dep) and gen_time(x) > dep_time(dep)], gen_time)
        if newer is not None and newer.get("selected_commit_id") != commit:
            same_as, commit = commit, newer.get("selected_commit_id")
        op, at = dep.get("operation") or "?", dep_time(dep)
        if same_as:
            text = f"{short(commit)} · {branch_of(g)} · same system as {short(same_as)}, {op} {ago(at, now)}"
        else:
            text = f"{short(commit)} · {branch_of(g)} · {op} {ago(at, now)}"
        return {"source": "testing" if testing else "deploy", "commit": commit, "branch": branch_of(g),
                "operation": op, "at": iso(at) if at else None, "same_as": same_as, "by_hand": False,
                "out": cur, "text": text}
    gen = newest(same, gen_time)
    if gen is not None:
        testing = is_testing(gen)
        return {"source": "testing" if testing else "deploy-by-hand", "commit": gen.get("selected_commit_id"),
                "branch": branch_of(gen), "by_hand": True, "out": cur,
                "text": f"{short(gen.get('selected_commit_id'))} · {branch_of(gen)} · by hand"}
    return {"source": "hand", "store_hash": store_hash(cur), "out": cur,
            "text": f"built by hand · {store_hash(cur)} · not a comin system"}


def next_boot(f, c, darwin):
    """What boots next: {"known": True, "out", "dep"} or {"known": False, "why"}.

    Without root, the boot loader's default can't be read. It is set by
    whoever installed the boot loader last: comin's newest boot or switch
    deployment, or a hand nixos-rebuild switch/boot, which also moves the
    world-readable /nix/var/nix/profiles/system link (comin uses its own
    profile). So comin's staged system is the next boot only while that link
    is older than comin's deployment and no EFI variable overrides the
    default; anything else is unknown."""
    if darwin:
        return {"known": False, "why": "macOS has no boot"}
    staged = c["staged"]
    if staged is None:
        return {"known": False, "why": "comin has no boot entry"}
    if f["efi_override"]:
        return {"known": False, "why": "an EFI variable overrides the default entry"}
    if f["profile_time"] is None:
        return {"known": False, "why": "the system profile's time is unreadable"}
    at = dep_time(staged)
    if at is None or f["profile_time"] > at.timestamp():
        return {"known": False, "why": "the system was rebuilt by hand after comin's last boot entry"}
    if c["failed_after_staged"]:
        return {"known": False, "why": "a later comin deployment failed part way"}
    return {"known": True, "out": get(staged, "generation", "out_path"), "dep": staged}


def line(key, text, tone=None, **extra):
    return {"key": key, "text": text, "first": text.split("\n", 1)[0], "tone": tone, **extra}


def host_row(host, probe, github, now, following=False):
    """One host's row: runs, lines, chip, actions. `probe` is {"ok": bool,
    "text": str, "error": str?} (a finished probe), `github` the last "github"
    event with state "ok" or None, `following` whether a deploy started from
    the panel is being followed."""
    base = {"event": "host", "host": host["label"], "alias": host["alias"], "darwin": host["darwin"],
            "device": host["device"], "local": host["local"], "probed_at": iso(now)}

    def done(chip, runs=None, lines=(), actions=None, **extra):
        label, colour, counted = CHIPS[chip]
        acts = {a: {"allowed": False, "reason": "offline"} for a in HOST_ACTIONS}
        acts.update(actions or {})
        return {**base, "chip": {"id": chip, "label": label, "colour": colour}, "counts": counted,
                "runs": runs, "lines": list(lines), "actions": acts, **extra}

    if not probe["ok"]:
        return done("offline", lines=[line("ssh", probe.get("error") or "no answer")], online=False, mode=None)
    f = parse_probe(probe["text"])
    st = f["status"]
    if st is None:
        acts = {a: {"allowed": False, "reason": "comin does not answer"} for a in HOST_ACTIONS}
        acts["ssh"] = {"allowed": True}
        acts["reboot"] = ({"allowed": False, "reason": "macOS"} if host["darwin"] else {"allowed": True})
        return done("no-comin", lines=[line("comin", "no answer")], actions=acts, online=True, mode=f["mode"],
                    info={"current": f["current"], "booted": f["booted"]})

    c = comin_facts(st, f["current"])
    cur = f["current"]
    runs = runs_of(f, c, now)
    nb = next_boot(f, c, host["darwin"])
    lines = []

    held = c["held"]
    staged_out = get(c["staged"], "generation", "out_path")
    held_out = get(held, "out_path")
    pending = held is not None and held_out != staged_out
    if held is not None:
        hc = short(held.get("selected_commit_id"))
        if held_out and held_out == staged_out:
            text = f"{hc} · same system as staged · comin-deploy releases it"
        elif held_out and held_out == cur:
            text = f"{hc} · same system · S or B makes it comin's"
        elif held_out:
            text = f"{hc} · {branch_of(held)} · built {ago(gen_time(held), now)}"
        else:
            text = f"{held['uuid'][:8]} · not in comin's store list"
        lines.append(line("held", text, None, generation=held["uuid"], out=held_out,
                          testing=is_testing(held), same_as_running=bool(held_out and held_out == cur)))

    repo = c["repo"]
    fetched = repo.get("selected_commit_id") or ""
    bg = c["builder_gen"]
    busy_build = c["evaluating"] or c["building"]
    busy_deploy = c["deploying"] or c["queued"] is not None
    if busy_build:
        if c["building"] and bg:
            g, phase, since = bg, "building", parse_time(bg.get("build_started_at"))
        else:
            g = {"selected_commit_id": fetched, "selected_branch_name": repo.get("selected_branch_name"),
                 "selected_branch_is_testing": repo.get("selected_branch_is_testing")}
            since = parse_time(get(bg, "eval_started_at")) if get(bg, "selected_commit_id") == fetched else None
            phase = "evaluating"
        tone = "pink" if is_testing(g) else None
        lines.append(line("next", f"{short(g.get('selected_commit_id'))} · {branch_of(g)} · {phase} {lasted(since, now)}".rstrip(),
                          tone, testing=is_testing(g)))
    build_error = None
    if not busy_build and bg and (bg.get("eval_err") or bg.get("build_err")) \
            and bg.get("selected_commit_id") == fetched:
        build_error = bg.get("eval_err") or bg.get("build_err")
        lines.append(line("next", f"{short(fetched)} · {build_error}", "red"))
    if busy_deploy:
        if c["deploying"]:
            d = c["deployment"] or {}
            g, op = d.get("generation") or {}, d.get("operation") or d.get("operation_submitted") or "?"
            lines.append(line("next", f"{short(g.get('selected_commit_id'))} · activating ({op})"))
        else:
            g = c["queued"] or {}
            lines.append(line("next", f"{short(g.get('selected_commit_id'))} · queued ({c['queued_op'] or '?'})"))

    dep = c["deployment"] or {}
    dep_out = get(dep, "generation", "out_path")
    deploy_failed = dep.get("status") == "failed" and bool(get(dep, "generation", "uuid")) and dep_out != cur
    if deploy_failed:
        lines.append(line("failed", f"{short(get(dep, 'generation', 'selected_commit_id'))} · {dep.get('error_msg') or 'failed'}", "red"))

    fetch_errors = []
    for r in repo.get("remotes") or []:
        if isinstance(r, dict) and r.get("fetch_error_msg"):
            fetch_errors.append(f"{r.get('name') or '?'}: {r['fetch_error_msg']}")
    if repo.get("error_msg"):
        fetch_errors.append(repo["error_msg"])
    for e in fetch_errors:
        lines.append(line("fetch", e, "red"))

    kernel_changed = (not host["darwin"] and f["booted_kernel"] is not None and f["current_kernel"] is not None
                      and f["booted_kernel"] != f["current_kernel"])
    reboot_staged = False
    if not host["darwin"]:
        if not nb["known"]:
            lines.append(line("boot", "unknown", None, why=nb["why"]))
        elif nb["out"] != cur:
            reboot_staged = True
            g = nb["dep"]["generation"]
            tail = "reboot leaves testing" if runs["source"] == "testing" else \
                f"staged {ago(dep_time(nb['dep']), now)} · reboot to run it"
            lines.append(line("boot", f"{short(g.get('selected_commit_id'))} · {branch_of(g)} · {tail}", None, out=nb["out"]))
        elif kernel_changed:
            lines.append(line("boot", "same system · new kernel"))

    testing_info = []
    gh_testing = set(github.get("testing_branches") or []) if github else None
    for r in repo.get("remotes") or []:
        t = get(r, "testing") or {}
        msg, name = t.get("error_msg") or "", t.get("name") or ""
        if not msg or "doesn't exist" in msg:
            continue
        testing_info.append(f"{name}: {msg}")
        if gh_testing is not None and name in gh_testing:
            why = "not on top of deploy" if "is not on top of" in msg else msg
            lines.append(line("test", f"{name} ignored: {why}", "orange"))

    if c["suspended"]:
        lines.append(line("comin", "suspended · resume it over ssh (T)"))

    behind, behind_why = None, None
    idle = not busy_build and not busy_deploy and not following
    if runs["source"] in ("deploy", "deploy-by-hand") and idle and github:
        want = github.get("deploy") or ""
        comin_main = repo.get("main_commit_id") or ""
        last_fetch = newest([parse_time(r.get("fetched_at")) for r in repo.get("remotes") or [] if isinstance(r, dict)],
                            lambda t: t)
        if want and comin_main != want:
            behind, behind_why = True, "not-fetched"
            lines.append(line("comin", f"has not fetched {short(want)} yet · last fetch {ago(last_fetch, now) or 'unknown'}"))
        elif want:
            g = newest([x for x in c["gens"] if x.get("selected_commit_id") == want and not is_testing(x)], gen_time)
            if g is None or g.get("build_status") != "built" or not g.get("out_path"):
                behind = None
            elif g["out_path"] == cur:
                behind = False
            elif held is None and staged_out in (None, cur):
                behind, behind_why = True, "different-system"
                lines.append(line("comin", f"built {short(want)}: a different system, neither held nor staged"))
            else:
                behind = False

    if runs["source"] == "hand" and held is None:
        last = newest(c["done"], dep_time)
        if last is not None:
            g = last["generation"]
            lines.append(line("comin", f"{short(g.get('selected_commit_id'))} · {branch_of(g)} · last deployed {ago(dep_time(last), now)}"))

    if not f["complete"]:
        lines.append(line("comin", "probe output was cut short"))

    if deploy_failed:
        chip = "deploy-failed"
    elif build_error:
        chip = "build-failed"
    elif fetch_errors:
        chip = "fetch-failed"
    elif c["suspended"]:
        chip = "suspended"
    elif busy_deploy or following:
        chip = "deploying"
    elif busy_build:
        chip = "building"
    elif pending:
        chip = "pending"
    elif runs["source"] == "testing":
        chip = "testing"
    elif runs["source"] == "hand":
        chip = "by-hand"
    elif behind:
        chip = "behind"
    elif reboot_staged:
        chip = "reboot"
    elif kernel_changed and (not nb["known"] or nb["out"] == cur):
        chip = "reboot-kernel"
    else:
        chip = "up-to-date"

    # The newest system comin has for this host, for the diff.
    built = bg.get("out_path") if bg and bg.get("build_status") == "built" and not is_testing(bg) else None
    newest_out = held_out or built or staged_out
    diff_to = newest_out if (newest_out and cur and newest_out != cur
                             and SYSTEM_PATH.fullmatch(newest_out)) else None

    has_cd = f["mode"] is not None
    blocked = ("comin is building" if busy_build else "comin is deploying" if (busy_deploy or following)
               else "comin is suspended" if c["suspended"] else None)

    def gate(ok, reason):
        return {"allowed": True} if ok else {"allowed": False, "reason": reason}

    switch_target = None
    if pending:
        switch_target = "held"
    elif reboot_staged and dep.get("operation") == "boot" and dep.get("status") == "done" and dep_out != cur:
        switch_target = "staged"
    elif deploy_failed:
        switch_target = "retry"
    acts = {
        "switch": (gate(False, "no comin-deploy on this host") if not has_cd
                   else gate(False, blocked) if blocked
                   else gate(False, "nothing held, staged or failed") if switch_target is None
                   else {"allowed": True, "target": switch_target,
                         "generation": held["uuid"] if switch_target == "held" else None}),
        "boot": (gate(False, "macOS has no boot") if host["darwin"]
                 else gate(False, "no comin-deploy on this host") if not has_cd
                 else gate(False, blocked) if blocked
                 else gate(False, "nothing held") if held is None
                 else gate(False, "same system as staged; comin-deploy releases it") if not pending
                 else gate(False, "comin deploys a testing generation with test, never for boot") if is_testing(held)
                 else {"allowed": True, "generation": held["uuid"]}),
        "mode": (gate(False, "no comin-deploy on this host") if not has_cd
                 else gate(False, blocked) if blocked
                 else {"allowed": True, "current": f["mode"],
                       "values": ["manual", "switch"] if host["darwin"] else ["manual", "boot", "switch"]}),
        "reboot": (gate(False, "macOS") if host["darwin"]
                   else gate(False, "comin is building") if busy_build
                   else gate(False, "comin is deploying") if (busy_deploy or following)
                   else {"allowed": True}),
        "diff": (gate(False, "the running system is comin's newest") if diff_to is None
                 else {"allowed": True, "to": diff_to}),
        "ssh": {"allowed": True},
    }
    info = {
        "current": cur, "booted": f["booted"], "staged": staged_out, "held": held_out,
        "next_boot": nb.get("out") if nb["known"] else None, "next_boot_why": nb.get("why"),
        "booted_kernel": f["booted_kernel"], "current_kernel": f["current_kernel"],
        "inhibitors": {"current": dep.get("current_inhibitors") or {}, "new": dep.get("new_inhibitors") or {}},
        "deployment": {"commit": get(dep, "generation", "selected_commit_id"), "status": dep.get("status"),
                       "operation": dep.get("operation"), "error": dep.get("error_msg") or None},
        "testing": testing_info, "suspend_reason": c["suspend_reason"] or None,
        "fetched": fetched or None, "comin_main": repo.get("main_commit_id") or None,
    }
    return done(chip, runs=runs, lines=lines, actions=acts, online=True, mode=f["mode"],
                behind=behind, behind_why=behind_why, info=info)


def check_command(row, cmd):
    """None if `cmd` (a parsed host command) may run on the host whose latest
    row is `row`, else (reason, why)."""
    if row is None:
        return ("no-state", "not probed yet")
    act = row["actions"].get(cmd["cmd"])
    if act is None:
        return ("unknown-command", cmd["cmd"])
    if not act["allowed"]:
        return ("not-allowed", act.get("reason"))
    if cmd["cmd"] in ("switch", "boot"):
        want = act.get("generation")
        if cmd.get("generation") != want:
            return ("stale", "the held generation is " + (want or "none") + " now")
    if cmd["cmd"] == "mode" and cmd.get("value") not in act["values"]:
        return ("bad-value", "mode must be one of " + ", ".join(act["values"]))
    return None


# ---- effects ----

def emit(**obj):
    with LOCK:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def run(argv, timeout):
    """(exit code, stdout, stderr); stdout is what arrived before a timeout."""
    try:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True, errors="replace")
    except OSError as e:
        return 127, "", str(e)
    try:
        out, err = p.communicate(timeout=timeout)
        return p.returncode, out, err
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return None, out or "", (err or "") + f"\nno answer in {timeout} s"


def last_line(text):
    lines = [x for x in (text or "").strip().split("\n") if x.strip()]
    return lines[-1].strip() if lines else ""


def probe_host(host):
    if host["local"]:
        code, out, err = run(["sh", "-c", PROBE], PROBE_TIMEOUT)
    else:
        code, out, err = run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host["alias"], PROBE],
                             PROBE_TIMEOUT)
    if "@@booted" not in out:
        return {"ok": False, "text": "", "error": last_line(err) or f"ssh exited with {code}"}
    return {"ok": True, "text": out}


def read_github(gh, repo):
    code, out, err = run([gh, "api", f"repos/{repo}/git/matching-refs/heads/"], GH_TIMEOUT)
    if code != 0:
        return {"state": "error", "error": last_line(err) or f"gh exited with {code}"}
    try:
        refs = {r["ref"][len("refs/heads/"):]: r["object"]["sha"] for r in json.loads(out)}
    except (ValueError, KeyError, TypeError):
        return {"state": "error", "error": "gh api: unexpected answer"}
    result = {"state": "ok", "master": refs.get("master", ""), "deploy": refs.get("deploy", ""),
              "testing_branches": sorted(n for n in refs if n.startswith("testing-")), "ahead": 0, "run": None}
    code, out, _ = run([gh, "run", "list", "-R", repo, "-w", "build.yml", "-b", "master", "-L", "1",
                        "--json", "status,conclusion,headSha,displayTitle,url,createdAt"], GH_TIMEOUT)
    if code == 0:
        try:
            r = (json.loads(out) or [None])[0]
            if r:
                result["run"] = {"status": r.get("status"), "conclusion": r.get("conclusion"), "url": r.get("url"),
                                 "head_sha": r.get("headSha"), "title": r.get("displayTitle"),
                                 "created_at": r.get("createdAt")}
        except (ValueError, TypeError, AttributeError):
            pass
    if result["master"] and result["deploy"] and result["master"] != result["deploy"]:
        code, out, _ = run([gh, "api", f"repos/{repo}/compare/{result['deploy']}...{result['master']}",
                            "--jq", ".ahead_by"], GH_TIMEOUT)
        result["ahead"] = int(out.strip()) if code == 0 and out.strip().isdigit() else None
    return result


class Sessions:
    """One tmux session per host on a private socket, holding its last action."""

    def __init__(self, tmux, runtime):
        self.tmux = tmux
        self.dir = runtime
        os.makedirs(runtime, mode=0o700, exist_ok=True)
        self.sock = os.path.join(runtime, "tmux.sock")
        self.conf = os.path.join(runtime, "tmux.conf")
        with open(self.conf, "w") as fh:
            # The pane stays after its command ends, so attach shows the output.
            fh.write("set -g remain-on-exit on\nset -g history-limit 50000\n")

    def t(self, *args):
        return [self.tmux, "-S", self.sock, "-f", self.conf, *args]

    def status_file(self, label):
        return os.path.join(self.dir, f"{label}.exit")

    def start(self, label, argv):
        subprocess.run(self.t("kill-session", "-t", f"={label}"), stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        st = self.status_file(label)
        try:
            os.unlink(st)
        except FileNotFoundError:
            pass
        wrapper = ["sh", "-c", 'st=$1; shift; "$@"; echo "$?" >"$st"', "sh", st, *argv]
        r = subprocess.run(self.t("new-session", "-d", "-s", label, "-x", "160", "-y", "48", *wrapper),
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        return r.returncode == 0, r.stderr.strip()

    def exists(self, label):
        return subprocess.run(self.t("has-session", "-t", f"={label}"), stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0

    def exit_code(self, label):
        try:
            with open(self.status_file(label)) as fh:
                text = fh.read().strip()
        except FileNotFoundError:
            return None
        return int(text) if text.lstrip("-").isdigit() else -1

    def tail(self, label):
        r = subprocess.run(self.t("capture-pane", "-p", "-J", "-t", f"={label}:", "-S", "-2000"),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace")
        # The pane's unused rows are blank, and tmux marks a finished pane
        # with its own line; the exit code is reported on its own.
        lines = [x for x in r.stdout.split("\n") if x.strip() and not x.startswith("Pane is dead")]
        return lines[-TAIL_LINES:]

    def attach_argv(self, label):
        return self.t("attach-session", "-t", f"={label}")


def ghostty(title, argv=None):
    cmd = ["ghostty", f"--title={title}"] + (["-e", *argv] if argv else [])
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return None
    except OSError as e:
        return str(e)


def on_host(host, command, tty=True):
    """argv running a fixed `command` on the host: here, or over ssh."""
    if host["local"]:
        return ["sh", "-c", command]
    return ["ssh", *(["-t"] if tty else []), "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
            host["alias"], command]


class Fleet:
    def __init__(self, config, gh, sessions, read_only=False):
        self.read_only = read_only
        self.repo = config["repo"]
        self.hosts = {h["label"]: h for h in config["hosts"]}
        self.order = [h["label"] for h in config["hosts"]]
        self.gh = gh
        self.sessions = sessions
        self.github = None
        self.probes = {}
        self.rows = {}
        self.inflight = set()
        self.last_probe = {}
        self.follow = {}  # label -> {"started", "idle_since"}
        self.running = {}  # label -> action id
        self.open = False
        self.last_round = None
        self.round_left = 0
        self.refresh_asked = True
        self.mu = threading.Lock()

    # -- probing --

    def row(self, label):
        with self.mu:
            probe, gh, following = self.probes.get(label), self.github, label in self.follow
        if probe is None:
            return None
        r = host_row(self.hosts[label], probe, gh, datetime.now(timezone.utc), following)
        with self.mu:
            self.rows[label] = r
        emit(**r)
        return r

    def probe(self, label, in_round=False):
        with self.mu:
            if label in self.inflight:
                if in_round:
                    self.round_finished_one()
                return
            self.inflight.add(label)
        emit(event="probing", host=label)

        def work():
            result = probe_host(self.hosts[label])
            with self.mu:
                self.probes[label] = result
                self.inflight.discard(label)
                self.last_probe[label] = time.monotonic()
            r = self.row(label)
            self.after_probe(label, r)
            if in_round:
                with self.mu:
                    self.round_finished_one()

        threading.Thread(target=work, daemon=True).start()

    def round_finished_one(self):
        self.round_left -= 1
        if self.round_left == 0:
            emit(event="round", state="done", at=iso(datetime.now(timezone.utc)))

    def start_round(self):
        with self.mu:
            self.last_round = time.monotonic()
            self.refresh_asked = False
            self.round_left = len(self.order) + 1
        emit(event="round", state="started", at=iso(datetime.now(timezone.utc)))

        def gh_work():
            result = read_github(self.gh, self.repo)
            result["at"] = iso(datetime.now(timezone.utc))
            emit(event="github", **result)
            with self.mu:
                self.github = result if result["state"] == "ok" else None
                known = [k for k in self.order if k in self.probes]
            for label in known:
                self.row(label)
            with self.mu:
                self.round_finished_one()

        threading.Thread(target=gh_work, daemon=True).start()
        for label in self.order:
            self.probe(label, in_round=True)

    def after_probe(self, label, r):
        with self.mu:
            fol = self.follow.get(label)
            if fol is None:
                return
            t = time.monotonic()
            idle = r is not None and r["online"] and r["chip"]["id"] not in ("no-comin",) \
                and not any(x["key"] == "next" and x["tone"] != "red" for x in r["lines"])
            stop = False
            if r is None or not r["online"] or t - fol["started"] >= FOLLOW_CAP:
                stop = True
            elif idle:
                fol["idle_since"] = fol["idle_since"] or t
                stop = t - fol["idle_since"] >= FOLLOW_IDLE and t - fol["started"] >= FOLLOW_MIN
            else:
                fol["idle_since"] = None
            if stop:
                del self.follow[label]
        if stop:
            self.row(label)

    def tick(self):
        t = time.monotonic()
        with self.mu:
            interval = INTERVAL_OPEN if self.open else INTERVAL_CLOSED
            # A round still waiting on a slow host is not overlapped; an
            # asked refresh waits for it.
            due = self.round_left == 0 and (self.refresh_asked or self.last_round is None
                                            or t - self.last_round >= interval)
            followed = [k for k in self.follow
                        if k not in self.inflight and t - self.last_probe.get(k, 0) >= FOLLOW_EVERY]
        if due:
            self.start_round()
        for label in followed:
            self.probe(label)

    def loop(self):
        while True:
            self.tick()
            time.sleep(1)

    # -- commands --

    def command(self, msg):
        cid = msg.get("id")
        name = msg.get("cmd")
        if name == "refresh":
            with self.mu:
                self.refresh_asked = True
            return
        if name in ("open", "closed"):
            with self.mu:
                self.open = name == "open"
                if self.open and (self.last_round is None or time.monotonic() - self.last_round >= INTERVAL_OPEN):
                    self.refresh_asked = True
            return
        label = msg.get("host")
        base = {"id": cid, "host": label, "action": name}
        if name not in HOST_ACTIONS and name != "attach":
            emit(event="action", **base, state="refused", reason="unknown-command")
            return
        if label not in self.hosts:
            emit(event="action", **base, state="refused", reason="unknown-host")
            return
        host = self.hosts[label]
        if self.read_only and name in ("switch", "boot", "mode", "reboot"):
            emit(event="action", **base, state="refused", reason="read-only")
            return
        if name == "attach":
            if not self.sessions.exists(label):
                emit(event="action", **base, state="refused", reason="no-session")
                return
            err = ghostty(f"Fleet: {label}", self.sessions.attach_argv(label))
            emit(event="action", **base, state="failed" if err else "ok", **({"reason": err} if err else {}))
            return
        with self.mu:
            row = self.rows.get(label)
            busy = label in self.running
        refusal = check_command(row, msg)
        if refusal is None and busy and name not in ("diff", "ssh"):
            refusal = ("busy", "an action is running on this host")
        if refusal:
            emit(event="action", **base, state="refused", reason=refusal[0], why=refusal[1])
            return
        act = row["actions"][name]
        if name == "diff":
            path = act["to"]
            if host["local"]:
                argv = ["sh", "-c", 'nix store diff-closures /run/current-system "$1"; printf "\\nPress Enter to close. "; read _',
                        "sh", path]
            else:
                argv = ["sh", "-c", 'ssh -t -o ConnectTimeout=5 "$1" "nix store diff-closures /run/current-system $2"; '
                        'printf "\\nPress Enter to close. "; read _', "sh", host["alias"], path]
            err = ghostty(f"Fleet: {label} diff", argv)
        elif name == "ssh":
            err = ghostty(f"Fleet: {label}", None if host["local"] else ["ssh", host["alias"]])
        else:
            self.run_action(cid, host, name, msg, act)
            return
        emit(event="action", **base, state="failed" if err else "ok", **({"reason": err} if err else {}))

    def run_action(self, cid, host, name, msg, act):
        label = host["label"]
        if name == "switch":
            command = "comin-deploy switch" + (f" {act['generation']}" if act.get("generation") else "")
        elif name == "boot":
            command = f"comin-deploy boot {act['generation']}"
        elif name == "mode":
            command = f"comin-deploy mode {msg['value']}"
        elif host["local"]:
            command = "systemctl reboot"
        else:
            command = "sudo -n systemctl reboot"
        # The host's shell reads this: every word above is fixed or checked
        # (the generation is the row's own and matched UUID on input, the
        # mode is one of the row's values).
        ok, err = self.sessions.start(label, on_host(host, command))
        base = {"id": cid, "host": label, "action": name}
        if not ok:
            emit(event="action", **base, state="failed", reason=err or "tmux failed")
            return
        with self.mu:
            self.running[label] = cid
            if name in ("switch", "boot"):
                self.follow[label] = {"started": time.monotonic(), "idle_since": None}
        emit(event="action", **base, state="started")
        if name in ("switch", "boot"):
            self.row(label)
        threading.Thread(target=self.watch_action, args=(cid, host, name), daemon=True).start()

    def watch_action(self, cid, host, name):
        label = host["label"]
        base = {"id": cid, "host": label, "action": name}
        shown, last_emit = None, 0.0
        while True:
            code = self.sessions.exit_code(label)
            tail = self.sessions.tail(label)
            if code is not None:
                break
            if not self.sessions.exists(label):
                code = -1
                break
            if tail != shown and time.monotonic() - last_emit >= 2:
                shown, last_emit = tail, time.monotonic()
                emit(event="action", **base, state="running", tail=tail)
            time.sleep(1)
        if name == "reboot" and not host["local"] and code != 0 \
                and any("password is required" in x for x in tail):
            emit(event="message", host=label, kind="sudo-password",
                 text=f"sudo on {label} needs a password: type it in the terminal that opened.")
            self.sessions.start(label, on_host(host, "sudo systemctl reboot"))
            err = ghostty(f"Fleet: {label} reboot", self.sessions.attach_argv(label))
            if err:
                emit(event="action", **base, state="failed", tail=tail, exit=code, reason=err)
                with self.mu:
                    self.running.pop(label, None)
                return
            emit(event="action", **base, state="running", tail=tail)
            self.watch_action_interactive(cid, host, name)
            return
        emit(event="action", **base, state="ok" if code == 0 else "failed", tail=tail, exit=code)
        with self.mu:
            self.running.pop(label, None)
        if name == "mode":
            self.probe(label)

    def watch_action_interactive(self, cid, host, name):
        label = host["label"]
        while self.sessions.exit_code(label) is None and self.sessions.exists(label):
            time.sleep(1)
        code = self.sessions.exit_code(label)
        emit(event="action", id=cid, host=label, action=name, state="ok" if code == 0 else "failed",
             tail=self.sessions.tail(label), exit=code if code is not None else -1)
        with self.mu:
            self.running.pop(label, None)


def parse_command(line):
    """The command in one stdin line, or raises ValueError(id)."""
    msg = json.loads(line)
    if not isinstance(msg, dict):
        raise ValueError(None)
    cid = msg.get("id")
    if cid is not None and (not isinstance(cid, int) or isinstance(cid, bool)):
        raise ValueError(None)
    if not set(msg) <= {"id", "cmd", "host", "generation", "value"}:
        raise ValueError(cid)
    for key in ("cmd", "host", "generation", "value"):
        if key in msg and not isinstance(msg[key], str):
            raise ValueError(cid)
    if "generation" in msg and not UUID.fullmatch(msg["generation"]):
        raise ValueError(cid)
    if not isinstance(msg.get("cmd"), str):
        raise ValueError(cid)
    return msg


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=CONFIG)
    parser.add_argument("--gh", default=GH)
    parser.add_argument("--tmux", default=TMUX)
    parser.add_argument("--runtime", default=os.path.join(
        os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/desk-fleet-{os.getuid()}", "desk-fleet"))
    parser.add_argument("--read-only", action="store_true")
    args = parser.parse_args()
    with open(args.config) as fh:
        config = json.load(fh)

    fleet = Fleet(config, args.gh, Sessions(args.tmux, args.runtime), args.read_only)
    emit(event="hello", repo=fleet.repo, read_only=args.read_only,
         hosts=[{"host": h["label"], "alias": h["alias"], "darwin": h["darwin"], "device": h["device"],
                 "local": h["local"]} for h in config["hosts"]])
    threading.Thread(target=fleet.loop, daemon=True).start()

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            msg = parse_command(line)
        except json.JSONDecodeError:
            emit(event="bad-input", line=line.strip())
            continue
        except ValueError as e:
            emit(event="action", id=e.args[0], state="refused", reason="bad-input")
            continue
        fleet.command(msg)
    emit(event="exit")


if __name__ == "__main__":
    main()
