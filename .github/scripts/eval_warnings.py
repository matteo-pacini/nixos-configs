#!/usr/bin/env python3
"""Collect Nix eval warnings, track proposals in a PR comment, apply accepted ones.

Subcommands (all JSON/markdown files are paths):
  collect DIR OUT                      eval every host in the flake at DIR, write warnings
  new HEAD BASE PREV OUT               warnings in HEAD but not BASE, minus ones dismissed in PREV
  render NEW PROPOSALS PREV PR SHA OUT build the PR comment body
  command TEXT                         print the action and numbers parsed from a PR comment
  apply BODY NUMS REPO OUT             apply accepted edits in REPO, write the updated body
  verify BODY NUMS DIR                 exit 1 unless DIR evals cleanly without those warnings
  mark BODY NUMS STATUS NOTE OUT       set status (dismissed/applied) on warnings, write body
  sources DIR                          print GitHub step outputs with upstream source paths

PREV/BODY may be an empty file when no comment exists yet. NUMS is a space-separated
list of 1-based warning numbers as shown in the comment, or empty for all.
"""

import base64
import hashlib
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
MARKER = "<!-- eval-warnings-bot -->"
DATA_RE = re.compile(r"<!-- eval-warnings-data:([A-Za-z0-9+/=]+) -->")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
# Head and base checkouts live at different store paths; strip the hash so the same
# warning compares equal across them.
STORE_RE = re.compile(r"/nix/store/[a-z0-9]{32}-")
WARNING_START_RE = re.compile(r"^(trace: |evaluation warning: )")
# Not an @mention: the Claude GitHub App also reacts to "@claude" and would start its own session.
COMMAND_RE = re.compile(r"^\s*/warnings (apply|dismiss)\b([ \d]*?)\s*$", re.MULTILINE)


def parse_warnings(stderr):
    warnings, current = [], None
    for line in ANSI_RE.sub("", stderr).splitlines():
        if WARNING_START_RE.match(line):
            if current is not None:
                warnings.append(current)
            current = line
        elif current is not None and line[:1] in (" ", "\t"):
            current += "\n" + line
        else:
            if current is not None:
                warnings.append(current)
            current = None
    if current is not None:
        warnings.append(current)
    return [STORE_RE.sub("/nix/store/…-", w).rstrip() for w in warnings]


def collect(flake_dir):
    hosts = {}
    for attr, host in HOSTS:
        ref = f"{flake_dir}#{attr}.{host}.config.system.build.toplevel.drvPath"
        proc = subprocess.run(["nix", "eval", ref, "--raw"], capture_output=True, text=True)
        hosts[host] = {"ok": proc.returncode == 0, "warnings": parse_warnings(proc.stderr)}
        if proc.returncode != 0:
            hosts[host]["error"] = proc.stderr[-4000:]
        print(f"{host}: ok={hosts[host]['ok']} warnings={len(hosts[host]['warnings'])}", file=sys.stderr)
    return {"hosts": hosts}


def key_of(text):
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def read_data(body):
    match = DATA_RE.search(body)
    if not match:
        return {"warnings": [], "dismissed": []}
    return json.loads(base64.b64decode(match.group(1)))


def new_warnings(head, base, prev_data):
    seen_on_base = {w for h in base["hosts"].values() for w in h["warnings"]}
    dismissed = set(prev_data.get("dismissed", []))
    found = {}
    for host, result in head["hosts"].items():
        for text in result["warnings"]:
            key = key_of(text)
            if text in seen_on_base or key in dismissed:
                continue
            entry = found.setdefault(key, {"key": key, "text": text, "hosts": []})
            if host not in entry["hosts"]:
                entry["hosts"].append(host)
    return list(found.values())


def fence(text, lang=""):
    ticks = "`" * max(3, max((len(m) for m in re.findall(r"`+", text)), default=0) + 1)
    return f"{ticks}{lang}\n{text}\n{ticks}"


def edit_diff(edit):
    lines = [f"# {edit['file']}"]
    lines += [f"- {l}" for l in edit["old"].splitlines()]
    lines += [f"+ {l}" for l in edit["new"].splitlines()]
    return "\n".join(lines)


def render(data):
    out = [MARKER, "### New eval warnings", ""]
    warnings = data["warnings"]
    if not warnings:
        out.append(f"No eval warnings new to this PR as of `{data['sha'][:7]}`.")
    else:
        out.append(
            f"{len(warnings)} warning(s) on this PR that `master` doesn't have. "
            "This is a proposal: nothing changes until you reply."
        )
    for i, w in enumerate(warnings, 1):
        status = {"applied": " · **applied**", "dismissed": " · **dismissed**"}.get(w.get("status"), "")
        note = f" ({w['note']})" if w.get("note") else ""
        out += ["", f"#### {i}. {w.get('summary') or 'Not analysed'}", "",
                f"Hosts: {', '.join(w['hosts'])}{status}{note}", "", fence(w["text"], "text"), ""]
        verdict = w.get("verdict", "unclear")
        if verdict == "fix" and w.get("edits"):
            out += ["**Proposed fix**", "", fence("\n".join(edit_diff(e) for e in w["edits"]), "diff")]
        elif verdict == "wait":
            out.append("**Suggest waiting**: no replacement upstream yet.")
        else:
            out.append("**No confident fix found.**")
        if w.get("evidence"):
            out += ["", "Evidence:"] + [f"- {e}" for e in w["evidence"]]
    if any(w.get("status", "proposed") == "proposed" for w in warnings):
        out += ["", "---",
                "Reply `/warnings apply` for a PR with every proposed fix, `/warnings apply 1 3` for some, "
                "or `/warnings dismiss` (also takes numbers) to stop proposing them on this PR."]
    stored = {k: data[k] for k in ("pr", "sha", "warnings", "dismissed")}
    out += ["", f"<sub>Checked `{data['sha'][:7]}`</sub>",
            f"<!-- eval-warnings-data:{base64.b64encode(json.dumps(stored).encode()).decode()} -->"]
    return "\n".join(out) + "\n"


