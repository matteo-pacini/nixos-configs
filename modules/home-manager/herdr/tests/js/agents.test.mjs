import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { APPS, atPrompt, fromShell, agentVersion, restartAgent, typeAtPrompt } from "../../lib/agents.js";

// `hc get --json` shapes, as hc reports them (paths trimmed).
const shellAtPrompt = { pid: 71910, argv: ["zsh", "-l"], foreground: { pid: 71910, argv: ["zsh", "-l"] } };
const agentInShell = { pid: 1955, argv: ["zsh"], foreground: { pid: 3836, argv: [".claude-wrapped_", "--resume", "73c4"] } };
const agentIsProgram = { pid: 16538, argv: ["claude"], foreground: { pid: 16538, argv: [".claude-wrapped_"] } };
const otherInShell = { pid: 34292, argv: ["zsh", "-l"], foreground: { pid: 34552, argv: ["caffeinate", "-d", "-i"] } };
// `sh -c "claude; exec sh"`: the agent shares the script's group, so the
// foreground is the script itself until it execs the shell.
const agentInScript = { pid: 500, argv: ["/bin/sh", "-c", "claude; exec sh"], foreground: { pid: 500, argv: ["/bin/sh", "-c", "claude; exec sh"] } };
const scriptWithoutShell = { pid: 501, argv: ["sh", "-c", "claude"], foreground: { pid: 501, argv: ["sh", "-c", "claude"] } };

test("atPrompt: only a shell with nothing running in it", () => {
  assert.equal(atPrompt(shellAtPrompt), true);
  assert.equal(atPrompt(agentInShell), false);
  assert.equal(atPrompt(agentIsProgram), false);
  assert.equal(atPrompt(agentInScript), false, "a `sh -c` script isn't a prompt");
});

test("fromShell: the agent's terminal outlives it", () => {
  assert.equal(fromShell(agentInShell), true);
  assert.equal(fromShell(otherInShell), true);
  assert.equal(fromShell(agentInScript), true);
  assert.equal(fromShell(agentIsProgram), false, "quitting it would end the terminal");
  assert.equal(fromShell(scriptWithoutShell), false, "no `exec sh` after the agent");
});

test("agentVersion: outdated only once the installed version is known and newer", () => {
  const spawned = [];
  const cx = { spawn: (f) => spawned.push(f), notify() {} };
  const labels = { "agent.version": "2.1.300", "claude.session": "abc" };
  mock({});
  let v = agentVersion("claude-code", "nexus/t3", labels, cx);
  assert.deepEqual([v.running, v.latest, v.outdated, v.session], ["2.1.300", null, false, "abc"]);
  assert.equal(spawned.length, 1, "reads the installed version in the background");
  // Not an agent: nothing to read.
  v = agentVersion("zsh", "t1", labels, cx);
  assert.deepEqual([v.app, v.running, v.outdated, v.session], [undefined, null, false, undefined]);
});

test("agentVersion: reads the installed version on the agent's machine", async () => {
  let spawned;
  const cx = { spawn: (f) => (spawned = f), notify() {} };
  mock({ exec: async () => ({ code: 0, stdout: "/nix/store/0abc-codex-0.99.1/bin/codex\n" }) });
  agentVersion("codex", "brightfalls/t9", { "agent.version": "0.98.0" }, cx);
  await spawned(cx);
  assert.deepEqual(calls[0][3], { on: "brightfalls" });
  const v = agentVersion("codex", "brightfalls/t9", { "agent.version": "0.98.0", "codex.session": "s1" }, cx);
  assert.deepEqual([v.latest, v.outdated, v.session], ["0.99.1", true, "s1"]);
});

test("restartAgent: quits, waits for the prompt, resumes the session", async () => {
  let quit = false;
  mock({
    hc: async (args) => {
      if (args[0] === "get") return { code: 0, stdout: JSON.stringify(quit ? shellAtPrompt : agentInShell) };
      if (args[0] === "send" && args[2] === "/exit") quit = true;
      return { code: 0, stdout: "" };
    },
    exec: async () => ({ code: 0, stdout: "" }),
    notify: () => assert.fail("no error expected"),
  });
  await restartAgent("t1", APPS["claude-code"], "sess-1");
  const sends = calls.filter(([n, a]) => n === "hc" && a[0] === "send").map(([, a]) => a[2]);
  assert.deepEqual(sends, ["/exit", "claude --resume sess-1"]);
});

// The quit clears the keep-cache-warm switch (scripts/claude-session.sh), so a
// restart has to put it back. `labelled` plays that hook: the label is gone
// once the agent has quit.
function restartWith(labels, { quits = true } = {}) {
  let quit = false;
  mock({
    hc: async (args) => {
      if (args[0] === "get") return { code: 0, stdout: JSON.stringify(quit ? shellAtPrompt : { ...agentInShell, labels }) };
      if (args[0] === "send" && args[2] === "/exit") quit = quits;
      return { code: 0, stdout: "" };
    },
    exec: async () => ({ code: 0, stdout: "" }),
    notify: () => {},
  });
  return restartAgent("t1", APPS["claude-code"], "sess-1");
}
const hcCalls = (verb) => calls.filter(([n, a]) => n === "hc" && a[0] === verb).map(([, a]) => a);

test("restartAgent: a session kept warm is kept warm after the restart", async () => {
  await restartWith({ "agent.keep_warm": "1", "claude.session": "sess-1", "agent.cache_ttl": "1h" });
  assert.deepEqual(hcCalls("label"), [["label", "t1", "agent.keep_warm=1"]], "the switch, with its value, and nothing else");
  const order = calls.filter(([n]) => n === "hc").map(([, a]) => a.slice(0, 3).join(" "));
  assert.ok(order.indexOf("label t1 agent.keep_warm=1") > order.indexOf("send t1 claude --resume sess-1"),
    "set after the resume, once the quitting session's hook has cleared it");
  assert.ok(order.indexOf("label t1 agent.keep_warm=1") > order.indexOf("send t1 /exit"));
});

