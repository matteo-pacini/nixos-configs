#!/usr/bin/env python3
"""Helpers for the CI fixer workflow.

Subcommands:
  failures RUN_ID OUT_DIR      save failed job logs to OUT_DIR, print GitHub step outputs
  guard                        exit 1 if the working tree touches paths the fixer may not edit
  verify BUILD_ATTR            eval every host; also build BUILD_ATTR when non-empty
  comment KIND DIAG FIX OUT    render a PR comment (KIND: fixed, escalate, failed, rerun, rerun-again, cap, update)
"""

import json
import re
import subprocess
import sys
from pathlib import Path

HOSTS = [
    ("nixosConfigurations", "BrightFalls"),
    ("nixosConfigurations", "Nexus"),
    ("nixosConfigurations", "CauldronLake"),
    ("darwinConfigurations", "WorkLaptop"),
    ("darwinConfigurations", "NightSprings"),
]
DARWIN = {h for a, h in HOSTS if a == "darwinConfigurations"}
MARKER = "<!-- ci-fixer -->"
JOB_RE = re.compile(r"^(eval|pr-build) \((\w+)")
# Failures a rerun can fix. Anything else goes to the model.
TRANSIENT_RE = re.compile(
    r"error sending request for url|Gateway Time-?out|50[234] (Bad Gateway|Service Unavailable)"
    r"|Connection (reset|refused|timed out)|Operation timed out|Could not resolve host"
    r"|No space left on device|lost communication with the server|received a shutdown signal"
    r"|HTTP error 5\d\d"
)
LOG_PREFIX_RE = re.compile(r"^[^\t]*\t[^\t]*\t\S+ ?")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
ALLOWED_RE = re.compile(r"^(?!\.github/|secrets/)[\w./@+-]+\.(nix|patch|diff)$|^flake\.lock$")
LOG_TAIL = 400


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


def failures(run_id, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    jobs = json.loads(gh("run", "view", run_id, "--json", "jobs"))["jobs"]
    failed = [j for j in jobs if j["conclusion"] == "failure"]
    logs = {}
    for line in gh("run", "view", run_id, "--log-failed").splitlines():
        job = line.split("\t", 1)[0]
        logs.setdefault(job, []).append(ANSI_RE.sub("", LOG_PREFIX_RE.sub("", line)))
    kinds, hosts, transient = set(), set(), False
    for j in failed:
        m = JOB_RE.match(j["name"])
        kinds.add(m.group(1) if m else "other")
        if m:
            hosts.add(m.group(2))
        lines = logs.get(j["name"], [])
        # Post-job cleanup output follows the error; drop it so the tail ends at the failure.
        errors = [i for i, l in enumerate(lines) if l.startswith("##[error]")]
        tail = lines[: errors[-1] + 1 if errors else len(lines)][-LOG_TAIL:]
        steps = [s["name"] for s in j["steps"] if s["conclusion"] == "failure"]
        name = re.sub(r"[^\w-]+", "_", j["name"])[:60]
        (out / f"{name}.log").write_text(f"job: {j['name']}\nfailed step: {', '.join(steps)}\n\n" + "\n".join(tail) + "\n")
        transient |= bool(TRANSIENT_RE.search("\n".join(tail)))
    kind = "build" if "pr-build" in kinds else "eval" if kinds == {"eval"} else "other"
    print(f"kind={kind}")
    print(f"hosts={' '.join(sorted(hosts))}")
    print(f"jobs={'; '.join(j['name'] for j in failed)}")
    print(f"platform={'darwin' if kind == 'build' and hosts & DARWIN else 'linux'}")
    print(f"transient={'true' if transient else 'false'}")


def guard():
    status = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"],
                            capture_output=True, text=True, check=True).stdout
    paths = [line[3:].split(" -> ")[-1] for line in status.splitlines()]
    bad = [p for p in paths if not ALLOWED_RE.match(p)]
    if not paths:
        sys.exit("The fixer didn't change anything.")
    if bad:
        sys.exit(f"The fixer touched files it may not edit: {', '.join(bad)}")
    print("\n".join(paths))