def select(data, nums):
    picked = [int(n) for n in nums.split()] if nums.strip() else range(1, len(data["warnings"]) + 1)
    for n in picked:
        if not 1 <= n <= len(data["warnings"]):
            sys.exit(f"There's no warning {n} in the proposal.")
    return [data["warnings"][n - 1] for n in picked]


def check_path(repo, file):
    path = (repo / file).resolve()
    if repo.resolve() not in path.parents or not file.endswith(".nix"):
        sys.exit(f"Refusing to edit {file}: only .nix files inside the repo.")
    if file.startswith((".github/", "secrets/")):
        sys.exit(f"Refusing to edit {file}: .github/ and secrets/ are off limits.")
    if not path.is_file():
        sys.exit(f"{file} doesn't exist on this branch any more.")
    return path


def apply(data, nums, repo):
    chosen = [w for w in select(data, nums) if w.get("status", "proposed") == "proposed"
              and w.get("verdict") == "fix" and w.get("edits")]
    if not chosen:
        sys.exit("None of those warnings has a proposed fix left to apply.")
    contents = {}
    for w in chosen:
        for e in w["edits"]:
            path = check_path(repo, e["file"])
            text = contents.get(path, path.read_text())
            if text.count(e["old"]) != 1:
                sys.exit(f"The proposed change to {e['file']} no longer matches the branch. "
                         "Push again for a fresh proposal.")
            contents[path] = text.replace(e["old"], e["new"])
    for path, text in contents.items():
        path.write_text(text)
    return chosen


def main(argv):
    cmd, args = argv[1], argv[2:]
    read = lambda p: Path(p).read_text() if Path(p).exists() else ""
    if cmd == "collect":
        Path(args[1]).write_text(json.dumps(collect(args[0]), indent=2))
    elif cmd == "new":
        head, base = json.loads(read(args[0])), json.loads(read(args[1]))
        found = new_warnings(head, base, read_data(read(args[2])))
        Path(args[3]).write_text(json.dumps(found, indent=2))
        print(len(found))
    elif cmd == "render":
        found = json.loads(read(args[0]))
        proposals = {p["key"]: p for p in json.loads(read(args[1]) or "{}").get("warnings", [])}
        prev = read_data(read(args[2]))
        # A fix PR that isn't merged yet leaves its warning on the branch; keep showing it as applied.
        settled = {w["key"]: w for w in prev["warnings"] if w.get("status") in ("applied", "pending")}
        warnings = [settled.get(w["key"]) or
                    {**w, **{k: v for k, v in proposals.get(w["key"], {}).items() if k != "key"},
                     "status": "proposed"} for w in found]
        data = {"pr": int(args[3]), "sha": args[4], "warnings": warnings, "dismissed": prev.get("dismissed", [])}
        Path(args[5]).write_text(render(data))
    elif cmd == "command":
        match = COMMAND_RE.search(args[0].replace("\r", ""))
        print(f"{match.group(1)}\n{match.group(2).strip()}" if match else "")
    elif cmd == "apply":
        data = read_data(read(args[0]))
        chosen = apply(data, args[1], Path(args[2]))
        for w in chosen:
            w["status"] = "pending"
        Path(args[3]).write_text(render(data))
        print(" ".join(str(data["warnings"].index(w) + 1) for w in chosen))
    elif cmd == "verify":
        data = read_data(read(args[0]))
        result = collect(args[2])
        broken = [h for h, r in result["hosts"].items() if not r["ok"]]
        remaining = {w for r in result["hosts"].values() for w in r["warnings"]}
        still = [n for n in args[1].split() if data["warnings"][int(n) - 1]["text"] in remaining]
        if broken or still:
            sys.exit(f"Verification failed. Eval broken on: {', '.join(broken) or 'none'}. "
                     f"Warnings still present: {', '.join(still) or 'none'}.")
    elif cmd == "mark":
        data = read_data(read(args[0]))
        for w in select(data, args[1]):
            if w.get("status", "proposed") in ("proposed", "pending"):
                w["status"], w["note"] = args[2], args[3]
                if args[2] == "dismissed" and w["key"] not in data["dismissed"]:
                    data["dismissed"].append(w["key"])
        Path(args[4]).write_text(render(data))
    elif cmd == "sources":
        archive = subprocess.run(["nix", "flake", "archive", "--json", "--dry-run"], cwd=args[0],
                                 capture_output=True, text=True, check=True)
        inputs = json.loads(archive.stdout)["inputs"]
        paths = {n: inputs[n]["path"] for n in ("nixpkgs", "home-manager", "nix-darwin") if n in inputs}
        print("add_dirs=" + " ".join(f"--add-dir {p}" for p in paths.values()))
        print("sources<<EOF_SOURCES")
        print("\n".join(f"- {n}: {p}" for n, p in paths.items()))
        print("EOF_SOURCES")
    else:
        sys.exit(f"Unknown subcommand {cmd}")


if __name__ == "__main__":
    main(sys.argv)
