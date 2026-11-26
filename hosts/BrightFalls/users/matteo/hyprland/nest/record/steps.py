"""Reads a desk-nest steps file: writes its caption track and prints the
actions `desk-nest record` plays, one per line, words separated by \\x1f:
<seconds>\\x1f<action>\\x1f<argument>...

usage: steps.py <steps> <track out>
Exits 1, naming the line, on anything it cannot read; nothing is written
then. The format is in README.md, "Recording a tour".
"""
import re
import shlex
import sys

# Action -> (fewest, most) arguments; None: no limit.
ACTIONS = {
    "caption": (2, None),
    "ipc": (2, None),
    "fixture": (2, 2),
    "set": (0, None),
    "keys": (1, None),
    "chord": (2, 2),
    "type": (1, None),
    "cursor": (1, 2),
    "lock": (0, 0),
    "stop": (0, 0),
    "scene": (1, 1),
    "click": (2, 3),
}
MODS = ("ctrl", "alt", "shift", "logo")


def number(word, where):
    try:
        x = float(word)
    except ValueError:
        sys.exit(f"{where}: not a number of seconds: {word}")
    if x != x or x in (float("inf"), float("-inf")):
        sys.exit(f"{where}: not a number of seconds: {word}")
    return x


def main():
    src, track_out = sys.argv[1], sys.argv[2]
    track, actions = [], []
    stopped = False
    with open(src) as f:
        for n, raw in enumerate(f, 1):
            where = f"{src}:{n}"
            # A caption's text is the rest of its line as written: quotes,
            # apostrophes and # are text, not shell syntax.
            m = re.match(r"\s*at\s+(\S+)\s+caption\s+(\S+)\s+(\S.*?)\s*$", raw)
            if m:
                t, dur = number(m[1], where), number(m[2], where)
                if stopped:
                    sys.exit(f"{where}: after stop")
                if actions and t < actions[-1][0]:
                    sys.exit(f"{where}: {t} s is before the line above")
                track.append(f"{t:g} {t + dur:g} {m[3]}")
                continue
            try:
                w = shlex.split(raw, comments=True)
            except ValueError as e:
                sys.exit(f"{where}: {e}")
            if not w:
                continue
            if w[0] == "pad" and len(w) == 3:
                number(w[1], where), number(w[2], where)
                track.append(shlex.join(w))
            elif w[0] in ("title", "end") and len(w) in (4, 5):
                number(w[1], where), number(w[2], where)
                track.append(shlex.join(w))
            elif w[0] == "at" and len(w) >= 3:
                t = number(w[1], where)
                act, args = w[2], w[3:]
                if act not in ACTIONS:
                    sys.exit(f"{where}: no action {act}; one of: {' '.join(ACTIONS)}")
                lo, hi = ACTIONS[act]
                if len(args) < lo or (hi is not None and len(args) > hi):
                    sys.exit(f"{where}: {act} takes {lo}{'' if hi == lo else ' or more' if hi is None else f' to {hi}'} arguments")
                if act == "chord" and args[0] not in MODS:
                    sys.exit(f"{where}: chord holds one of {', '.join(MODS)}, not {args[0]}")
                if act == "scene" and not re.fullmatch(r"[A-Za-z0-9_-]+", args[0]):
                    sys.exit(f"{where}: a scene name is letters, digits, _ and -")
                if act == "click" and not (all(a.isdigit() for a in args[:2]) and args[2:] in ([], ["left"], ["right"], ["middle"])):
                    sys.exit(f"{where}: click <x> <y> [left|right|middle]")
                if act == "cursor" and not (args in (["hide"], ["show"]) or (len(args) == 2 and all(a.isdigit() for a in args))):
                    sys.exit(f"{where}: cursor hide, cursor show or cursor <x> <y>")
                if any("\x1f" in a or "\n" in a for a in args):
                    sys.exit(f"{where}: a word holds a control character")
                if stopped:
                    sys.exit(f"{where}: after stop")
                if actions and t < actions[-1][0]:
                    sys.exit(f"{where}: {t} s is before the line above")
                actions.append((t, [act] + args))
                stopped = stopped or act == "stop"
            else:
                sys.exit(f"{where}: cannot read: {raw.strip()}")
    if not stopped:
        sys.exit(f"{src}: no `at <t> stop`: the recording would never end")
    with open(track_out, "w") as f:
        f.write("".join(l + "\n" for l in track))
    for t, words in actions:
        print("\x1f".join([f"{t:g}"] + words))


main()
