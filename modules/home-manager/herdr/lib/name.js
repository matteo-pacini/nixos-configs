// What an agent is called, and renaming it. agent-list's rows, pane-header and
// the Rename dialog (agent-list's, opened from its menu and from pane-menu)
// share this, so the sidebar and the pane header always show the same name.
//
// The name is the terminal's `agent.name` label, else its title. Not for
// Claude Code, whose title is one it makes up until the session is named:
// there the name is the session's own (`claude.name`, from
// scripts/claude-statusline.sh), else "Claude Code". A Claude Code session
// takes a rename made here as its name at its next message
// (scripts/claude-title.sh), which removes the label, so for Claude Code the
// label only lasts until then.

import { openOverlay } from "herdr";

/** The person's name for an agent. */
export const NAME = "agent.name";
// The terminal's title when NAME was set: scripts/claude-title.sh tells from it
// whether Claude Code was renamed after.
const BASE = "agent.name_base";
// The Claude Code session NAME was set for: scripts/claude-title.sh gives the
// name to no other.
const FOR = "agent.name_session";
// A Claude Code session's name, absent until it has one.
const SESSION_NAME = "claude.name";
const SESSION = "claude.session";

/** A terminal title without the status glyph a program puts in front of it. */
export const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

/** Whether `a` (an agents() or panes() entry) is a Claude Code agent. */
export const isClaude = (a) => a?.app === "claude-code";

/** The name of agent `a` (an agents() entry); `term` is its terminals() entry,
 *  if listed yet. */
export function agentName(a, term) {
  const own = term?.labels?.[NAME] || term?.name;
  if (isClaude(a)) return own || term?.labels?.[SESSION_NAME] || "Claude Code";
  return own || clean(a.title) || a.program?.name || a.address;
}

/** What pane-header calls pane `p` (a panes() entry): an agent's name as
 *  agentName gives it; a shell's program; else the terminal's title. */
export function paneName(p, term) {
  if (p.app || p.program?.agent) return agentName({ ...p, address: p.terminal }, term);
  return (p.program?.shell && p.program.name) || p.title || p.program?.name || "shell";
}

/** The name the Rename dialog starts from for `a` (an agents() or panes()
 *  entry): the label, or for Claude Code the session's name, since saving
 *  renames the session. */
export function renameValue(a, term) {
  return term?.labels?.[NAME] || (isClaude(a) && term?.labels?.[SESSION_NAME]) || "";
}

/** The `hc label` arguments that rename `a` to `value`; `term` is its
 *  terminals() entry. Empty removes the name. */
export function renameLabels(value, a, term) {
  const name = value.trim();
  const claude = name && isClaude(a);
  return [`${NAME}=${name}`, `${BASE}=${claude ? clean(a.title) : ""}`,
    `${FOR}=${(claude && term?.labels?.[SESSION]) || ""}`];
}

/** Opens agent-list's Rename dialog for the agent at `address`, starting from
 *  `value`; `claude`: it is a Claude Code agent. */
export function openRename(address, value, claude) {
  // The Claude Code hint is two lines.
  openOverlay({ mod: "agent-list", kind: "dialog", width: 380, height: claude ? 236 : 220,
    props: { rename: address, value, claude } });
}
