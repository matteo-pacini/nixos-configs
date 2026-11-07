// What git says about a folder, as the sidebar rows and the status bar show
// it: its repo, branch, and how far it is from the repo's default branch.

import { exec } from "herdr";

const base = (path) => path.replace(/\/+$/, "").split("/").pop();

/** The checkout at `cwd` on `on` (null: this computer):
 *  { info } with info = { name, branch (null: detached), ahead, behind, repo,
 *    top (the checkout's root), linked (a linked worktree) }, { none: true } when git says it isn't a repo, or
 *  { unsure: true } when git couldn't answer (ask again later).
 *  `repo` is JSON [on, git common dir]: the same for every checkout of one
 *  repo on one machine. `ahead`/`behind` count against origin's default
 *  branch (else origin/master, origin/main, else the branch's upstream), as
 *  fresh as the checkout's last fetch. Rejects when `exec` can't run (the
 *  machine is away). */
export async function gitInfo(cwd, on) {
  // No optional locks, no fsmonitor: writes nothing under .git, so a watch on
  // the folder doesn't wake on its own look.
  const r = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch"], { cwd, on });
  if (r.code !== 0) return /not a git repository/i.test(r.stderr) ? { none: true } : { unsure: true };
  const top = (await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on })).stdout.trim();
  const common = (await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on })).stdout.trim();
  const name = common.endsWith("/.git") ? base(common.slice(0, -5)) : base(common).replace(/\.git$/, "");
  const info = { name, branch: null, ahead: 0, behind: 0, repo: JSON.stringify([on, common]), top, linked: common !== `${top}/.git` };
  for (const line of r.stdout.split("\n")) {
    if (line.startsWith("# branch.head ")) info.branch = line.slice(14) === "(detached)" ? null : line.slice(14);
    else if (line.startsWith("# branch.ab ")) {
      const [a, b] = line.slice(12).split(" ");
      info.ahead = Math.abs(parseInt(a, 10)) || 0;
      info.behind = Math.abs(parseInt(b, 10)) || 0;
    }
  }
  const head = await exec("git", ["rev-parse", "--abbrev-ref", "origin/HEAD"], { cwd, on });
  let main = head.code === 0 ? head.stdout.trim() : null;
  for (const ref of main ? [] : ["origin/master", "origin/main"]) {
    if ((await exec("git", ["rev-parse", "--verify", "--quiet", ref], { cwd, on })).code === 0) { main = ref; break; }
  }
  if (main) {
    const ab = await exec("git", ["rev-list", "--left-right", "--count", `${main}...HEAD`], { cwd, on });
    if (ab.code === 0) {
      const [behind, ahead] = ab.stdout.trim().split(/\s+/).map((n) => parseInt(n, 10) || 0);
      Object.assign(info, { ahead, behind });
    }
  }
  return { info };
}

/** Whether `branch` is a repo's default one, which rows and the bar leave unnamed. */
export const plain = (branch) => branch === "master" || branch === "main";

/** The origin remote's URL of the checkout at `cwd`, or null. */
export async function origin(cwd, on) {
  const r = await exec("git", ["remote", "get-url", "origin"], { cwd, on });
  return r.code === 0 ? r.stdout.trim() : null;
}
