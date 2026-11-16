// Going back to a repo's default branch: what the space menu's item and the
// back-to-master dialog ask git, and what they make of the answers. Each probe
// is one `sh -c`, so a remote space costs one round trip. No drawing here, so
// Node tests can load it.

import { exec } from "herdr";

/** `key=value` lines as an object; later keys win. */
export function fields(text) {
  const out = {};
  for (const line of text.split("\n")) {
    const at = line.indexOf("=");
    if (at > 0) out[line.slice(0, at)] = line.slice(at + 1);
  }
  return out;
}

// The default branch: origin/HEAD, else origin's master or main, else a local
// master or main (a repo with no remote).
const DEFAULT = `
d=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); d=\${d#origin/}
if [ -z "$d" ]; then for b in master main; do git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null && { d=$b; break; }; done; fi
if [ -z "$d" ]; then for b in master main; do git rev-parse -q --verify "refs/heads/$b" >/dev/null && { d=$b; break; }; done; fi
echo "default=$d"
`;

/** What the menu needs: git=none outside a repo; else linked, branch (empty:
 *  detached), short, repo (its name), op (a rebase, merge, cherry-pick, revert or bisect under way),
 *  conflicts, default, and elsewhere (the worktree that has the default
 *  branch checked out, if not this one). */
export const MENU_PROBE = `
gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || { echo git=none; exit 0; }
echo git=yes
top=$(git rev-parse --show-toplevel)
[ "$(git rev-parse --path-format=absolute --git-common-dir)" = "$top/.git" ] && echo linked=0 || echo linked=1
echo "branch=$(git symbolic-ref -q --short HEAD)"
echo "short=$(git rev-parse --short HEAD)"
common=$(git rev-parse --path-format=absolute --git-common-dir); [ "\${common##*/}" = .git ] && common=\${common%/.git}
echo "repo=\${common##*/}"
if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then echo op=rebase
elif [ -f "$gd/MERGE_HEAD" ]; then echo op=merge
elif [ -f "$gd/CHERRY_PICK_HEAD" ]; then echo op=cherry-pick
elif [ -f "$gd/REVERT_HEAD" ]; then echo op=revert
elif [ -f "$gd/BISECT_LOG" ]; then echo op=bisect
fi
[ -n "$(git ls-files -u | head -n 1)" ] && echo conflicts=1
${DEFAULT}
[ -n "$d" ] && git worktree list --porcelain | awk -v t="$top" -v b="refs/heads/$d" '/^worktree /{p=substr($0,10)} $0=="branch " b && p!=t {print "elsewhere=" p}'
exit 0
`;

/** What the dialog needs after its fetch: MENU_PROBE's fields plus remote,
 *  head, ref (what the default branch is compared with), origin
 *  (origin has it), local (a local one exists), dahead/dbehind (local
 *  against origin's), ahead (commits here not on ref), unpushed, gone (the
 *  upstream was pruned), orphans (detached: commits on no branch, tag or
 *  remote), then `--status--` and `git status --porcelain=v2`. */
export const DIALOG_PROBE = `${MENU_PROBE.replace(/exit 0\n$/, "")}
git remote get-url origin >/dev/null 2>&1 && echo remote=1
echo "head=$(git rev-parse HEAD)"
b=$(git symbolic-ref -q --short HEAD)
if [ -n "$d" ]; then
  ref=$d
  if git rev-parse -q --verify "refs/remotes/origin/$d" >/dev/null; then ref=origin/$d; echo origin=1; fi
  echo "ref=$ref"
  if git rev-parse -q --verify "refs/heads/$d" >/dev/null; then
    echo local=1
    [ "$ref" = "origin/$d" ] && git rev-list --left-right --count "refs/heads/$d...refs/remotes/origin/$d" | awk '{print "dahead=" $1; print "dbehind=" $2}'
  fi
  echo "ahead=$(git rev-list --count "$ref..HEAD")"
fi
if [ -n "$b" ]; then
  echo "unpushed=$(git rev-list --count HEAD --not --remotes)"
  [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$b")" = "[gone]" ] && echo gone=1
else
  echo "orphans=$(git rev-list --count HEAD --not --branches --tags --remotes)"
fi
echo --status--
git --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --untracked-files=all
`;

/** The fetch the dialog opens with: exit=124 when it took over 25 s. `timeout`
 *  isn't on every Mac, so without it the fetch runs unbounded and `exec`'s
 *  own 30 s limit is what stops it. */
export const FETCH = `
if command -v timeout >/dev/null 2>&1; then GIT_TERMINAL_PROMPT=0 timeout 25 git fetch --prune --quiet origin
else GIT_TERMINAL_PROMPT=0 git fetch --prune --quiet origin; fi
echo "exit=$?"
`;

/** Saves, switches, fast-forwards and deletes in one exec: closing the dialog
 *  ends its tasks but not a running exec, so nothing after this may matter.
 *  Args: mode (stash|wip|none), stash message, default, ref, create (1: make
 *  the local default from ref), ff (1), branch to delete, branch to keep a
 *  detached HEAD on. Prints stashed=1 when a stash was made. Exits 10 save,
 *  11 switch, 12 fast-forward, 13 hook (switched, then stopped), 14 delete,
 *  15 keep. */
