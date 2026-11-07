import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mock, calls } from "herdr";
import { parse, check, counts, tooltip, checksUrl, onGitHub, lookup, nextDelay, relation, FIELDS } from "../../lib/pr.js";

// Real `gh pr view --json FIELDS` output from this repo's PRs.
const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), "utf8"));
const open = (name, over = {}) => ({ ...fixture(name), state: "OPEN", ...over });

test("checks running: counts both, worst is running, link goes to the checks tab", () => {
  const pr = parse(fixture("pr-466-running"));
  assert.equal(pr.state, "open");
  assert.equal(pr.number, 466);
  assert.deepEqual(pr.checks.running, ["eval (WorkLaptop, macos-latest, darwinConfigurations)", "eval (NightSprings, macos-latest, darwinConfigurations)"]);
  assert.equal(pr.checks.passed, 4);
  assert.equal(pr.worst, "running");
  assert.equal(counts(pr.checks), "4 passed · 2 running");
  assert.equal(checksUrl(pr), "https://github.com/matteo-pacini/nixos-configs/pull/466/checks");
  assert.equal(pr.conflicts, false);
  assert.equal(pr.changes, false);
});

test("every check passed", () => {
  const pr = parse(fixture("pr-466"));
  assert.equal(pr.worst, "passed");
  assert.equal(counts(pr.checks), "11 passed");
  assert.equal(tooltip(pr.checks), null);
});

test("a failed check wins and is named; cancelled counts as failed, skipped as nothing", () => {
  const pr = parse(open("pr-424"));
  assert.equal(pr.worst, "failed");
  assert.equal(pr.checks.failed.length, 5);
  assert.equal(pr.checks.passed, 0);
  assert.equal(counts(pr.checks), "");
  assert.equal(checksUrl(pr), pr.checks.failed[0].url);
  assert.match(tooltip(pr.checks), /^Failed: .+\n[\s\S]*Click: open the first failed check$/);
});

test("failed beats running; the counts after it leave the failed out", () => {
  const running = fixture("pr-466-running").statusCheckRollup;
  const failed = fixture("pr-424").statusCheckRollup[0];
  const pr = parse(open("pr-466-running", { statusCheckRollup: [...running, failed] }));
  assert.equal(pr.worst, "failed");
  assert.equal(counts(pr.checks), "4 passed · 2 running");
  assert.equal(tooltip(pr.checks).split("\n").length, 4);
});

test("merged and closed carry no checks, review or conflicts", () => {
  for (const [name, state] of [["pr-464", "merged"], ["pr-424", "closed"]]) {
    const pr = parse({ ...fixture(name), reviewDecision: "CHANGES_REQUESTED", mergeStateStatus: "DIRTY" });
    assert.equal(pr.state, state);
    assert.equal(pr.worst, null);
    assert.equal(pr.changes, false);
    assert.equal(pr.conflicts, false);
  }
});

test("draft, changes requested and conflicts on an open PR", () => {
  const pr = parse(open("pr-466-running", { isDraft: true, reviewDecision: "CHANGES_REQUESTED", mergeStateStatus: "DIRTY" }));
  assert.equal(pr.state, "draft");
  assert.equal(pr.changes, true);
  assert.equal(pr.conflicts, true);
  assert.equal(pr.worst, "running");
});

test("no checks: no glyph", () => {
  assert.equal(parse(open("pr-466", { statusCheckRollup: [] })).worst, null);
});

test("status contexts (nixpkgs' Eval Summary) count like check runs", () => {
  const ctx = fixture("status-context");
  assert.deepEqual(check(ctx), { name: "Eval Summary", url: ctx.targetUrl, result: "passed" });
  assert.equal(check({ ...ctx, state: "PENDING" }).result, "running");
  assert.equal(check({ ...ctx, state: "ERROR" }).result, "failed");
});

test("GitHub origins over SSH and HTTPS; others are not", () => {
  assert.ok(onGitHub("git@github.com:matteo-pacini/nixos-configs.git"));
  assert.ok(onGitHub("https://github.com/NixOS/nixpkgs"));
  assert.ok(onGitHub("ssh://git@github.com/NixOS/nixpkgs.git"));
  assert.ok(!onGitHub("git@gitlab.com:a/b.git"));
  assert.ok(!onGitHub("https://github.com.evil.example/a/b"));
  assert.ok(!onGitHub(null));
});

test("lookup runs gh in the folder on its machine, without prompts", async () => {
  mock({ exec: async () => ({ code: 0, stdout: JSON.stringify(fixture("pr-466")), stderr: "" }) });
  const r = await lookup("/n/wt", "nexus");
  assert.equal(r.pr.number, 466);
  assert.deepEqual(calls, [["exec", "env", ["GH_PROMPT_DISABLED=1", "gh", "pr", "view", "--json", FIELDS], { cwd: "/n/wt", on: "nexus" }]]);
});

test("lookup: no PR clears, any other failure is unknown", async () => {
  mock({ exec: async () => ({ code: 1, stdout: "", stderr: 'no pull requests found for branch "x"\n' }) });
  assert.deepEqual(await lookup("/h/r", null), { none: true });
  mock({ exec: async () => ({ code: 4, stdout: "", stderr: "To get started with GitHub CLI, please run:  gh auth login" }) });
  assert.deepEqual(await lookup("/h/r", null), { unknown: true });
  mock({ exec: async () => { throw new Error("machine away"); } });
  assert.deepEqual(await lookup("/h/r", "nexus"), { unknown: true });
});

test("next look: a minute while checks run and the window is in front, else ten", () => {
  const running = parse(fixture("pr-466-running"));
  assert.equal(nextDelay(running, true), 60_000);
  assert.equal(nextDelay(running, false), 600_000);
  assert.equal(nextDelay(parse(fixture("pr-466")), true), 600_000);
  assert.equal(nextDelay(null, true), 600_000);
});

test("relation: same checkout from a subfolder, another worktree, another repo", () => {
  const space = { repo: '[null,"/h/r/.git"]', top: "/h/r" };
  assert.equal(relation({ ...space }, space), "same");
  assert.equal(relation({ repo: space.repo, top: "/h/.herdr/worktrees/r/x" }, space), "worktree");
  assert.equal(relation({ repo: '[null,"/h/nixpkgs/.git"]', top: "/h/nixpkgs" }, space), "repo");
  assert.equal(relation({ ...space }, null), "repo");
  assert.equal(relation(null, space), "same");
});
