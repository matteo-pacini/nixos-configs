"""desk-fleet: its state model against probe fixtures, then the built helper
against fake ssh, comin, comin-deploy, sudo, ghostty and gh.

Usage: test-desk-fleet.py <desk-fleet> <desk-fleet.py> <fixtures dir> <work dir>

fixtures/*.probe are real probes cut down to the fields the model reads
(brightfalls.probe in the current PROBE format; nexus and nightsprings from
an older probe without kernels or profile time). Every other case is built
below. The fakes log every call to $FAKE/log; refused commands must add
nothing to it.
"""

import importlib.util
import json
import os
import queue
import stat
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone

HELPER, SOURCE, FIXTURES, WORK = sys.argv[1:5]

spec = importlib.util.spec_from_file_location("desk_fleet", SOURCE)
fleet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fleet)

NOW = datetime(2026, 11, 16, 12, 0, tzinfo=timezone.utc)
FAILURES = []


def check(name, cond, detail=""):
    if not cond:
        FAILURES.append(f"{name}: {detail}")
        print(f"FAIL {name}: {detail}")


def t(minutes):
    return (NOW - timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")


def sp(tag, kind="nixos-system-Test"):
    return "/nix/store/" + (tag * 32)[:32] + "-" + kind


def uid(n):
    return f"{n:08x}-0000-4000-8000-000000000000"


C1, C2, C3 = "1" * 40, "2" * 40, "3" * 40
CT = "7" * 40
A, B, X, T, Z = sp("a"), sp("b"), sp("x"), sp("t"), sp("z")
K1, K2 = sp("k", "linux-7.3/bzImage"), sp("m", "linux-7.4/bzImage")


def G(n, commit, out, testing=False, ago=60, eval_err="", build_err="", built=True):
    return {"uuid": uid(n), "selected_commit_id": commit, "out_path": out if built else "",
            "selected_branch_name": "testing-Nexus" if testing else "deploy",
            "selected_branch_is_testing": testing, "eval_err": eval_err, "build_err": build_err,
            "build_status": "built" if built and not build_err else ("failed" if build_err else ""),
            "eval_started_at": t(ago + 2), "eval_ended_at": t(ago + 1),
            "build_started_at": t(ago + 1), "build_ended_at": t(ago) if built else None}


def D(gen, op="boot", status="done", ago=120, error=""):
    return {"generation": gen, "status": status, "operation": op, "operation_submitted": op,
            "created_at": t(ago + 1), "ended_at": t(ago) if status != "running" else None,
            "error_msg": error, "current_inhibitors": {}, "new_inhibitors": {}}


def status(deps=(), gens=(), builder=None, held="", deployment=None, deploying=False, queued=None,
           evaluating=False, building=False, suspended=False, fetch_err="", main=C2, selected=None,
           testing_err="", fetched_ago=1):
    deps = list(deps)
    sel = selected or main
    return {
        "is_suspended": suspended,
        "builder": {"is_evaluating": evaluating, "is_building": building, "generation": builder},
        "deployer": {"is_deploying": deploying, "is_suspended": suspended, "operation": "boot" if queued else "",
                     "generation_to_deploy": queued,
                     "deployment": deployment if deployment is not None else (deps[-1] if deps else None)},
        "fetcher": {"repository_status": {
            "selected_commit_id": sel, "selected_branch_name": "deploy", "selected_branch_is_testing": False,
            "main_commit_id": main, "error_msg": "",
            "remotes": [{"name": "origin", "fetch_error_msg": fetch_err, "fetched_at": t(fetched_ago),
                         "main": {"commit_id": main},
                         "testing": {"name": "testing-Nexus", "commit_id": "",
                                     "error_msg": testing_err or "the branch 'origin/testing-Nexus' doesn't exist"}}]}},
        "store": {"deployments": deps, "generations": list(gens),
                  "deployer": {"is_suspended": suspended, "suspend_reason": ""}},
        "deploy_confirmer": {"submitted": held},
    }


def probe_text(st, current, booted=None, bk=K1, ck=K1, profile_ago=600, mode="manual", efi=()):
    profile = "" if profile_ago is None else str(int((NOW - timedelta(minutes=profile_ago)).timestamp()))
    return "\n".join([
        "@@booted", booted or current or "", "@@current", current or "", "@@bkernel", bk or "",
        "@@ckernel", ck or "", "@@profile", profile, "@@efi", *efi, "@@mode", mode or "",
        "@@status", json.dumps(st) if st is not None else "", "", "@@end", ""])


LINUX = {"label": "Nexus", "alias": "nexus", "darwin": False, "device": "server", "local": False}
MAC = {"label": "NightSprings", "alias": "nightsprings", "darwin": True, "device": "laptop", "local": False}
LOCAL = {"label": "BrightFalls", "alias": "brightfalls", "darwin": False, "device": "desktop", "local": True}
GH = {"state": "ok", "master": C3, "deploy": C2, "testing_branches": []}


def row(text, host=LINUX, github=GH, following=False):
    return fleet.host_row(host, {"ok": True, "text": text}, github, NOW, following)


def lines(r, key):
    return [x["text"] for x in r["lines"] if x["key"] == key]


def allowed(r):
    return sorted(k for k, v in r["actions"].items() if v["allowed"])


def expect(name, r, chip, keys=None, runs=None, has=(), lacks=()):
    check(name + " chip", r["chip"]["id"] == chip, f"{r['chip']['id']} != {chip}; lines {r['lines']}")
    if keys is not None:
        check(name + " keys", allowed(r) == sorted(keys), f"{allowed(r)} != {sorted(keys)}")
    if runs is not None:
        check(name + " runs", r["runs"]["source"] == runs, f"{r['runs']}")
    for key, text in has:
        check(name + f" line {key}", any(text in x for x in lines(r, key)), f"{text!r} not in {lines(r, key)}")
    for key in lacks:
        check(name + f" no {key} line", not lines(r, key), f"{lines(r, key)}")


def model_tests():
    g_a, g_b = G(1, C1, A, ago=3000), G(2, C2, B, ago=30)
    base = [D(g_a, ago=2900)]

    # Every chip of the design's table, in its order.
    r = fleet.host_row(LINUX, {"ok": False, "text": "", "error": "No route to host"}, GH, NOW)
    expect("offline", r, "offline", keys=[], has=[("ssh", "No route to host")])

    r = row(probe_text(None, A))
    expect("no comin", r, "no-comin", keys=["reboot", "ssh"], has=[("comin", "no answer")])

    st = status(base + [D(g_b, status="failed", ago=5, error="switch-to-configuration exited with status 4")],
                gens=[g_a, g_b], builder=g_b, deployment=D(g_b, status="failed", ago=5,
                                                           error="switch-to-configuration exited with status 4"))
    r = row(probe_text(st, A, profile_ago=6000))
    expect("deploy failed", r, "deploy-failed", keys=["switch", "diff", "mode", "reboot", "ssh"],
           has=[("failed", "2222222 · switch-to-configuration exited with status 4")])
    check("deploy failed retries", r["actions"]["switch"].get("target") == "retry", r["actions"]["switch"])

    g_err = G(3, C2, "", build_err="error: builder for foo failed", built=False)
    r = row(probe_text(status(base, gens=[g_a, g_err], builder=g_err), A, profile_ago=6000))
    expect("build failed", r, "build-failed", keys=["mode", "reboot", "ssh"],
           has=[("next", "2222222 · error: builder for foo failed")])

    g_eval = G(3, C2, "", eval_err="error: attribute 'foo' missing", built=False)
    r = row(probe_text(status(base, gens=[g_a, g_eval], builder=g_eval), A, profile_ago=6000))
    expect("eval failed", r, "build-failed", has=[("next", "attribute 'foo' missing")])

    # A multi-line error keeps its full text and carries its first line.
    trace = "error: attribute 'foo' missing\n       at /hosts/Nexus/default.nix:3:5:\n            2|"
    g_trace = G(4, C2, "", eval_err=trace, built=False)
    r = row(probe_text(status(base, gens=[g_a, g_trace], builder=g_trace), A, profile_ago=6000))
    nxt = [x for x in r["lines"] if x["key"] == "next"]
    check("multi-line text whole", nxt and nxt[0]["text"] == "2222222 · " + trace, nxt)
    check("multi-line first", nxt and nxt[0]["first"] == "2222222 · error: attribute 'foo' missing", nxt)
    check("every line has first", all(x["first"] == x["text"].split("\n")[0] for x in r["lines"]), r["lines"])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1, fetch_err="could not resolve host"), A,
                       profile_ago=6000))
    expect("fetch failed", r, "fetch-failed", keys=["mode", "reboot", "ssh"],
           has=[("fetch", "origin: could not resolve host")])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1, suspended=True), A, profile_ago=6000),
            github={**GH, "deploy": C1})
    expect("suspended", r, "suspended", keys=["reboot", "ssh"], has=[("comin", "suspended")])
    check("suspended no mode", r["actions"]["mode"]["reason"] == "comin is suspended", r["actions"]["mode"])

    running = D(g_b, status="running", ago=0)
    r = row(probe_text(status(base, gens=[g_a, g_b], builder=g_b, deployment=running, deploying=True), A,
                       profile_ago=6000))
    expect("deploying", r, "deploying", keys=["diff", "ssh"], has=[("next", "2222222 · activating (boot)")])
    check("deploying no reboot", r["actions"]["reboot"]["reason"] == "comin is deploying", r["actions"]["reboot"])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000),
            github={**GH, "deploy": C1}, following=True)
    expect("followed deploy", r, "deploying", keys=["ssh"])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, evaluating=True, main=C2), A, profile_ago=6000))
    expect("building", r, "building", keys=["ssh"], has=[("next", "2222222 · deploy · evaluating")])
    check("building no switch", r["actions"]["switch"]["reason"] == "comin is building", r["actions"]["switch"])

    r = row(probe_text(status(base, gens=[g_a, g_b], builder=g_b, held=g_b["uuid"]), A, profile_ago=6000))
    expect("pending", r, "pending", keys=["switch", "boot", "diff", "mode", "reboot", "ssh"],
           runs="deploy", has=[("held", "2222222 · deploy · built 30m ago")])
    check("pending switch names generation", r["actions"]["switch"]["generation"] == g_b["uuid"], r["actions"]["switch"])

    g_t = G(5, CT, T, testing=True, ago=12)
    st = status(base + [D(g_t, op="test", ago=11)], gens=[g_a, g_t], builder=g_t, deployment=D(g_t, op="test", ago=11))
    r = row(probe_text(st, T, booted=A, profile_ago=6000))
    expect("testing deployed", r, "testing", keys=["diff", "mode", "reboot", "ssh"], runs="testing",
           has=[("boot", "1111111 · deploy · reboot leaves testing")])
    check("testing runs text", r["runs"]["text"].startswith("7777777 · testing-Nexus · test"), r["runs"]["text"])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000), github={**GH, "deploy": C1})
    expect("up to date", r, "up-to-date", keys=["mode", "reboot", "ssh"], runs="deploy", lacks=["boot", "test"])

    # Pending wins over Testing and By hand; Behind and Reboot come after.
    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000))
    expect("behind, not fetched", r, "behind", keys=["mode", "reboot", "ssh"],
           has=[("comin", "has not fetched 2222222 yet · last fetch 1m ago")])
    check("behind why fetched", r["behind_why"] == "not-fetched", r["behind_why"])

    r = row(probe_text(status(base, gens=[g_a, g_b], builder=g_b, main=C2), A, profile_ago=6000))
    expect("behind, different system", r, "behind", keys=["diff", "mode", "reboot", "ssh"],
           has=[("comin", "built 2222222: a different system")])
    check("behind why system", r["behind_why"] == "different-system", r["behind_why"])

    st = status(base + [D(g_b, ago=10)], gens=[g_a, g_b], builder=g_b, main=C2)
    r = row(probe_text(st, A, profile_ago=6000))
    expect("reboot staged", r, "reboot", keys=["switch", "diff", "mode", "reboot", "ssh"],
           has=[("boot", "2222222 · deploy · staged 10m ago · reboot to run it")])
    check("reboot switch target", r["actions"]["switch"].get("target") == "staged", r["actions"]["switch"])

    g_k = G(6, C2, B, ago=12)
    st = status(base + [D(g_k, op="switch", ago=10)], gens=[g_a, g_k], builder=g_k, main=C2)
    r = row(probe_text(st, B, booted=A, bk=K1, ck=K2, profile_ago=6000))
    expect("reboot kernel", r, "reboot-kernel", keys=["mode", "reboot", "ssh"],
           has=[("boot", "same system · new kernel")])

    # The cases that used to read wrong.
    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), X, booted=A, profile_ago=60),
            github={**GH, "deploy": C1})
    expect("hand build, nothing held", r, "by-hand", keys=["diff", "mode", "reboot", "ssh"], runs="hand",
           has=[("boot", "unknown"), ("comin", "1111111 · deploy · last deployed 2d ago")])
    check("hand runs text", r["runs"]["text"] == "built by hand · xxxxxxx · not a comin system", r["runs"]["text"])

    st = status(base, gens=[g_a, g_b], builder=g_b, held=g_b["uuid"])
    r = row(probe_text(st, X, booted=A, profile_ago=60))
    expect("hand build + held", r, "pending", keys=["switch", "boot", "diff", "mode", "reboot", "ssh"], runs="hand",
           has=[("held", "2222222 · deploy · built"), ("boot", "unknown")], lacks=["comin"])

    r = row(probe_text(st, B, booted=A, profile_ago=20))
    expect("activated by hand, same system as held", r, "pending", runs="deploy-by-hand",
           has=[("held", "2222222 · same system · S or B makes it comin's")])
    check("same system runs text", r["runs"]["text"] == "2222222 · deploy · by hand", r["runs"]["text"])

    st = status(base, gens=[g_a], builder=g_a, main=C1, testing_err=(
        "this branch has been hard reset: its head 'fd5e' is not on top of '1111'"))
    gh_t = {**GH, "deploy": C1, "testing_branches": ["testing-Nexus"]}
    r = row(probe_text(st, A, profile_ago=6000), github=gh_t)
    expect("testing rejected", r, "up-to-date", has=[("test", "testing-Nexus ignored: not on top of deploy")])
    r = row(probe_text(st, A, profile_ago=6000), github={**GH, "deploy": C1})
    expect("testing rejected, branch deleted", r, "up-to-date", lacks=["test"])
    check("leftover rejection under info", r["info"]["testing"] and "hard reset" in r["info"]["testing"][0], r["info"])

    g_tb = G(7, CT, T, testing=True, ago=0)
    r = row(probe_text(status(base, gens=[g_a, g_tb], builder=g_tb, building=True), A, profile_ago=6000))
    expect("testing building", r, "building", keys=["ssh"], has=[("next", "7777777 · testing-Nexus · building")])
    check("testing building tone", [x["tone"] for x in r["lines"] if x["key"] == "next"] == ["pink"], r["lines"])

    # comin holds a testing generation like any other on a manual host
    # (manager.go submits every built generation to the deploy confirmer);
    # releasing it deploys with test, so B is refused.
    r = row(probe_text(status(base, gens=[g_a, g_t], builder=g_t, held=g_t["uuid"]), A, profile_ago=6000))
    expect("testing held", r, "pending", keys=["switch", "diff", "mode", "reboot", "ssh"],
           has=[("held", "7777777 · testing-Nexus")])
    check("testing held: no boot", "testing" in r["actions"]["boot"]["reason"], r["actions"]["boot"])

    g_new = G(8, C2, A, ago=5)
    st = status([D(g_a, op="switch", ago=180)], gens=[g_a, g_new], builder=g_new, main=C2)
    r = row(probe_text(st, A, profile_ago=6000))
    expect("newer commit, same system", r, "up-to-date", keys=["mode", "reboot", "ssh"],
           runs="deploy")
    check("same system text", r["runs"]["text"] == "2222222 · deploy · same system as 1111111, switch 3h ago",
          r["runs"]["text"])

    # A held system equal to the staged one is not Pending: comin-deploy auto
    # releases it within a minute.
    g_same = G(9, C2, A, ago=1)
    r = row(probe_text(status(base, gens=[g_a, g_same], builder=g_same, held=g_same["uuid"]), A, profile_ago=6000))
    expect("held equals staged", r, "up-to-date", has=[("held", "same system as staged")])
    check("held equals staged: no boot", "releases" in r["actions"]["boot"]["reason"], r["actions"]["boot"])

    # Darwin: no boot, no reboot, no boot line.
    m_a, m_b = G(10, C1, sp("p", "darwin-system"), ago=3000), G(11, C2, sp("q", "darwin-system"), ago=10)
    st = status([D(m_a, op="switch", ago=2900)], gens=[m_a, m_b], builder=m_b, held=m_b["uuid"])
    r = row(probe_text(st, m_a["out_path"], booted="/private/var/run/booted-system", bk=None, ck=None,
                       profile_ago=None, mode="switch"), host=MAC)
    expect("darwin pending", r, "pending", keys=["switch", "diff", "mode", "ssh"], lacks=["boot"])
    check("darwin boot reason", r["actions"]["boot"]["reason"] == "macOS has no boot", r["actions"]["boot"])
    check("darwin modes", r["actions"]["mode"]["values"] == ["manual", "switch"], r["actions"]["mode"])

    # Next boot: unknown unless comin's last boot entry is newer than the
    # system profile and no EFI variable overrides the default.
    st = status(base + [D(g_b, ago=10)], gens=[g_a, g_b], builder=g_b)
    expect("efi override", row(probe_text(st, A, profile_ago=6000, efi=["LoaderEntryOneShot-4a67"])), "up-to-date",
           has=[("boot", "unknown")])
    expect("rebuilt by hand after comin", row(probe_text(st, A, profile_ago=5)), "up-to-date",
           has=[("boot", "unknown")])
    expect("profile unreadable", row(probe_text(st, A, profile_ago=None)), "up-to-date", has=[("boot", "unknown")])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000), github=None)
    expect("github unknown", r, "up-to-date")
    check("behind unknown", r["behind"] is None, r["behind"])

    r = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000, mode=""),
            github={**GH, "deploy": C1})
    expect("no comin-deploy", r, "up-to-date", keys=["reboot", "ssh"])

    # The real probes.
    def real(name, host):
        with open(os.path.join(FIXTURES, name)) as fh:
            return fleet.host_row(host, {"ok": True, "text": fh.read()},
                                  {**GH, "deploy": "073c52e6831804a69eae70f10a92ab3de29ff200"}, NOW)

    r = real("brightfalls.probe", LOCAL)
    expect("real brightfalls", r, "pending", keys=["switch", "boot", "diff", "mode", "reboot", "ssh"], runs="hand",
           has=[("held", "073c52e · deploy · built"), ("boot", "unknown")])
    check("real brightfalls runs", r["runs"]["text"] == "built by hand · g756j7c · not a comin system", r["runs"]["text"])
    check("real brightfalls boot why", "rebuilt by hand" in r["info"]["next_boot_why"], r["info"])
    r = real("nexus.probe", LINUX)
    expect("real nexus", r, "pending", runs="deploy-by-hand", has=[("held", "073c52e · same system")])
    r = real("nightsprings.probe", MAC)
    expect("real nightsprings", r, "up-to-date", keys=["mode", "ssh"], runs="deploy", lacks=["boot"])

    # The command gate.
    pend = row(probe_text(status(base, gens=[g_a, g_b], builder=g_b, held=g_b["uuid"]), A, profile_ago=6000))
    def gate(r, cmd):
        """The refusal reason, or None if allowed."""
        return (fleet.check_command(r, cmd) or [None])[0]

    check("gate switch ok", gate(pend, {"cmd": "switch", "host": "Nexus", "generation": g_b["uuid"]}) is None)
    check("gate switch stale", gate(pend, {"cmd": "switch", "host": "Nexus", "generation": uid(99)}) == "stale")
    check("gate switch without generation", gate(pend, {"cmd": "switch", "host": "Nexus"}) == "stale")
    check("gate bad mode", gate(pend, {"cmd": "mode", "host": "Nexus", "value": "test"}) == "bad-value")
    check("gate no row", gate(None, {"cmd": "reboot", "host": "Nexus"}) == "no-state")
    up = row(probe_text(status(base, gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000), github={**GH, "deploy": C1})
    check("gate nothing to switch", gate(up, {"cmd": "switch", "host": "Nexus"}) == "not-allowed")
    check("gate unknown command", gate(up, {"cmd": "rm", "host": "Nexus"}) == "unknown-command")


# ---- the built helper with fakes ----

def write_exe(path, text):
    with open(path, "w") as fh:
        fh.write("#!/bin/sh\n" + text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)


def helper_tests():
    fake = os.path.join(WORK, "fake")
    bindir = os.path.join(WORK, "bin")
    os.makedirs(fake)
    os.makedirs(bindir)
    log = os.path.join(fake, "log")
    open(log, "w").close()

    g_a, g_b = G(1, C1, A, ago=3000), G(2, C2, B, ago=30)
    here = status([D(g_a, ago=2900)], gens=[g_a, g_b], builder=g_b, held=g_b["uuid"])
    with open(os.path.join(fake, "local.status"), "w") as fh:
        json.dump(here, fh)
    with open(os.path.join(fake, "far.probe"), "w") as fh:
        fh.write(probe_text(status([D(g_a, ago=2900)], gens=[g_a], builder=g_a, main=C1), A, profile_ago=6000))
    m_a = G(10, C1, sp("p", "darwin-system"), ago=3000)
    with open(os.path.join(fake, "mac.probe"), "w") as fh:
        fh.write(probe_text(status([D(m_a, op="switch", ago=2900)], gens=[m_a], builder=m_a, main=C1),
                            m_a["out_path"], bk=None, ck=None, profile_ago=None, mode="switch"))

    write_exe(os.path.join(bindir, "ssh"), r'''
while [ $# -gt 0 ]; do
  case "$1" in -o) shift 2 ;; -t) shift ;; *) break ;; esac
done
alias=$1; shift
case "$*" in *@@booted*) ;; *) echo "ssh $alias $*" >>"$FAKE/log" ;; esac
if [ "$alias" = gone ]; then echo "ssh: connect to host gone port 22: No route to host" >&2; exit 255; fi
case "$*" in *@@booted*) cat "$FAKE/$alias.probe"; exit 0 ;; esac
FAKE_HOST=$alias exec sh -c "$*"
''')
    write_exe(os.path.join(bindir, "comin"), 'cat "$FAKE/local.status"\n')
    write_exe(os.path.join(bindir, "readlink"), r'''
case "$2" in
  /run/current-system) echo ''' + X + r''' ;;
  /run/booted-system) echo ''' + A + r''' ;;
  *) exit 1 ;;
esac
''')
    write_exe(os.path.join(bindir, "comin-deploy"), r'''
host=${FAKE_HOST:-local}
if [ "$1" = mode ] && [ $# = 1 ]; then echo manual; exit 0; fi
echo "$host comin-deploy $*" >>"$FAKE/log"
echo "fake comin-deploy on $host: $*"
if [ -e "$FAKE/$host.slow" ]; then sleep 60; fi
code=$(cat "$FAKE/$host.cdexit" 2>/dev/null || echo 0)
[ "$code" = 0 ] || echo "The deployment failed: fake error"
exit "$code"
''')
    write_exe(os.path.join(bindir, "sudo"), r'''
host=${FAKE_HOST:-local}
if [ "$1" = -n ] && [ -e "$FAKE/$host.password" ]; then echo "sudo: a password is required" >&2; exit 1; fi
echo "$host sudo $*" >>"$FAKE/log"
''')
    write_exe(os.path.join(bindir, "ghostty"), 'echo "ghostty $*" >>"$FAKE/log"\n')
    write_exe(os.path.join(bindir, "systemctl"), 'echo "${FAKE_HOST:-local} systemctl $*" >>"$FAKE/log"\n')
    gh = os.path.join(bindir, "fake-gh")
    write_exe(gh, r'''
echo "gh $*" >>"$FAKE/gh.log"
if [ -e "$FAKE/gh.broken" ]; then echo "gh: To get started with GitHub CLI, please run: gh auth login" >&2; exit 4; fi
case "$1 $2" in
  "api repos/o/r/git/matching-refs/heads/")
    echo '[{"ref":"refs/heads/master","object":{"sha":"''' + C3 + r'''"}},{"ref":"refs/heads/deploy","object":{"sha":"''' + C1 + r'''"}},{"ref":"refs/heads/testing-Nexus","object":{"sha":"''' + CT + r'''"}}]' ;;
  "run list") echo '[{"status":"completed","conclusion":"success","headSha":"''' + C3 + r'''","displayTitle":"t","url":"https://example.invalid/run/1","createdAt":"2026-11-16T11:00:00Z"}]' ;;
  "api repos/o/r/compare/"*) echo 4 ;;
  *) exit 1 ;;
esac
''')
    config = os.path.join(WORK, "config.json")
    with open(config, "w") as fh:
        json.dump({"repo": "o/r", "hosts": [
            {"label": "Here", "alias": "here", "darwin": False, "device": "desktop", "local": True},
            {"label": "Far", "alias": "far", "darwin": False, "device": "server", "local": False},
            {"label": "Mac", "alias": "mac", "darwin": True, "device": "laptop", "local": False},
            {"label": "Gone", "alias": "gone", "darwin": False, "device": "laptop", "local": False}]}, fh)

    env = {**os.environ, "FAKE": fake, "PATH": bindir + ":" + os.environ["PATH"]}

    def start(runtime, *extra):
        """A running helper: (process, its events so far, wait, send)."""
        proc = subprocess.Popen([HELPER, "--config", config, "--gh", gh, "--runtime", runtime, *extra],
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
        events, q = [], queue.Queue()

        def reader():
            for out in proc.stdout:
                q.put(json.loads(out))
            q.put(None)

        threading.Thread(target=reader, daemon=True).start()

        def wait(pred, timeout, what):
            end = time.monotonic() + timeout
            for e in events:
                if pred(e):
                    return e
            while time.monotonic() < end:
                try:
                    e = q.get(timeout=0.2)
                except queue.Empty:
                    continue
                if e is None:
                    break
                events.append(e)
                if pred(e):
                    return e
            check("helper " + what, False, f"not seen in {timeout} s")
            return None

        def send(**msg):
            proc.stdin.write(json.dumps(msg) + "\n")
            proc.stdin.flush()

        return proc, events, wait, send

    runtime = os.path.join(WORK, "rt")
    proc, events, wait, send = start(runtime)

    def logged(want=None):
        """The fakes' log; with `want`, once it holds that (Ghostty is
        started detached, so its line can come after the action's event)."""
        end = time.monotonic() + 5
        while True:
            with open(log) as fh:
                text = fh.read()
            if want is None or want in text or time.monotonic() > end:
                return text
            time.sleep(0.1)

    hello = wait(lambda e: e["event"] == "hello", 5, "hello")
    check("hello order", [h["host"] for h in hello["hosts"]] == ["Here", "Far", "Mac", "Gone"], hello)
    check("hello not read-only", hello["read_only"] is False, hello)
    wait(lambda e: e["event"] == "round" and e["state"] == "done", 20, "first round")
    rows = {e["host"]: e for e in events if e["event"] == "host"}
    check("helper Here pending", rows.get("Here", {}).get("chip", {}).get("id") == "pending", rows.get("Here"))
    check("helper Here hand", rows.get("Here", {}).get("runs", {}).get("source") == "hand", rows.get("Here"))
    check("helper Far up to date", rows.get("Far", {}).get("chip", {}).get("id") == "up-to-date", rows.get("Far"))
    check("helper Gone offline", rows.get("Gone", {}).get("chip", {}).get("id") == "offline", rows.get("Gone"))
    check("helper Gone reason", "No route to host" in rows.get("Gone", {}).get("lines", [{}])[0].get("text", ""), rows.get("Gone"))
    gh_ev = wait(lambda e: e["event"] == "github", 5, "github")
    check("helper github", gh_ev and gh_ev["state"] == "ok" and gh_ev["ahead"] == 4
          and gh_ev["testing_branches"] == ["testing-Nexus"] and gh_ev["run"]["conclusion"] == "success", gh_ev)

    # Refused: nothing may reach a fake.
    refusals = [
        ({"id": 1, "cmd": "switch", "host": "Far"}, "not-allowed"),
        ({"id": 2, "cmd": "switch", "host": "Here", "generation": uid(99)}, "stale"),
        ({"id": 3, "cmd": "switch", "host": "Here"}, "stale"),
        ({"id": 4, "cmd": "boot", "host": "Mac", "generation": uid(99)}, "not-allowed"),
        ({"id": 5, "cmd": "reboot", "host": "Gone"}, "not-allowed"),
        ({"id": 6, "cmd": "reboot", "host": "Mac"}, "not-allowed"),
        ({"id": 7, "cmd": "rm", "host": "Here"}, "unknown-command"),
        ({"id": 8, "cmd": "reboot", "host": "Elsewhere"}, "unknown-host"),
        ({"id": 9, "cmd": "mode", "host": "Mac", "value": "boot"}, "bad-value"),
        ({"id": 10, "cmd": "switch", "host": "Here", "argv": "rm -rf /"}, "bad-input"),
        ({"id": 11, "cmd": "boot", "host": "Here", "generation": "$(reboot)"}, "bad-input"),
        ({"id": 12, "cmd": "attach", "host": "Far"}, "no-session"),
        ({"id": 13, "cmd": "diff", "host": "Far"}, "not-allowed"),
    ]
    for msg, reason in refusals:
        send(**msg)
    for msg, reason in refusals:
        e = wait(lambda e, i=msg["id"]: e["event"] == "action" and e.get("id") == i, 5, f"refusal {msg['id']}")
        check(f"refused {msg}", e is not None and e["state"] == "refused" and e["reason"] == reason, e)
    proc.stdin.write("not json\n")
    proc.stdin.flush()
    wait(lambda e: e["event"] == "bad-input", 5, "bad-input")
    check("refused commands ran nothing", logged() == "", logged())

    # Switch on this machine, followed every 5 s until comin is idle 20 s.
    send(id=20, cmd="switch", host="Here", generation=g_b["uuid"])
    wait(lambda e: e["event"] == "action" and e.get("id") == 20 and e["state"] == "started", 10, "switch started")
    started = len(events)
    wait(lambda e: e["event"] == "host" and e["host"] == "Here" and e["chip"]["id"] == "deploying", 5, "Here deploying")
    done = wait(lambda e: e["event"] == "action" and e.get("id") == 20 and e["state"] in ("ok", "failed"), 15, "switch done")
    check("switch ok", done and done["state"] == "ok" and any("fake comin-deploy on local: switch " + g_b["uuid"] in x
                                                               for x in done["tail"]), done)
    check("switch command", f"local comin-deploy switch {g_b['uuid']}" in logged(), logged())
    wait(lambda e: e["event"] == "host" and e["host"] == "Here" and e["chip"]["id"] == "pending"
         and events.index(e) > started, 45, "follow ends when comin is idle")
    probes = [e for e in events[started:] if e["event"] == "probing" and e["host"] == "Here"]
    check("followed every 5 s", len(probes) >= 4, len(probes))

    send(id=21, cmd="attach", host="Here")
    wait(lambda e: e["event"] == "action" and e.get("id") == 21, 5, "attach")
    check("attach opens the session", "attach-session -t =Here" in logged("attach-session -t =Here"), logged())

    # Mode on another host, through ssh; a failing comin-deploy is reported.
    send(id=22, cmd="mode", host="Far", value="boot")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 22 and e["state"] in ("ok", "failed"), 15, "mode")
    check("mode ok", e and e["state"] == "ok", e)
    check("mode over ssh", "ssh far comin-deploy mode boot" in logged() and "far comin-deploy mode boot" in logged(), logged())
    open(os.path.join(fake, "far.cdexit"), "w").write("1\n")
    send(id=23, cmd="mode", host="Far", value="manual")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 23 and e["state"] in ("ok", "failed"), 15, "mode fails")
    check("mode failure reported", e and e["state"] == "failed" and e["exit"] == 1
          and any("fake error" in x for x in e["tail"]), e)

    # Reboot: sudo wants a password, so the session opens in Ghostty.
    open(os.path.join(fake, "far.password"), "w").close()
    send(id=24, cmd="reboot", host="Far")
    m = wait(lambda e: e["event"] == "message" and e["host"] == "Far", 15, "sudo message")
    check("sudo message", m and m["kind"] == "sudo-password", m)
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 24 and e["state"] in ("ok", "failed"), 15, "reboot")
    check("reboot ok", e and e["state"] == "ok", e)
    check("reboot sudo", "far sudo systemctl reboot" in logged()
          and "ghostty --title=Fleet: Far reboot" in logged("ghostty --title=Fleet: Far reboot"), logged())

    send(id=25, cmd="diff", host="Here")
    wait(lambda e: e["event"] == "action" and e.get("id") == 25, 5, "diff")
    check("diff in ghostty", "diff-closures /run/current-system \"$1\"" in logged("diff-closures") and B in logged(),
          logged())
    send(id=26, cmd="ssh", host="Far")
    wait(lambda e: e["event"] == "action" and e.get("id") == 26, 5, "ssh")
    check("ssh in ghostty", "ghostty --title=Fleet: Far -e ssh far" in logged("-e ssh far"), logged())

    # This machine reboots through logind, never sudo.
    send(id=27, cmd="reboot", host="Here")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 27 and e["state"] in ("ok", "failed"), 15,
             "local reboot")
    check("local reboot ok", e and e["state"] == "ok", e)
    check("local reboot without sudo", "local systemctl reboot" in logged() and "local sudo" not in logged(), logged())

    # GitHub failing is its own message; hosts are still read.
    open(os.path.join(fake, "gh.broken"), "w").close()
    mark = len(events)
    send(cmd="refresh")
    e = wait(lambda e: e["event"] == "github" and e["state"] == "error", 20, "github error")
    check("github error text", e and "gh auth login" in e["error"], e)
    wait(lambda e: e["event"] == "round" and e["state"] == "done" and events.index(e) > mark, 20, "round after github error")
    hosts = {e["host"] for e in events[mark:] if e["event"] == "host"}
    check("hosts read without github", hosts == {"Here", "Far", "Mac", "Gone"}, hosts)
    far = [e for e in events[mark:] if e["event"] == "host" and e["host"] == "Far"][-1]
    check("behind unknown without github", far["behind"] is None, far)

    proc.stdin.close()
    wait(lambda e: e["event"] == "exit", 10, "exit")
    proc.wait(10)
    subprocess.run([fleet_tmux(), "-S", os.path.join(runtime, "tmux.sock"), "kill-server"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # A helper restarted while an action still runs counts the host as busy:
    # the running session is neither replaced nor killed.
    os.unlink(os.path.join(fake, "far.cdexit"))
    open(os.path.join(fake, "far.slow"), "w").close()
    runtime = os.path.join(WORK, "rt-restart")
    tsock = [fleet_tmux(), "-S", os.path.join(runtime, "tmux.sock")]
    proc, events, wait, send = start(runtime)
    wait(lambda e: e["event"] == "round" and e["state"] == "done", 20, "restart: first round")
    send(id=40, cmd="mode", host="Far", value="boot")
    wait(lambda e: e["event"] == "action" and e.get("id") == 40 and e["state"] == "started", 10, "slow mode started")
    logged("far comin-deploy mode boot")
    proc.stdin.close()
    wait(lambda e: e["event"] == "exit", 10, "restart: exit")
    proc.wait(10)
    before = logged()
    proc, events, wait, send = start(runtime)
    wait(lambda e: e["event"] == "round" and e["state"] == "done", 20, "restart: round after restart")
    send(id=41, cmd="mode", host="Far", value="manual")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 41, 10, "restart: second action")
    check("restart: second action refused busy", e and e["state"] == "refused" and e["reason"] == "busy", e)
    check("restart: first session still there",
          subprocess.run([*tsock, "has-session", "-t", "=Far"], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL).returncode == 0)
    check("restart: nothing more ran", logged() == before, logged()[len(before):])
    proc.stdin.close()
    wait(lambda e: e["event"] == "exit", 10, "restart: second exit")
    proc.wait(10)
    subprocess.run([*tsock, "kill-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.unlink(os.path.join(fake, "far.slow"))

    # --read-only: rows as usual, every write refused before the gate, the
    # rest still works.
    before = logged()
    proc, events, wait, send = start(os.path.join(WORK, "rt-ro"), "--read-only")
    hello = wait(lambda e: e["event"] == "hello", 5, "read-only hello")
    check("hello read-only", hello and hello["read_only"] is True, hello)
    wait(lambda e: e["event"] == "round" and e["state"] == "done", 20, "read-only round")
    here = [e for e in events if e["event"] == "host" and e["host"] == "Here"]
    check("read-only still probes", here and here[-1]["chip"]["id"] == "pending", here)
    writes = [
        {"id": 30, "cmd": "switch", "host": "Here", "generation": g_b["uuid"]},
        {"id": 31, "cmd": "boot", "host": "Here", "generation": g_b["uuid"]},
        {"id": 32, "cmd": "mode", "host": "Far", "value": "manual"},
        {"id": 33, "cmd": "reboot", "host": "Far"},
        {"id": 34, "cmd": "reboot", "host": "Here"},
    ]
    for msg in writes:
        send(**msg)
    for msg in writes:
        e = wait(lambda e, i=msg["id"]: e["event"] == "action" and e.get("id") == i, 5, f"read-only {msg['id']}")
        check(f"read-only refuses {msg['cmd']} {msg['host']}", e and e["state"] == "refused"
              and e["reason"] == "read-only", e)
    send(id=35, cmd="diff", host="Here")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 35, 5, "read-only diff")
    check("read-only diff works", e and e["state"] == "ok", e)
    send(id=36, cmd="ssh", host="Far")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 36, 5, "read-only ssh")
    check("read-only ssh works", e and e["state"] == "ok", e)
    send(id=37, cmd="attach", host="Here")
    e = wait(lambda e: e["event"] == "action" and e.get("id") == 37, 5, "read-only attach")
    check("read-only attach not refused for read-only", e and e.get("reason") != "read-only", e)
    mark = len(events)
    send(cmd="open")
    send(cmd="refresh")
    wait(lambda e: e["event"] == "round" and e["state"] == "started" and events.index(e) >= mark, 10,
         "read-only refresh")
    end = time.monotonic() + 5
    while "-e ssh far" not in logged()[len(before):] and time.monotonic() < end:
        time.sleep(0.1)
    added = logged()[len(before):]
    check("read-only diff and ssh reach ghostty", "diff-closures" in added and "-e ssh far" in added, added)
    check("read-only ran nothing", not any(w in added for w in ("comin-deploy", "sudo", "systemctl")), added)
    proc.stdin.close()
    wait(lambda e: e["event"] == "exit", 10, "read-only exit")
    proc.wait(10)


def fleet_tmux():
    with open(HELPER) as fh:
        for text in fh:
            if text.startswith("TMUX = "):
                return json.loads(text.split("=", 1)[1].strip())
    raise SystemExit("no TMUX in the helper")


model_tests()
helper_tests()
if FAILURES:
    print(f"{len(FAILURES)} failures")
    sys.exit(1)
print("all fleet tests passed")
