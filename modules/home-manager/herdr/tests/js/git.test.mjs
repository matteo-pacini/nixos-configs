import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { gitInfo, plain, origin } from "../../lib/git.js";

// exec answering git by what it's asked; `over` replaces an answer by its key.
function repo(over = {}) {
  const answers = {
    status: { code: 0, stdout: "# branch.oid abc\n# branch.head feat/x\n# branch.upstream origin/feat/x\n# branch.ab +1 -0\n", stderr: "" },
    "--show-toplevel": { code: 0, stdout: "/h/.herdr/worktrees/r/feat-x\n", stderr: "" },
    "--git-common-dir": { code: 0, stdout: "/h/r/.git\n", stderr: "" },
    "origin/HEAD": { code: 0, stdout: "origin/master\n", stderr: "" },
    "rev-list": { code: 0, stdout: "3\t5\n", stderr: "" },
    "get-url": { code: 0, stdout: "git@github.com:me/r.git\n", stderr: "" },
    ...over,
  };
  mock({
    exec: async (cmd, args) => {
      const key = Object.keys(answers).find((k) => args.includes(k));
      return answers[key] ?? { code: 1, stdout: "", stderr: "" };
    },
  });
}

test("a linked worktree: its repo, branch and ahead/behind against origin's default", async () => {
  repo();
  const { info } = await gitInfo("/h/.herdr/worktrees/r/feat-x/sub", null);
  assert.deepEqual(info, { name: "r", branch: "feat/x", ahead: 5, behind: 3, repo: '[null,"/h/r/.git"]', top: "/h/.herdr/worktrees/r/feat-x", linked: true });
  // Every call runs in the folder asked about, on its machine.
  assert.ok(calls.every(([, , , opts]) => opts.cwd === "/h/.herdr/worktrees/r/feat-x/sub" && opts.on === null));
});

test("without origin/HEAD it tries origin/master, then main; without either, the upstream's counts", async () => {
  repo({ "origin/HEAD": { code: 1, stdout: "", stderr: "" }, "--verify": { code: 1, stdout: "", stderr: "" } });
  const { info } = await gitInfo("/h/r", null);
  assert.deepEqual([info.ahead, info.behind], [1, 0]);
  const tried = calls.filter(([, , args]) => args.includes("--verify")).map(([, , args]) => args.at(-1));
  assert.deepEqual(tried, ["origin/master", "origin/main"]);
});

test("detached HEAD has no branch", async () => {
  repo({ status: { code: 0, stdout: "# branch.oid abc\n# branch.head (detached)\n", stderr: "" } });
  assert.equal((await gitInfo("/h/r", null)).info.branch, null);
});

test("not a repo is remembered; any other git failure is asked again", async () => {
  repo({ status: { code: 128, stdout: "", stderr: "fatal: not a git repository (or any of the parent directories): .git" } });
  assert.deepEqual(await gitInfo("/tmp", null), { none: true });
  repo({ status: { code: 128, stdout: "", stderr: "fatal: detected dubious ownership" } });
  assert.deepEqual(await gitInfo("/tmp", null), { unsure: true });
});

test("plain branches are master and main only", () => {
  assert.ok(plain("master") && plain("main"));
  assert.ok(!plain("feat/main") && !plain(null));
});

test("origin's URL, null without one", async () => {
  repo();
  assert.equal(await origin("/h/r", "nexus"), "git@github.com:me/r.git");
  repo({ "get-url": { code: 2, stdout: "", stderr: "error: No such remote 'origin'" } });
  assert.equal(await origin("/h/r", null), null);
});
