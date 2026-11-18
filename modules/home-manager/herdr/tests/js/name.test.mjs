import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { agentName, paneName, renameValue, renameLabels, openRename, clean, isClaude } from "../../lib/name.js";

// agents(), panes() and terminals() entries as herdr-app 0.1.13 gives them,
// cut to the fields the names are made from.
const claude = (more = {}) => ({ address: "t4v", app: "claude-code", title: "✳ new-sunshine",
  program: { name: "Claude Code", agent: true }, ...more });
const pane = (more = {}) => ({ pane: "p3", terminal: "t4v", app: "claude-code", title: "✳ new-sunshine",
  program: { name: "Claude Code", agent: true }, ...more });
const term = (labels, more = {}) => ({ address: "t4v", name: null, labels, ...more });

test("clean: drops the status glyph a program puts before its title", () => {
  assert.equal(clean("✳ new-sunshine"), "new-sunshine");
  assert.equal(clean("⠐ Fix pane header labels "), "Fix pane header labels");
  assert.equal(clean("herdr-cleanup"), "herdr-cleanup");
  assert.equal(clean("日本 notes"), "日本 notes");
  assert.equal(clean(undefined), "");
});

test("agentName: the label, then the hc name, the title, the program, the address", () => {
  assert.equal(agentName(claude(), term({ "agent.name": "herdr-cleanup" }, { name: "worker" })), "herdr-cleanup");
  assert.equal(agentName(claude(), term({}, { name: "worker" })), "worker");
  assert.equal(agentName(claude(), term({})), "new-sunshine");
  assert.equal(agentName(claude(), undefined), "new-sunshine");
  assert.equal(agentName(claude({ title: "✳" }), term({})), "Claude Code");
  assert.equal(agentName({ address: "nexus/t3" }, undefined), "nexus/t3");
});

test("paneName: an agent pane is named as its sidebar row", () => {
  for (const labels of [{ "agent.name": "herdr-cleanup" }, {}]) {
    assert.equal(paneName(pane(), term(labels)), agentName(claude(), term(labels)));
  }
  assert.equal(paneName(pane(), term({ "agent.name": "herdr-cleanup" })), "herdr-cleanup");
  assert.equal(paneName(pane(), undefined), "new-sunshine");
  // An agent herdr knows only by its program.
  assert.equal(paneName(pane({ app: null, title: "review" }), term({})), "review");
  assert.equal(paneName(pane({ terminal: "nexus/t3", title: "" , program: null }), undefined), "nexus/t3");
});

test("paneName: a shell keeps its program, anything else its title", () => {
  const shell = { pane: "p1", terminal: "t2", title: "~/Repositories", program: { name: "zsh", shell: true } };
  assert.equal(paneName(shell, term({ "agent.name": "ignored" })), "zsh");
  assert.equal(paneName({ pane: "p1", terminal: "t2", title: "htop", program: { name: "htop" } }, undefined), "htop");
  assert.equal(paneName({ pane: "p1", terminal: "t2", program: { name: "htop" } }, undefined), "htop");
  assert.equal(paneName({ pane: "p1" }, undefined), "shell");
});

test("renameValue: the label; for Claude Code, else the session's name", () => {
  assert.equal(renameValue(claude(), term({ "agent.name": "herdr-cleanup" })), "herdr-cleanup");
  assert.equal(renameValue(claude(), term({})), "new-sunshine");
  assert.equal(renameValue(pane(), undefined), "new-sunshine");
  assert.equal(renameValue({ address: "t9", app: "codex", title: "review" }, term({})), "");
});

test("renameLabels: Claude Code gets the name and the title it was renamed from", () => {
  assert.deepEqual(renameLabels("  herdr-cleanup ", claude()), ["agent.name=herdr-cleanup", "agent.name_base=new-sunshine"]);
  assert.deepEqual(renameLabels("a b", claude({ title: "" })), ["agent.name=a b", "agent.name_base="]);
});

test("renameLabels: another agent gets the name alone", () => {
  assert.deepEqual(renameLabels("review", { address: "t9", app: "codex", title: "x" }), ["agent.name=review", "agent.name_base="]);
  assert.deepEqual(renameLabels("review", undefined), ["agent.name=review", "agent.name_base="]);
});

test("renameLabels: empty removes both", () => {
  assert.deepEqual(renameLabels("   ", claude()), ["agent.name=", "agent.name_base="]);
});

test("openRename: agent-list's dialog, taller for Claude Code's two-line hint", () => {
  mock({ openOverlay: () => {} });
  openRename("nexus/t3", "paperless-agent", true);
  openRename("t9", "", false);
  assert.deepEqual(calls, [
    ["openOverlay", { mod: "agent-list", kind: "dialog", width: 380, height: 236, props: { rename: "nexus/t3", value: "paperless-agent", claude: true } }],
    ["openOverlay", { mod: "agent-list", kind: "dialog", width: 380, height: 220, props: { rename: "t9", value: "", claude: false } }],
  ]);
});

test("isClaude: by the app herdr reports", () => {
  assert.equal(isClaude(claude()), true);
  assert.equal(isClaude({ app: "codex" }), false);
  assert.equal(isClaude(undefined), false);
});
