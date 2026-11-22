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

const codex = (more = {}) => ({ address: "t9", app: "codex", title: "⠐ review", program: { name: "Codex", agent: true }, ...more });

test("agentName: the label, then the hc name, the title, the program, the address", () => {
  assert.equal(agentName(codex(), term({ "agent.name": "herdr-cleanup" }, { name: "worker" })), "herdr-cleanup");
  assert.equal(agentName(codex(), term({}, { name: "worker" })), "worker");
  assert.equal(agentName(codex(), term({})), "review");
  assert.equal(agentName(codex(), undefined), "review");
  assert.equal(agentName(codex({ title: "⠐" }), term({})), "Codex");
  assert.equal(agentName({ address: "nexus/t3" }, undefined), "nexus/t3");
});

test("agentName: Claude Code is its session's name, never the title it makes up", () => {
  assert.equal(agentName(claude(), term({ "agent.name": "herdr-cleanup", "claude.name": "old" }, { name: "worker" })), "herdr-cleanup");
  assert.equal(agentName(claude(), term({ "claude.name": "new-sunshine" }, { name: "worker" })), "worker");
  assert.equal(agentName(claude({ title: "✳ Fix pane header labels" }), term({ "claude.name": "new-sunshine" })), "new-sunshine");
  assert.equal(agentName(claude({ title: "✳ Fix pane header labels" }), term({})), "Claude Code");
  assert.equal(agentName(claude(), undefined), "Claude Code");
});

test("paneName: an agent pane is named as its sidebar row", () => {
  for (const labels of [{ "agent.name": "herdr-cleanup" }, {}]) {
    assert.equal(paneName(pane(), term(labels)), agentName(claude(), term(labels)));
  }
  assert.equal(paneName(pane(), term({ "agent.name": "herdr-cleanup" })), "herdr-cleanup");
  assert.equal(paneName(pane(), undefined), "Claude Code");
  assert.equal(paneName(pane(), term({ "claude.name": "new-sunshine" })), "new-sunshine");
  // An agent herdr knows only by its program.
  assert.equal(paneName(pane({ app: null, title: "review" }), term({})), "review");
  assert.equal(paneName(pane({ app: "codex", terminal: "nexus/t3", title: "" , program: null }), undefined), "nexus/t3");
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
  assert.equal(renameValue(claude(), term({ "claude.name": "new-sunshine" })), "new-sunshine");
  assert.equal(renameValue(claude(), term({})), "", "not the title Claude Code made up");
  assert.equal(renameValue(pane(), undefined), "");
  assert.equal(renameValue({ address: "t9", app: "codex" }, term({ "claude.name": "left-behind" })), "");
  assert.equal(renameValue({ address: "t9", app: "codex", title: "review" }, term({})), "");
});

test("renameLabels: Claude Code gets the name, the title it was renamed from and the session it is for", () => {
  assert.deepEqual(renameLabels("  herdr-cleanup ", claude(), term({ "claude.session": "s-1" })),
    ["agent.name=herdr-cleanup", "agent.name_base=new-sunshine", "agent.name_session=s-1"]);
  assert.deepEqual(renameLabels("a b", claude({ title: "" }), term({})), ["agent.name=a b", "agent.name_base=", "agent.name_session="]);
  assert.deepEqual(renameLabels("a b", claude({ title: "" })), ["agent.name=a b", "agent.name_base=", "agent.name_session="]);
});

test("renameLabels: another agent gets the name alone", () => {
  assert.deepEqual(renameLabels("review", { address: "t9", app: "codex", title: "x" }, term({ "claude.session": "s-0" })),
    ["agent.name=review", "agent.name_base=", "agent.name_session="]);
  assert.deepEqual(renameLabels("review", undefined), ["agent.name=review", "agent.name_base=", "agent.name_session="]);
});

test("renameLabels: empty removes all three", () => {
  assert.deepEqual(renameLabels("   ", claude(), term({ "claude.session": "s-1" })), ["agent.name=", "agent.name_base=", "agent.name_session="]);
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
