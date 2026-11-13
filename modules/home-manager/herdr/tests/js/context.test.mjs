import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { contextPrompt, copy, others } from "../../lib/context.js";

// agents() and spaces() entries, trimmed to the fields the prompt reads.
const agent = (address, app, space, tab, status) => ({
  address, app, status, space: space.id, space_name: space.name,
  tab: `${space.id}-${tab}`, tab_name: tab, program: { name: app },
});
const nixos = { id: "s1", name: "nixos-configs", machine: null, branch: "feat/e2e" };
const core = { id: "s2", name: "herdr-core", machine: null, branch: "main" };
const lab = { id: "s3", name: "homelab", machine: "nexus", branch: "master" };
const spaces = [nixos, core, lab];
const self = agent("t3", "claude-code", nixos, "api", "idle");
const agents = [
  agent("t1", "codex", nixos, "api", "idle"),
  self,
  agent("t4b", "opencode", nixos, "api", "working"),
  agent("t2", "claude-code", nixos, "docs", "idle"),
  agent("t8", "codex", core, "main", "working"),
  agent("nexus/t8", "claude-code", lab, "1", "idle"),
  agent("nexus/t9", "codex", lab, "1", "done"),
];
const names = (m) => m ?? "BrightFalls";
const now = new Date(2026, 10, 10, 14, 32);
const prompt = (level, list = agents, me = self) => contextPrompt({ level, self: me, agents: list, spaces, names, now });

const INTRO = 'You are a Claude Code agent running in herdr: terminal t3, tab "api", space "nixos-configs" (branch feat/e2e) on BrightFalls.';
const OUTRO = "This is for awareness. Don't interact with them unless your task says to.\n`herdr-app --skill` explains herdr, including how to get the current state. Your task: ";

test("others: each level widens the last, never including the agent itself", () => {
  const at = (level) => others(level, self, agents, spaces).map((a) => a.address);
  assert.deepEqual(at("tab"), ["t1", "t4b"]);
  assert.deepEqual(at("space"), ["t1", "t4b", "t2"]);
  assert.deepEqual(at("machine"), ["t1", "t4b", "t2", "t8"]);
  assert.deepEqual(at("everywhere"), ["t1", "t4b", "t2", "t8", "nexus/t8", "nexus/t9"]);
});

test("tab: one line per agent", () => {
  assert.equal(prompt("tab"), [INTRO,
    "Other agents in this tab, as of 14:32 (this changes often):",
    "- t1: Codex, idle",
    "- t4b: opencode, working",
    OUTRO].join("\n"));
});

test("space: grouped by tab", () => {
  assert.equal(prompt("space"), [INTRO,
    "Other agents in this space, as of 14:32 (this changes often):",
    '- tab "api": t1 Codex, idle; t4b opencode, working',
    '- tab "docs": t2 Claude Code, idle',
    OUTRO].join("\n"));
});

test("machine: grouped by space, with its branch", () => {
  assert.equal(prompt("machine"), [INTRO,
    "Other agents on BrightFalls, as of 14:32 (this changes often):",
    '- space "nixos-configs" (feat/e2e): t1 Codex in api, idle; t4b opencode in api, working; t2 Claude Code in docs, idle',
    '- space "herdr-core" (main): t8 Codex in main, working',
    OUTRO].join("\n"));
});

test("everywhere: counts per space and machine", () => {
  assert.equal(prompt("everywhere"), [INTRO,
    "Other agents on every machine, as of 14:32 (this changes often):",
    '- BrightFalls, space "nixos-configs" (feat/e2e): 3 agents, 1 working',
    '- BrightFalls, space "herdr-core" (main): 1 agent, 1 working',
    '- nexus, space "homelab" (master): 2 agents',
    OUTRO].join("\n"));
});

test("an agent on another machine is addressed as it is there", () => {
  const remote = agents.find((a) => a.address === "nexus/t9");
  const text = prompt("tab", agents, remote);
  assert.match(text, /^You are a Codex agent running in herdr: terminal t9, tab "1", space "homelab" \(branch master\) on nexus\.\n/);
  assert.match(text, /\n- t8: Claude Code, idle\n/);
});

test("alone: says so, and still ends in the task", () => {
  assert.equal(prompt("tab", [self]), [INTRO, "No other agents in this tab right now.", OUTRO].join("\n"));
  assert.match(prompt("everywhere", [self]), /\nNo other agents anywhere right now\.\n/);
});

test("an opencode agent gets an, not a", () => {
  const oc = agents.find((a) => a.address === "t4b");
  assert.match(prompt("tab", agents, oc), /^You are an opencode agent/);
});

test("copy: the text is an argument, never part of the script", async () => {
  const text = "a `b` $(c)\nYour task: ";
  mock({ exec: () => ({ code: 0, stdout: "", stderr: "" }) });
  assert.equal(await copy(text), true);
  const [, cmd, args] = calls[0];
  assert.equal(cmd, "sh");
  assert.equal(args.at(-1), text);
  assert.ok(!args[1].includes(text));
  mock({ exec: () => ({ code: 1, stdout: "", stderr: "" }) });
  assert.equal(await copy(text), false);
});
