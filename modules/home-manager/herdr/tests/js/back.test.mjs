import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mock } from "herdr";
import { MENU_PROBE, DIALOG_PROBE, RUN, sh, fields, parseStatus, backItem, plan, runArgs, failure, lastLine } from "../../lib/back.js";

// The scripts run for real: exec is sh/git in a throwaway repo, with no
// user or system git config.
let home;
const env = () => ({
  PATH: process.env.PATH, HOME: home, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: join(home, "gitconfig"),
  GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@t", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@t",
});
function git(cwd, ...args) {
  const r = spawnSync("git", args, { cwd, env: env(), encoding: "utf8" });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${r.stderr}`);
  return r.stdout.trim();
}
const commit = (cwd, file, text = file) => { writeFileSync(join(cwd, file), text); git(cwd, "add", file); git(cwd, "commit", "-qm", file); };

// A bare origin with master, cloned to work/ (origin/HEAD set) on branch feat.
function repo() {
  home = mkdtempSync(join(tmpdir(), "back-"));
  writeFileSync(join(home, "gitconfig"), "[init]\n\tdefaultBranch = master\n[advice]\n\tdetachedHead = false\n");
  git(home, "init", "-q", "--bare", "origin.git");
  git(home, "clone", "-q", "origin.git", "seed");
  const seed = join(home, "seed");
  commit(seed, "a");
  git(seed, "push", "-q", "origin", "master");
  git(home, "clone", "-q", "origin.git", "work");
  const work = join(home, "work");
  git(work, "switch", "-qc", "feat");
  return { seed, work };
}

beforeEach(() => {
  mock({
    exec: async (cmd, args, { cwd }) => {
      const r = spawnSync(cmd, args, { cwd, env: env(), encoding: "utf8" });
      return { code: r.status, stdout: r.stdout, stderr: r.stderr };
    },
  });
});

async function probe(cwd) {
  const r = await sh(DIALOG_PROBE, cwd, null);
  const [head, rest = ""] = r.stdout.split("--status--\n");
  return { f: fields(head), status: parseStatus(rest) };
}
const texts = (p) => p.lines.map((l) => `${l.tone}: ${l.text}`);
const run = async (cwd, p, choices) => sh(RUN, cwd, null, runArgs(p, { mode: "stash", message: "", del: true, keep: true, ...choices }));

test("merged and clean: says so, offers delete, and the run switches, fast-forwards and deletes", async () => {
  const { seed, work } = repo();
  commit(seed, "b");
  git(seed, "push", "-q", "origin", "master");
  git(work, "fetch", "-q");
  const { f, status } = await probe(work);
  assert.deepEqual([f.default, f.ref, f.repo, f.dbehind], ["master", "origin/master", "work", "1"]);
  const p = plan(f, status, null);
  assert.deepEqual(texts(p), ["ok: Everything on feat is on master.", "muted: Then fast-forwards master to origin."]);
  assert.deepEqual(p.del, { on: true, off: false, hint: "" });
  const r = await run(work, p);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(git(work, "symbolic-ref", "--short", "HEAD"), "master");
  assert.equal(git(work, "rev-parse", "HEAD"), git(work, "rev-parse", "origin/master"));
  assert.equal(git(work, "branch", "--list", "feat"), "");
});

test("uncommitted and untracked work is stashed under the default message", async () => {
  const { work } = repo();
  writeFileSync(join(work, "a"), "changed");
  writeFileSync(join(work, "new"), "x");
  const { f, status } = await probe(work);
  assert.deepEqual([status.changed, status.untracked], [1, 1]);
  const p = plan(f, status, null);
  assert.equal(texts(p)[0], "plain: 1 changed file and 1 untracked. Save them first:");
  const r = await run(work, p);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(fields(r.stdout).stashed, "1");
  assert.match(git(work, "stash", "list"), /herdr: feat/);
  assert.equal(git(work, "status", "--porcelain"), "");
});

test("a WIP commit stays on the branch and keeps it", async () => {
  const { work } = repo();
  writeFileSync(join(work, "new"), "x");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  const args = runArgs(p, { mode: "wip", message: "", del: true, keep: true });
  assert.equal(args[6], "", "no delete with a WIP commit");
  const r = await sh(RUN, work, null, args);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(git(work, "log", "-1", "--format=%s", "feat"), "WIP");
});

test("commits pushed nowhere: caution, delete off", async () => {
  const { work } = repo();
  commit(work, "c");
  commit(work, "d");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  assert.deepEqual(texts(p), ["caution: 2 commits aren’t pushed anywhere. They stay on the branch, on this machine only."]);
  assert.deepEqual(p.del, { on: false, off: true, hint: "not merged" });
});

test("an upstream pruned by the fetch is gone", async () => {
  const { work } = repo();
  commit(work, "c");
  git(work, "push", "-q", "-u", "origin", "feat");
  git(work, "push", "-q", "origin", "--delete", "feat");
  git(work, "fetch", "-q", "--prune");
  const { f, status } = await probe(work);
  assert.equal(f.gone, "1");
  assert.deepEqual(texts(plan(f, status, null)), ["caution: origin no longer has feat. Its 1 commit is on this machine only."]);
});

test("a merged PR that holds every commit allows delete; newer commits don't", () => {
  const f = { default: "master", branch: "feat", ahead: "2", unpushed: "0", remote: "1", origin: "1", local: "1", ref: "origin/master" };
  const covers = plan(f, parseStatus(""), { number: 412, covers: true });
  assert.deepEqual(texts(covers), ["ok: PR #412 is merged and holds every commit here."]);
  assert.deepEqual(covers.del, { on: true, off: false, hint: "PR merged" });
  const newer = plan(f, parseStatus(""), { number: 412, newer: 1 });
  assert.deepEqual(texts(newer), ["caution: PR #412 is merged, but 1 commit here is newer than it."]);
  assert.deepEqual(newer.del, { on: false, off: true, hint: "has newer commits" });
});

test("detached HEAD with commits on nothing keeps them on a new branch", async () => {
  const { work } = repo();
  git(work, "switch", "-q", "--detach");
  git(work, "branch", "-q", "-D", "feat");
  commit(work, "c");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  assert.equal(p.keep, `wip/${f.short}`);
  assert.equal(p.wipOff, true);
  assert.equal(p.del, null);
  assert.deepEqual(texts(p), ["blocked: 1 commit is on no branch or tag. After the switch only the reflog has it."]);
  const r = await run(work, p);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(git(work, "rev-parse", `wip/${f.short}`), f.head);
});

test("diverged local default: switches without fast-forwarding", async () => {
  const { seed, work } = repo();
  git(work, "switch", "-q", "master");
  commit(work, "local");
  git(work, "switch", "-q", "feat");
  commit(seed, "b");
  git(seed, "push", "-q", "origin", "master");
  git(work, "fetch", "-q");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  assert.equal(p.args.ff, "0");
  assert.ok(texts(p).includes("caution: Local master and origin/master have diverged. Switches without fast-forwarding."));
});

test("no local default: creates it from origin's", async () => {
  const { work } = repo();
  git(work, "branch", "-q", "-D", "master");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  assert.equal(p.args.create, "1");
  const r = await run(work, p);
  assert.equal(r.code, 0, r.stderr);
  assert.equal(git(work, "rev-parse", "--abbrev-ref", "master@{u}"), "origin/master");
});

test("a locked index stops the save: exit 10, nothing changed", async () => {
  const { work } = repo();
  writeFileSync(join(work, "new"), "x");
  const { f, status } = await probe(work);
  const p = plan(f, status, null);
  writeFileSync(join(work, ".git", "index.lock"), "");
  const r = await run(work, p);
  assert.equal(r.code, 10);
  const lines = failure(r.code, r.stderr, { p, mode: "stash", message: "herdr: feat", stashed: false, del: false, where: "feat" });
  assert.match(lines[0].text, /^Couldn’t stash: /);
  assert.equal(lines[1].text, "Nothing changed. Still on feat.");
});

test("a failing post-checkout hook: switched, then stopped with 13, branch kept", async () => {
  const { work } = repo();
  writeFileSync(join(work, ".git", "hooks", "post-checkout"), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
  const { f, status } = await probe(work);
  const r = await run(work, plan(f, status, null));
  assert.equal(r.code, 13);
  assert.equal(git(work, "symbolic-ref", "--short", "HEAD"), "master");
  assert.notEqual(git(work, "branch", "--list", "feat"), "");
});

test("menu probe: linked worktree, operation, conflicts, default in a worktree", async () => {
  const { work } = repo();
  git(work, "worktree", "add", "-q", join(home, "wt"), "master");
  let f = fields((await sh(MENU_PROBE, work, null)).stdout);
  assert.deepEqual([f.git, f.linked, f.branch, f.default, f.elsewhere], ["yes", "0", "feat", "master", join(home, "wt")]);
  assert.equal(backItem(f, { tabs: [] }).hint, "master is in a worktree");
  f = fields((await sh(MENU_PROBE, join(home, "wt"), null)).stdout);
  assert.equal(f.linked, "1");
  assert.equal(backItem(f, { tabs: [] }), null);

  writeFileSync(join(work, "a"), "feat side");
  git(work, "commit", "-qam", "feat a");
  git(join(home, "wt"), "switch", "-q", "--detach");
  git(work, "switch", "-q", "master");
  writeFileSync(join(work, "a"), "master side");
  git(work, "commit", "-qam", "master a");
  git(work, "switch", "-q", "feat");
  spawnSync("git", ["merge", "-q", "master"], { cwd: work, env: env() });
  f = fields((await sh(MENU_PROBE, work, null)).stdout);
  assert.deepEqual([f.op, f.conflicts], ["merge", "1"]);
  assert.equal(backItem(f, { tabs: [] }).hint, "merge in progress");

  f = fields((await sh(MENU_PROBE, home, null)).stdout);
  assert.equal(f.git, "none");
});

test("menu item: hidden on the default branch, and the first reason that applies", () => {
  const f = { git: "yes", linked: "0", branch: "feat", default: "master" };
  const blocked = { status: "blocked", tabs: [{ status: "blocked", working_since: 1 }] };
  const busy = { status: "done", tabs: [{ status: "done", working_since: null }, { status: "working", working_since: 1 }] };
  assert.equal(backItem({ ...f, branch: "master" }, { tabs: [] }), null);
  assert.deepEqual(backItem(f, { tabs: [] }), { label: "Back to master", hint: "" });
  assert.deepEqual(backItem({ ...f, default: "" }, { tabs: [] }), { label: "Back to default branch", hint: "no default branch" });
  assert.equal(backItem({ ...f, op: "rebase", conflicts: "1" }, blocked).hint, "rebase in progress");
  assert.equal(backItem({ ...f, conflicts: "1" }, blocked).hint, "unresolved conflicts");
  assert.equal(backItem(f, blocked).hint, "needs you");
  // space.status says "done" here; working_since still shows the working agent.
  assert.equal(backItem(f, busy).hint, "agent working");
});

test("status: submodule work is not counted as a change, a moved submodule commit is", () => {
  const s = parseStatus([
    "1 .M N... 100644 100644 100644 abc abc file.txt",
    "1 .M S.M. 160000 160000 160000 abc abc vendor/herdr",
    "1 M. SC.. 160000 160000 160000 abc def vendor/other",
    "? new file.txt",
    "u UU N... 100644 100644 100644 100644 a b c conflicted",
  ].join("\n"));
  assert.deepEqual(s, { changed: 2, untracked: 1, conflicts: true, submodules: ["vendor/herdr"] });
});

test("failure copy names where you are, the stash and the kept branch", () => {
  const p = { branch: "feat", short: "abc", target: "master", keep: null, args: { ref: "origin/master" } };
  assert.deepEqual(failure(12, "fatal: Not possible to fast-forward, aborting.\n", { p, mode: "stash", message: "herdr: feat", stashed: true, del: true, where: "master" }), [
    { text: "git merge --ff-only origin/master failed: Not possible to fast-forward, aborting.", tone: "blocked" },
    { text: "You are on master. Your changes are in stash “herdr: feat”. The branch is kept.", tone: "muted" },
  ]);
  assert.equal(lastLine("hint: x\nerror: cannot lock ref\n"), "cannot lock ref");
  // A failed fetch ends in advice; the fatal line is what went wrong.
  assert.equal(lastLine("fatal: '/x' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.\n"), "'/x' does not appear to be a git repository");
});