test("restartAgent: a session that wasn't kept warm stays off", async () => {
  await restartWith({ "claude.session": "sess-1", "agent.cache_ttl": "1h" });
  assert.deepEqual(hcCalls("label"), []);
  await restartWith({ "agent.keep_warm": "", "claude.session": "sess-1" });
  assert.deepEqual(hcCalls("label"), [], "an empty label is off");
  await restartWith(undefined);
  assert.deepEqual(hcCalls("label"), [], "a terminal with no labels");
});

test("restartAgent: the switch isn't set on a terminal whose agent didn't quit", async () => {
  await restartWith({ "agent.keep_warm": "1", "claude.session": "sess-1" }, { quits: false });
  assert.deepEqual(hcCalls("label"), [], "the session still runs with its switch as it was");
  assert.deepEqual(hcCalls("send").map((a) => a[2]), ["/exit"], "and nothing is resumed");
});

test("restartAgent: only Claude Code carries a switch over", async () => {
  assert.deepEqual(APPS["claude-code"].keeps, ["agent.keep_warm"]);
  for (const id of Object.keys(APPS).filter((k) => k !== "claude-code")) assert.equal(APPS[id].keeps, undefined, id);
  let quit = false;
  mock({
    hc: async (args) => {
      if (args[0] === "get") return { code: 0, stdout: JSON.stringify(quit ? shellAtPrompt : { ...agentInShell, labels: { "agent.keep_warm": "1" } }) };
      if (args[0] === "send" || args[0] === "keys") quit = true;
      return { code: 0, stdout: "" };
    },
    exec: async () => ({ code: 0, stdout: "" }),
    notify: () => {},
  });
  await restartAgent("t1", APPS.codex ?? APPS.opencode, "sess-1");
  assert.deepEqual(hcCalls("label"), []);
});

test("restartAgent: answers Claude's background-work prompt with Enter", async () => {
  let asked = false, quit = false;
  mock({
    hc: async (args) => {
      if (args[0] === "get") return { code: 0, stdout: JSON.stringify(quit ? shellAtPrompt : agentInShell) };
      if (args[0] === "read") { asked = true; return { code: 0, stdout: "Background work is running. Exit?" }; }
      if (args[0] === "keys" && args[2] === "enter") quit = true;
      return { code: 0, stdout: "" };
    },
    exec: async () => ({ code: 0, stdout: "" }),
    notify: () => assert.fail("no error expected"),
  });
  await restartAgent("t1", APPS["claude-code"], "sess-1");
  assert.equal(asked, true);
  assert.deepEqual(calls.filter(([n, a]) => n === "hc" && a[0] === "keys").length, 1, "Enter pressed once");
  assert.equal(calls.at(-1)[1].at(-1), "claude --resume sess-1");
});

test("restartAgent: opencode quits with a key, not pasted text", async () => {
  let quit = false;
  mock({
    hc: async (args) => {
      if (args[0] === "get") return { code: 0, stdout: JSON.stringify(quit ? shellAtPrompt : agentInShell) };
      if (args[0] === "keys") quit = true;
      return { code: 0, stdout: "" };
    },
    exec: async () => ({ code: 0, stdout: "" }),
    notify: () => assert.fail("no error expected"),
  });
  await restartAgent("t1", APPS.opencode, "ses_9");
  assert.deepEqual(calls.find(([n, a]) => n === "hc" && a[0] === "keys")[1], ["keys", "t1", "ctrl+c"]);
});

test("restartAgent: refuses an agent that is the terminal's own program", async () => {
  const errors = [];
  mock({
    hc: async () => ({ code: 0, stdout: JSON.stringify(agentIsProgram) }),
    notify: (n) => errors.push(n.body),
  });
  await restartAgent("t1", APPS["claude-code"], "sess-1");
  assert.deepEqual(errors, ["it isn't running from a shell"]);
  assert.equal(calls.some(([n, a]) => n === "hc" && a[0] === "send"), false, "never told it to quit");
});

test("typeAtPrompt: waits for the prompt, then types the agent quoted", async () => {
  const shellStarting = { pid: 71910, argv: ["zsh"], foreground: null };
  const gets = [shellStarting, shellAtPrompt];
  mock({
    hc: (args) => (args[0] === "get" ? { code: 0, stdout: JSON.stringify(gets.shift()) } : { code: 0, stdout: "", stderr: "" }),
    exec: () => ({ code: 0 }),
  });
  await typeAtPrompt("nexus/t7", ["claude", "--model", "it's"], "Claude Code");
  const hcCalls = calls.filter((c) => c[0] === "hc").map((c) => c[1]);
  assert.deepEqual(hcCalls, [
    ["get", "nexus/t7", "--json"],
    ["get", "nexus/t7", "--json"],
    ["send", "nexus/t7", "claude --model 'it'\\''s'"],
  ]);
});

test("typeAtPrompt: never types into a terminal that isn't at a prompt", async () => {
  mock({
    hc: (args) => (args[0] === "get" ? { code: 0, stdout: JSON.stringify(agentIsProgram) } : { code: 0 }),
    exec: () => ({ code: 0 }),
    notify: () => null,
  });
  await typeAtPrompt("t9", ["codex"], "Codex");
  assert.equal(calls.some((c) => c[0] === "hc" && c[1][0] === "send"), false);
  assert.equal(calls.filter((c) => c[0] === "notify").length, 1);
});
