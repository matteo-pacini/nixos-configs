import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { teleport, parseMarks, slug, tilde, worktreePath, movable } from "../../lib/teleport.js";

const repo = { top: "/h/r", main: "/h/r", name: "r", linked: false, branch: "feat/x", base: "master", ahead: 2, files: 3, origin: "o" };
const src = (over = {}) => ({ on: null, home: "/h", repo: { ...repo, ...over }, label: "BrightFalls" });
const dst = { on: "nexus", home: "/n", repo: "/n/r", label: "Nexus" };
const at = () => "2026-11-07T09:00:00Z";

// exec answering git by its subcommand (`fail` makes that one fail), and `sh`
// scripts (snapshot, apply) with `snap`. Every call lands in `calls`.
function world({ fail = [] } = {}) {
  mock({
    exec: async (cmd, args, opts) => {
      if (cmd === "sh") return { code: 0, stdout: "snap123\n", stderr: "" };
      const sub = args.find((a) => !a.startsWith("-"));
      if (fail.includes(sub)) return { code: 1, stdout: "", stderr: sub === "push" ? "! [rejected] feat/x -> feat/x (non-fast-forward)" : `${sub} broke` };
      return { code: 0, stdout: "", stderr: "" };
    },
  });
}
const gits = () => calls.filter(([, cmd]) => cmd === "git").map(([, , args, opts]) => ({ args, on: opts.on ?? null }));
// Calls of one git subcommand (its first non-option argument), on one side if given.
const ran = (sub, on) => gits().filter((g) => g.args.find((a) => !a.startsWith("-")) === sub && (on === undefined || g.on === on));

test("local → remote: snapshot, push, worktree there, then stash and switch here", async () => {
  world();
  const r = await teleport({ src: src(), dst, bring: true, self: "brightfalls", now: at });
  assert.equal(r.worktree, "/n/.herdr/worktrees/r/feat-x");
  assert.deepEqual(r.warnings, []);
  const order = gits().map((g) => `${g.on ?? "here"} ${g.args.slice(0, 2).join(" ")}`);
  const pos = (s) => order.findIndex((o) => o.startsWith(s));
  // Nothing changes here until the worktree exists there.
  assert.ok(pos("here push") < pos("nexus worktree add"));
  assert.ok(pos("nexus worktree add") < pos("here stash push"));
  assert.ok(pos("here stash push") < pos("here switch master"));
  const push = ran("push")[0].args;
  assert.deepEqual(push.slice(0, 3), ["push", "--atomic", "nexus:r"]);
  assert.ok(push.includes("refs/herdr/teleport/feat/x:refs/herdr/teleport/feat/x"));
  // The snapshot ref goes on both sides.
  assert.equal(ran("update-ref").filter((g) => g.args.includes("-d")).length, 2);
});

test("marks name both machines, this one by its own name", async () => {
  world();
  await teleport({ src: src(), dst, bring: true, self: "brightfalls", now: at });
  const config = Object.fromEntries(ran("config").filter((g) => !g.args.includes("--unset")).map((g) => [g.args[1], JSON.parse(g.args[2])]));
  assert.deepEqual(config["branch.feat/x.herdrTeleportFrom"], { from: "brightfalls", path: "/h/r", at: at(), files: 3 });
  assert.deepEqual(config["branch.feat/x.herdrTeleportTo"], { to: "nexus", path: "/n/.herdr/worktrees/r/feat-x", at: at() });
});

test("remote → local fetches here instead of pushing", async () => {
  world();
  await teleport({ src: { on: "nexus", home: "/n", repo: { ...repo, top: "/n/wt", main: "/n/r", linked: true }, label: "Nexus" },
    dst: { on: null, home: "/h", repo: "/h/r", label: "BrightFalls" }, bring: false, self: "brightfalls", now: at });
  assert.equal(ran("push").length, 0);
  const fetch = ran("fetch")[0];
  assert.equal(fetch.on, null);
  assert.equal(fetch.args[1], "nexus:r");
});

test("a refused push leaves this side as it was", async () => {
  world({ fail: ["push"] });
  await assert.rejects(teleport({ src: src(), dst, bring: true, self: "brightfalls", now: at }), /Nexus's feat\/x has commits this one lacks/);
  assert.equal(ran("stash").length + ran("switch").length + ran("worktree").length, 0);
  assert.equal(ran("update-ref", null).filter((g) => g.args.includes("-d")).length, 1, "snapshot ref removed here");
});

test("a failed worktree add there leaves this side as it was", async () => {
  world({ fail: ["worktree"] });
  await assert.rejects(teleport({ src: src(), dst, bring: true, self: "brightfalls", now: at }), /Making the worktree on Nexus: worktree broke/);
  assert.equal(ran("stash").length + ran("switch").length, 0);
  assert.equal(ran("update-ref", "nexus").filter((g) => g.args.includes("-d")).length, 1, "snapshot ref removed there");
});

test("committed work only: no snapshot, files stay here", async () => {
  world();
  await teleport({ src: src(), dst, bring: false, self: "brightfalls", now: at });
  assert.equal(calls.filter(([, cmd]) => cmd === "sh").length, 0);
  assert.equal(ran("stash").length, 0);
  assert.equal(ran("switch").length, 1);
});

test("a linked worktree here is stashed, closed and removed, not switched", async () => {
  world();
  let closed = false;
  await teleport({ src: src({ top: "/h/wt", linked: true }), dst, bring: false, self: "brightfalls", now: at, closeSource: () => (closed = true) });
  assert.equal(closed, true);
  assert.equal(ran("stash").length, 1, "files that would be lost are stashed");
  assert.deepEqual(ran("worktree", null).map((g) => g.args), [["worktree", "remove", "/h/wt"]]);
  assert.equal(ran("switch").length, 0);
});

test("trouble here after the move is a warning, not a failure", async () => {
  world({ fail: ["switch"] });
  const r = await teleport({ src: src(), dst, bring: true, self: "brightfalls", now: at });
  assert.match(r.warnings[0], /^Switching to master here: switch broke/);
});

test("parseMarks reads both kinds, branch names with slashes and dots", () => {
  const marks = parseMarks([
    'branch.feat/a.b.herdrteleportfrom {"from":"nexus"}',
    'branch.x.herdrteleportto {"to":"brightfalls"}',
    "branch.y.herdrteleportto not-json",
  ].join("\n"));
  assert.deepEqual(marks, { from: { "feat/a.b": { from: "nexus" } }, to: { x: { to: "brightfalls" } } });
});

test("helpers", () => {
  assert.equal(slug("feat/teleport as worktree"), "feat-teleport-as-worktree");
  assert.equal(tilde("/home/m/x", "/home/m"), "~/x");
  assert.equal(tilde("/home/mx", "/home/m"), "/home/mx");
  assert.equal(worktreePath("/n", repo, "feat/x"), "/n/.herdr/worktrees/r/feat-x");
  assert.equal(movable(repo), true);
  assert.equal(movable({ ...repo, branch: "master" }), false);
  assert.equal(movable({ ...repo, branch: null }), false);
});
