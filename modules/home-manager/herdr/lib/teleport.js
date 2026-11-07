// Teleport: moves a space's branch to a git worktree on another machine, with
// its uncommitted files if asked, and leaves this side on the default branch.
// Used by the `space-menu` (where it can go), the `teleport` dialog (doing it)
// and `space-cards` (the marks it leaves). See the herdr README.
//
// Every git transfer runs on this computer, over SSH to the other machine by
// its hc name (the SSH mesh's alias for it): a push to a remote target, a
// fetch from a remote source. So one side is always this computer.
//
// Marks, in each side's repo config, keyed by branch:
//   branch.<b>.herdrTeleportFrom = {"from","path","at","files"}  where it came from
//   branch.<b>.herdrTeleportTo   = {"to","path","at"}            where it went
// `from`/`to` are hc machine names, the computer that ran it under its own
// (`self`), so the marks read the same from any machine.

import { exec } from "herdr";

/** Runs git; never rejects on a git failure: { ok, out, err }. */
export async function git(cwd, args, on) {
  const r = await exec("git", args, { cwd, on });
  return { ok: r.code === 0, out: (r.stdout ?? "").trim(), err: (r.stderr || r.stdout || "").trim() };
}

async function must(step, result) {
  const r = await result;
  if (!r.ok) throw new Error(`${step}: ${r.err || "failed"}`);
  return r.out;
}

/** A branch name as a folder name, as the shipped worktree dialog makes them. */
export const slug = (branch) => branch.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");

/** `path` with `home` as ~. */
export const tilde = (path, home) => (home && (path === home || path.startsWith(home + "/")) ? `~${path.slice(home.length)}` : path);

/** The home folder of `on` (null: this computer). */
export async function homeOf(on) {
  const r = await exec("sh", ["-c", 'printf %s "$HOME"'], { on });
  if (r.code !== 0 || !r.stdout.trim()) throw new Error(`Couldn't find the home folder${on ? ` on ${on}` : ""}.`);
  return r.stdout.trim();
}

/** The repo at `folder` on `on`, or null outside git: { top, main, name, linked,
 *  branch (null when detached), base (the default branch: master/main), ahead
 *  (commits on top of it), files (uncommitted, untracked included), origin }. */