export const RUN = `
mode=$1 msg=$2 d=$3 ref=$4 create=$5 ff=$6 del=$7 keep=$8
if [ -n "$keep" ]; then git branch "$keep" HEAD || exit 15; fi
case $mode in
  stash)
    before=$(git rev-parse -q --verify refs/stash)
    git stash push -u -m "$msg" >/dev/null || exit 10
    [ "$(git rev-parse -q --verify refs/stash)" != "$before" ] && echo stashed=1 ;;
  wip) { git add -A && git -c commit.gpgsign=false commit -q --no-verify -m WIP; } || exit 10 ;;
esac
if [ "$create" = 1 ]; then git switch -q -c "$d" --track "$ref"; else git switch -q "$d"; fi
if [ $? -ne 0 ]; then [ "$(git symbolic-ref -q --short HEAD)" = "$d" ] && exit 13; exit 11; fi
if [ "$ff" = 1 ]; then git merge -q --ff-only "$ref" || exit 12; fi
if [ -n "$del" ]; then git branch -q -D "$del" || exit 14; fi
exit 0
`;

/** Runs a probe script in `cwd` on `on`: { code, stdout, stderr }. Rejects
 *  when the machine is away or has no `sh`. */
export const sh = (script, cwd, on, args = []) => exec("sh", ["-c", script, "sh", ...args], { cwd, on });

/** What git said went wrong: its first `fatal:` or `error:` line (the advice
 *  after it is no use in one line), else its last line; prefix dropped. */
