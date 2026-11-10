// The text pane-menu's "Add herdr context" pastes into an idle agent: who and
// where it is, and the other agents at the chosen level, ending in "Your
// task:" for the person to finish. Awareness only: it names agents, never
// grants anything.

import { APPS } from "./agents.js";

/** The levels, narrowest first, with pane-menu's icon for each. */
export const LEVELS = [
  { key: "tab", label: "Tab", icon: "square" },
  { key: "space", label: "Space", icon: "folder" },
  { key: "machine", label: "Machine", icon: "monitor" },
  { key: "everywhere", label: "Everywhere", icon: "server" },
];

// An agent's address on its own machine: the agents listed share the
// reader's machine, where `nexus/t8` is plain `t8`.
const local = (address) => address.split("/").pop();
const appName = (a) => APPS[a.app]?.name ?? a.program?.name ?? a.app ?? "agent";
const plural = (n) => `${n} agent${n === 1 ? "" : "s"}`;
const branchOf = (space) => (space?.branch ? ` (${space.branch})` : "");

/** The agents other than `self` that `level` covers. `agents` and `spaces`
 *  are herdr's agents() and spaces(). */
export function others(level, self, agents, spaces) {
  const machineOf = (a) => spaces.find((s) => s.id === a.space)?.machine ?? null;
  const here = machineOf(self);
  const inScope = {
    tab: (a) => a.tab === self.tab,
    space: (a) => a.space === self.space,
    machine: (a) => machineOf(a) === here,
    everywhere: () => true,
  }[level];
  return agents.filter((a) => a.address !== self.address && inScope(a));
}

/** The context for `self` (an agents() entry) at `level`. `names` maps a
 *  machine (spaces()' `machine`, null for this one) to the name to show;
 *  `now` is a Date. */
export function contextPrompt({ level, self, agents, spaces, names, now }) {
  const spaceOf = (a) => spaces.find((s) => s.id === a.space);
  const nameOf = (machine) => names(machine ?? null);
  const space = spaceOf(self);
  const machine = nameOf(space?.machine);
  const list = others(level, self, agents, spaces);
  const where = { tab: "in this tab", space: "in this space", machine: `on ${machine}`, everywhere: "on every machine" }[level];
  const time = now.toTimeString().slice(0, 5);
  const branch = space?.branch ? ` (branch ${space.branch})` : "";
  const intro = `You are a${/^[aeiou]/i.test(appName(self)) ? "n" : ""} ${appName(self)} agent running in herdr: terminal ${local(self.address)}, tab "${self.tab_name}", space "${self.space_name}"${branch} on ${machine}.`;

  // Groups in first-seen order, which is agents()' space, tab, pane order.
  const group = (key) => {
    const groups = new Map();
    for (const a of list) {
      const k = key(a);
      groups.set(k, [...(groups.get(k) ?? []), a]);
    }
    return [...groups.values()];
  };
  const lines = {
    tab: () => list.map((a) => `- ${local(a.address)}: ${appName(a)}, ${a.status}`),
    space: () => group((a) => a.tab).map((g) =>
      `- tab "${g[0].tab_name}": ${g.map((a) => `${local(a.address)} ${appName(a)}, ${a.status}`).join("; ")}`),
    machine: () => group((a) => a.space).map((g) =>
      `- space "${g[0].space_name}"${branchOf(spaceOf(g[0]))}: ${g.map((a) => `${local(a.address)} ${appName(a)} in ${a.tab_name}, ${a.status}`).join("; ")}`),
    everywhere: () => group((a) => a.space).map((g) => {
      const working = g.filter((a) => a.status === "working").length;
      return `- ${nameOf(spaceOf(g[0])?.machine)}, space "${g[0].space_name}"${branchOf(spaceOf(g[0]))}: ${plural(g.length)}${working ? `, ${working} working` : ""}`;
    }),
  }[level]();

  const body = list.length
    ? [`Other agents ${where}, as of ${time} (this changes often):`, ...lines]
    : [`No other agents ${where === "on every machine" ? "anywhere" : where} right now.`];
  return [
    intro,
    ...body,
    "This is for awareness. Don't interact with them unless your task says to.",
    "`herdr-app --skill` explains herdr, including how to get the current state. Your task: ",
  ].join("\n");
}