export async function repoOf(folder, on) {
  const top = await git(folder, ["rev-parse", "--show-toplevel"], on);
  const common = await git(folder, ["rev-parse", "--path-format=absolute", "--git-common-dir"], on);
  if (!top.ok || !common.ok) return null;
  const main = common.out.endsWith("/.git") ? common.out.slice(0, -5) : common.out;
  const branch = await git(top.out, ["symbolic-ref", "--short", "-q", "HEAD"], on);
  const head = await git(top.out, ["rev-parse", "--abbrev-ref", "origin/HEAD"], on);
  let base = head.ok ? head.out.replace(/^origin\//, "") : null;
  for (const b of base ? [] : ["master", "main"]) if ((await git(top.out, ["rev-parse", "--verify", "--quiet", `refs/heads/${b}`], on)).ok) { base = b; break; }
  const ahead = base ? await git(top.out, ["rev-list", "--count", `${head.ok ? head.out : base}..HEAD`], on) : null;
  const status = await git(top.out, ["--no-optional-locks", "status", "--porcelain"], on);
  const origin = await git(top.out, ["remote", "get-url", "origin"], on);
  return {
    top: top.out, main, name: main.split("/").pop(), linked: main !== top.out,
    branch: branch.ok && branch.out ? branch.out : null, base,
    ahead: ahead?.ok ? Number(ahead.out) || 0 : 0,
    files: status.ok ? status.out.split("\n").filter(Boolean).length : 0,
    origin: origin.ok ? origin.out : null,
  };
}

/** Whether `branch` can teleport: a branch, not the default one. */
export const movable = (repo) => Boolean(repo?.branch && repo.base && repo.branch !== repo.base);

/** The other side's clone of `repo`: the same path relative to home on `on`,
 *  with the same origin. { path, home } or null. */
export async function cloneOn(repo, fromHome, on) {
  if (!repo.origin || !(repo.main === fromHome || repo.main.startsWith(fromHome + "/"))) return null;
  const home = await homeOf(on);
  const path = home + repo.main.slice(fromHome.length);
  const origin = await git(path, ["remote", "get-url", "origin"], on).catch(() => ({ ok: false }));
  return origin.ok && origin.out === repo.origin ? { path, home } : null;
}

/** The worktree a teleport makes on the other side, as the shipped worktree
 *  dialog would place it, so the new space nests under its repo there. */
export const worktreePath = (home, repo, branch) => `${home}/.herdr/worktrees/${repo.name}/${slug(branch)}`;

/** Why a teleport can't go from `src` to `dst` (see teleport()), or null. */
export async function refusal(src, dst) {
  const list = await git(dst.repo, ["worktree", "list", "--porcelain"], dst.on);
  if (!list.ok) return list.err;
  if (list.out.split("\n").includes(`branch refs/heads/${src.repo.branch}`))
    return `${src.repo.branch} is already checked out on ${dst.label}.`;
  return null;
}

// The uncommitted files, untracked included, as a commit on top of HEAD; the
// working tree and the index are left as they are (a throwaway index).
const SNAPSHOT = `set -e
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp "$(git rev-parse --git-path index)" "$dir/index" 2>/dev/null || true
export GIT_INDEX_FILE="$dir/index"
git add -A
git commit-tree "$(git write-tree)" -p HEAD -m "herdr teleport: uncommitted files"`;

// Lays a snapshot's files over a fresh checkout and unstages them, so they
// arrive uncommitted (deletions included).
const APPLY = 'git read-tree -m -u HEAD "$1" && git reset -q';

const unset = (repo, key, on) => git(repo, ["config", "--unset", key], on);

/**
 * Moves `src.repo.branch` from `src` to a new worktree on `dst`.
 * src: { on, home, repo (repoOf), label }; dst: { on, home, repo (the clone's
 * path), label }; `bring`: carry the uncommitted files; `self`: this computer's
 * hc name, for the marks. Exactly one of src.on / dst.on is null (this computer).
 *
 * Nothing changes on `src` until `dst` has the worktree: a failure before that
 * throws with `src` as it was. After it, src's uncommitted files go to a stash
 * (`herdr-teleport <branch>`) when they were carried or would be lost, and its
 * checkout goes back to the default branch, or a linked worktree is removed
 * (`closeSource` is called first, to close its space). Problems there come
 * back in `warnings`: the teleport itself has happened.
 * Returns { worktree, warnings }.
 */
export async function teleport({ src, dst, bring, self, closeSource = () => {}, now = () => new Date().toISOString() }) {
  const { branch } = src.repo;
  const ref = `refs/herdr/teleport/${branch}`;
  const carry = bring && src.repo.files > 0;
  const worktree = worktreePath(dst.home, src.repo, branch);
  const sshPath = (side, path) => `${side.on}:${path.slice(side.home.length + 1)}`;

  const snap = carry ? await must("Snapshot", exec("sh", ["-c", SNAPSHOT], { cwd: src.repo.top, on: src.on }).then((r) => ({ ok: r.code === 0, out: r.stdout.trim(), err: r.stderr.trim() }))) : null;
  const refs = [`refs/heads/${branch}:refs/heads/${branch}`, ...(snap ? [`${ref}:${ref}`] : [])];
  if (snap) await must("Snapshot", git(src.repo.top, ["update-ref", ref, snap], src.on));
  try {
    // Fast-forward only: a branch with commits there that this one lacks is refused.
    const moved = src.on
      ? await git(dst.repo, ["fetch", sshPath(src, src.repo.main), ...refs], null)
      : await git(src.repo.top, ["push", "--atomic", sshPath(dst, dst.repo), ...refs], null);
    if (!moved.ok)
      throw new Error(/rejected|non-fast-forward/.test(moved.err) ? `${dst.label}'s ${branch} has commits this one lacks. Bring them together first.` : `Sending ${branch}: ${moved.err}`);
  } finally {
    if (snap) await git(src.repo.top, ["update-ref", "-d", ref], src.on);
  }

  const added = await git(dst.repo, ["worktree", "add", worktree, branch], dst.on);
  if (!added.ok) {
    if (snap) await git(dst.repo, ["update-ref", "-d", ref], dst.on);
    throw new Error(`Making the worktree on ${dst.label}: ${added.err}`);
  }
  const warnings = [];
  if (snap) {
    const applied = await exec("sh", ["-c", APPLY, "sh", ref], { cwd: worktree, on: dst.on });
    if (applied.code !== 0) warnings.push(`The uncommitted files didn't apply on ${dst.label} (${applied.stderr.trim()}); they stay in the stash here.`);
    await git(dst.repo, ["update-ref", "-d", ref], dst.on);
  }
  await git(dst.repo, ["config", `branch.${branch}.herdrTeleportFrom`, JSON.stringify({ from: src.on ?? self, path: src.repo.top, at: now(), files: carry ? src.repo.files : 0 })], dst.on);
  await unset(dst.repo, `branch.${branch}.herdrTeleportTo`, dst.on);

  // This side, now that the other has it.
  const here = (step, r) => r.then((r) => { if (!r.ok) warnings.push(`${step} here: ${r.err}`); return r.ok; });
  const stashed = src.repo.files > 0 && (carry || src.repo.linked)
    ? await here("Stashing", git(src.repo.top, ["stash", "push", "--include-untracked", "-m", `herdr-teleport ${branch}`], src.on))
    : true;
  if (src.repo.linked) {
    if (stashed) {
      closeSource();
      await here("Removing the worktree", git(src.repo.main, ["worktree", "remove", src.repo.top], src.on));
    }
  } else {
    await here(`Switching to ${src.repo.base}`, git(src.repo.top, ["switch", src.repo.base], src.on));
  }
  await git(src.repo.main, ["config", `branch.${branch}.herdrTeleportTo`, JSON.stringify({ to: dst.on ?? self, path: worktree, at: now() })], src.on);
  await unset(src.repo.main, `branch.${branch}.herdrTeleportFrom`, src.on);
  return { worktree, warnings };
}

/** The marks in `git config --get-regexp` output for herdrTeleport keys:
 *  { from: { branch: mark }, to: { branch: mark } }. */
export function parseMarks(out) {
  const marks = { from: {}, to: {} };
  for (const line of (out ?? "").split("\n")) {
    const m = /^branch\.(.+)\.herdrteleport(from|to) (.*)$/i.exec(line);
    if (!m) continue;
    try { marks[m[2].toLowerCase()][m[1]] = JSON.parse(m[3]); } catch {}
  }
  return marks;
}

/** git config args that read every mark (for parseMarks). */
export const MARKS = ["config", "--get-regexp", "^branch\\..*\\.herdrteleport(from|to)$"];