export function lastLine(text) {
  const lines = (text ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
  const said = lines.find((l) => /^(fatal|error):/.test(l)) ?? lines.at(-1) ?? "";
  return said.replace(/^(error|fatal):\s*/, "");
}

/** `git status --porcelain=v2` as { changed, untracked, conflicts,
 *  submodules }: changed counts tracked paths (a submodule whose commit
 *  moved counts; its own uncommitted work doesn't, it's in `submodules`). */
export function parseStatus(text) {
  const out = { changed: 0, untracked: 0, conflicts: false, submodules: [] };
  for (const line of text.split("\n")) {
    if (line.startsWith("? ")) out.untracked++;
    else if (line.startsWith("u ")) out.conflicts = true;
    else if (line.startsWith("1 ") || line.startsWith("2 ")) {
      const parts = line.split(" ");
      const sub = parts[2];
      const path = (line.startsWith("1 ") ? parts.slice(8) : parts.slice(9)).join(" ").split("\t")[0];
      if (!sub.startsWith("S")) out.changed++;
      else {
        if (sub[1] === "C") out.changed++;
        if (sub[2] === "M" || sub[3] === "U") out.submodules.push(path);
      }
    }
  }
  return out;
}

/** Whether an agent in the space waits on the person, and whether one is working. */
export const needsYou = (space) => space.status === "blocked" || (space.tabs ?? []).some((t) => t.status === "blocked");
export const working = (space) => (space.tabs ?? []).some((t) => t.working_since != null);

/** The space menu's item from MENU_PROBE's fields and the space: null when
 *  hidden (not git, a linked worktree, already on the default branch), else
 *  { label, hint } with hint "" when it can run. */
export function backItem(f, space) {
  if (f.git !== "yes" || f.linked === "1") return null;
  if (f.default && f.branch === f.default) return null;
  const label = f.default ? `Back to ${f.default}` : "Back to default branch";
  const hint = !f.default
    ? "no default branch"
    : f.op
      ? `${f.op} in progress`
      : f.conflicts
        ? "unresolved conflicts"
        : needsYou(space)
          ? "needs you"
          : working(space)
            ? "agent working"
            : f.elsewhere
              ? `${f.default} is in a worktree`
              : "";
  return { label, hint };
}

const count = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const num = (v) => Number(v) || 0;

/** The dialog's content from DIALOG_PROBE's fields, the parsed status and
 *  the PR check ({ number, covers, newer } or null):
 *  { target, branch, short, lines: [{ text, tone }], save, submodulesOnly,
 *    wipOff, del: { on, off, hint } | null, keep (branch name) | null,
 *    args (RUN's, but mode and message) }.
 *  tone: "ok" | "caution" | "blocked" | "muted" | "plain". */
export function plan(f, status, pr) {
  const D = f.default, B = f.branch || null;
  const ahead = num(f.ahead), unpushed = num(f.unpushed), orphans = num(f.orphans);
  const dahead = num(f.dahead), dbehind = num(f.dbehind);
  const lines = [];
  const say = (text, tone = "plain") => lines.push({ text, tone });
  const { changed, untracked } = status;
  const save = changed + untracked > 0;
  if (save) {
    const what = changed && untracked ? `${count(changed, "changed file")} and ${untracked} untracked` : changed ? count(changed, "changed file") : count(untracked, "untracked file");
    say(`${what}. Save ${changed + untracked === 1 ? "it" : "them"} first:`);
  }
  for (const s of status.submodules) say(`Submodule ${s} has uncommitted changes. Neither choice saves them; they stay in the submodule.`, "caution");
  const merged = ahead === 0;
  if (B) {
    const are = (n) => (n === 1 ? "isn’t" : "aren’t");
    if (merged) say(`Everything on ${B} is on ${D}.`, "ok");
    else if (pr?.covers) say(f.gone ? `PR #${pr.number} is merged and origin no longer has ${B}.` : `PR #${pr.number} is merged and holds every commit here.`, "ok");
    else if (pr?.newer) say(`PR #${pr.number} is merged, but ${count(pr.newer, "commit")} here ${pr.newer === 1 ? "is" : "are"} newer than it.`, "caution");
    else if (f.gone && unpushed > 0) say(`origin no longer has ${B}. ${unpushed === 1 ? "Its 1 commit is" : `Its ${unpushed} commits are`} on this machine only.`, "caution");
    else if (unpushed > 0) say(`${count(unpushed, "commit")} ${are(unpushed)} pushed anywhere. ${unpushed === 1 ? "It stays" : "They stay"} on the branch, on this machine only.`, "caution");
    else say(`${count(ahead, "commit")} ${are(ahead)} on ${D}. The branch keeps ${ahead === 1 ? "it" : "them"}.`, "caution");
  } else if (orphans > 0) say(`${count(orphans, "commit")} ${orphans === 1 ? "is" : "are"} on no branch or tag. After the switch only the reflog has ${orphans === 1 ? "it" : "them"}.`, "blocked");
  else if (merged) say(`${f.short} is already on ${D}.`, "ok");
  else say(`${f.short} is on another branch or tag. Nothing to keep.`, "muted");
  const create = !f.local && Boolean(f.origin);
  const diverged = dahead > 0 && dbehind > 0;
  const ff = Boolean(f.local && f.origin) && dbehind > 0 && !diverged;
  if (!f.remote) say("No remote: switches only, nothing fetched.", "muted");
  else if (create) say(`No local ${D}: creates it from origin/${D}.`, "muted");
  else if (diverged) say(`Local ${D} and origin/${D} have diverged. Switches without fast-forwarding.`, "caution");
  else if (ff) say(`Then fast-forwards ${D} to origin.`, "muted");
  const deletable = merged || Boolean(pr?.covers);
  const del = B ? { on: deletable, off: !deletable, hint: !deletable ? (pr?.newer ? "has newer commits" : "not merged") : !merged ? "PR merged" : "" } : null;
  const keep = !B && orphans > 0 ? `wip/${f.short}` : null;
  return {
    target: D, branch: B, short: f.short, lines, save, wipOff: !B, del, keep,
    args: { d: D, ref: f.ref, create: create ? "1" : "0", ff: ff ? "1" : "0" },
  };
}

/** RUN's arguments for a plan and the person's choices. */
export function runArgs(p, { mode, message, del, keep }) {
  const m = p.save ? mode : "none";
  const msg = (message ?? "").trim() || `herdr: ${p.branch ?? p.short}`;
  const delBranch = p.del && del && !(m === "wip") ? p.branch : "";
  return [m, msg, p.args.d, p.args.ref, p.args.create, p.args.ff, delBranch, p.keep && keep ? p.keep : ""];
}

/** What a failed RUN means, by exit code: { lines: [{ text, tone }] }.
 *  `stashed`: RUN said it made a stash; `where`: the branch git reports now. */
export function failure(code, stderr, { p, mode, message, stashed, del, where }) {
  const err = lastLine(stderr);
  const B = p.branch ?? p.short, D = p.target;
  const saved = stashed ? `Your changes are in stash “${message}”.` : mode === "wip" ? `Your changes are in a WIP commit on ${B}.` : "";
  const kept = del ? " The branch is kept." : "";
  const here = where ? `You are on ${where}.` : "";
  const join = (...parts) => parts.filter(Boolean).join(" ");
  switch (code) {
    case 10: return [{ text: `Couldn’t ${mode === "wip" ? "commit" : "stash"}: ${err}`, tone: "blocked" }, { text: `Nothing changed. Still on ${B}.`, tone: "muted" }];
    case 15: return [{ text: `Couldn’t create ${p.keep}: ${err}`, tone: "blocked" }, { text: `Nothing changed. Still on ${B}.`, tone: "muted" }];
    case 11: return [{ text: `git switch failed: ${err}`, tone: "blocked" }, { text: join(here || `Still on ${B}.`, saved), tone: "muted" }];
    case 12: return [{ text: `git merge --ff-only ${p.args.ref} failed: ${err}`, tone: "blocked" }, { text: join(here || `You are on ${D}.`, saved, kept.trim()), tone: "muted" }];
    case 13: return [{ text: `post-checkout hook failed: ${err || "exit 1"}`, tone: "blocked" }, { text: join(here || `You are on ${D}.`, saved, kept.trim()), tone: "muted" }];
    case 14: return [{ text: `On ${D}.`, tone: "ok" }, { text: `Deleting ${B} failed: ${err}. The branch is kept.`, tone: "caution" }];
    default: return [{ text: `git failed: ${err || `exit ${code}`}`, tone: "blocked" }, { text: join(here, saved), tone: "muted" }];
  }
}