def verify(build_attr):
    broken = []
    for attr, host in HOSTS:
        proc = subprocess.run(["nix", "eval", f".#{attr}.{host}.config.system.build.toplevel.drvPath", "--raw"],
                              capture_output=True, text=True)
        print(f"eval {host}: {'ok' if proc.returncode == 0 else 'FAILED'}", file=sys.stderr)
        if proc.returncode != 0:
            broken.append(host)
            print(proc.stderr[-3000:], file=sys.stderr)
    if broken:
        sys.exit(f"Eval still fails on: {', '.join(broken)}.")
    if build_attr:
        proc = subprocess.run(["nix", "build", build_attr, "--no-link", "-L"], capture_output=True, text=True)
        if proc.returncode != 0:
            print(proc.stderr[-6000:], file=sys.stderr)
            sys.exit(f"{build_attr} still fails to build.")
        print(f"build {build_attr}: ok", file=sys.stderr)


def bullets(items):
    return "\n".join(f"- {i}" for i in items) if items else "- none recorded"


def comment(kind, diag_path, fix_path, out):
    read = lambda p: json.loads(Path(p).read_text() or "{}") if p and Path(p).exists() else {}
    diag, fix = read(diag_path), read(fix_path)
    title = {
        "fixed": "Fixed and pushed",
        "escalate": "Needs you",
        "failed": "Couldn't fix it",
        "rerun": "Transient failure, re-running",
        "rerun-again": "Failed again after a rerun",
        "cap": "Giving up after two attempts",
        "update": "Updated from master",
    }[kind]
    lines = [MARKER, f"### CI fixer: {title}", ""]
    if kind in ("escalate", "failed", "rerun-again", "cap"):
        lines += ["@matteo-pacini", ""]
    if kind == "rerun":
        lines.append("The failed jobs look like infrastructure trouble (network, cache or runner), not this PR. "
                     "Re-running them once.")
    elif kind == "rerun-again":
        lines.append("The rerun failed the same way, so this probably isn't a flake in the runner. "
                     "Check the cache and runners, or push a fix.")
    elif kind == "cap":
        lines.append("Two fix attempts on this PR didn't get CI green. Over to you.")
    elif kind == "update":
        lines.append("`master` already has the fix for this failure, so I merged `master` into this branch. "
                     "The PR's checks are re-running.")
    if diag:
        lines += ["", f"**What failed:** {diag.get('failure', '')}", "", "**Diagnosis**", "", diag.get("diagnosis", "")]
        if diag.get("evidence"):
            lines += ["", "**Evidence**", "", bullets(diag["evidence"])]
    if kind == "fixed":
        lines += ["", "**Fix**", "", fix.get("summary", ""), "",
                  f"Commit: {fix.get('sha', '')}. All five hosts evaluate"
                  + (f" and `{diag['verify_build']}` builds" if diag.get("verify_build") else "")
                  + ". The PR's checks are re-running."]
    elif kind == "escalate" and diag.get("question"):
        lines += ["", "**Over to you**", "", diag["question"]]
    elif kind == "failed":
        lines += ["", "**What went wrong**", "", fix.get("error") or fix.get("summary") or "See the workflow run."]
    if kind in ("escalate", "failed", "rerun-again", "cap"):
        lines += ["", "Reply `/fix <what to do>` and I'll try again with your instructions."]
    lines += ["", "<sub>Add the `bot:off` label to stop the CI fixer on this PR; `/fix` still works.</sub>"]
    Path(out).write_text(re.sub(r"\n{3,}", "\n\n", "\n".join(lines)) + "\n")


def main(argv):
    cmd, args = argv[1], argv[2:]
    if cmd == "failures":
        failures(*args)
    elif cmd == "guard":
        guard()
    elif cmd == "verify":
        verify(args[0] if args else "")
    elif cmd == "comment":
        comment(*args)
    else:
        sys.exit(f"Unknown subcommand {cmd}")


if __name__ == "__main__":
    main(sys.argv)
