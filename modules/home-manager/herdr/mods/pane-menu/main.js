// The terminal right-click menu of the workbench layout (its `terminal_menu`):
// the shipped `menu` mod's pane items, plus Rename for an agent, and splits
// that open a second menu choosing what runs in the new pane: a shell (the
// default, first and selected) or an agent installed on the pane's machine.
// Props from the app: { tab: "pane", target: { pane, terminal }, overlay }; the
// second menu gets { split: { direction, pane } }.

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, theme, keys, terminals, panes, knownAgents, shared, setShared, notify, exec } from "herdr";
import { typeAtPrompt } from "./lib/agents.js";

// The agents each machine last reported, so the split menu fills at once
// while knownAgents() checks again.
const KNOWN = "pane-menu.agents";
const ROW = 31;

const machineOf = (address) => (address?.includes("/") ? address.split("/")[0] : null);

// An item is { label, icon, hint?, act }; `sep` draws a line above it.
function paneItems(target) {
  const all = terminals();
  const term = all.find((t) => t.address === target.terminal);
  const pane = panes().find((p) => p.pane === target.pane);
  const parent = term?.parent && all.find((t) => t.address === term.parent);
  const toProgram = term?.labels?.["herdr.right-click"] === "program";
  const split = (direction) => ({
    label: direction === "right" ? "Split right" : "Split down",
    icon: "panel-right",
    hint: "▸",
    act: () => openOverlay({ mod: "pane-menu", kind: "popup", width: 220, height: splitHeight(target.terminal), props: { split: { direction, pane: target.pane } } }),
  });
  return [
    ...(term && (pane?.app || pane?.program?.agent)
      ? [{ label: "Rename", icon: "square-pen", act: () => openOverlay({ mod: "agent-list", kind: "dialog", width: 380, height: 220,
          props: { rename: term.address, value: term.labels?.["agent.name"] ?? "" } }) }]
      : []),
    split("right"),
    split("down"),
    { label: "Zoom", icon: "square", hint: shortcut("pane.zoom"), act: () => run("pane.zoom", { pane: target.pane }) },
    ...(term
      ? [toProgram
          ? { label: "Use Herdr right-click menu", icon: "terminal", act: () => run("terminal.right_click", { terminal: term.address, to: "menu" }) }
          : { label: "Send right-clicks to pane", icon: "terminal", act: () => run("terminal.right_click", { terminal: term.address, to: "program" }) }]
      : []),
    ...(parent ? [{ label: `Send back to ${parent.name || parent.address}`, icon: "terminal", act: () => run("terminal.park", { terminal: term.address }) }] : []),
    { label: "Close pane", icon: "x", sep: true, hint: shortcut("pane.close"), act: () => run("pane.close", { pane: target.pane }) },
  ];
}

// The new pane is a shell in the split one's current folder. An agent is typed
// at its prompt rather than run as the pane's program, so it gets what the
// shell sets up there (direnv's dev shell) and leaves the shell when it exits.
function splitItems(split, agents) {
  const open = () => run("pane.split", { direction: split.direction, pane: split.pane });
  // terminals() lists the split's terminal a moment after pane.split returns.
  const start = (a) => async () => {
    const before = new Set(terminals().map((t) => t.address));
    open();
    let address;
    for (let i = 0; i < 50 && !address; i++) {
      address = terminals().find((t) => !before.has(t.address))?.address;
      if (!address) await exec("sleep", ["0.1"]);
    }
    if (address) await typeAtPrompt(address, a.run, a.name);
    else notify({ title: `Couldn't start ${a.name}`, body: "the split has no terminal", level: "error" });
  };
  return [
    { label: "Shell", icon: "terminal", act: open },
    ...agents.map((a, i) => ({ label: a.name, agent: a, sep: i === 0, act: start(a) })),
  ];
}

function splitHeight(terminal) {
  const n = (shared(KNOWN)?.[machineOf(terminal) ?? ""] ?? []).filter((a) => a.installed).length || 3;
  return (n + 1) * ROW + 19;
}

// The key bound to a command, for the hint on the right.
function shortcut(name) {
  return keys().find((b) => b.section === "global" && b.action === name)?.keys ?? "";
}

export default class PaneMenu extends View {
  init(_props, cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    const split = props()?.split;
    if (!split) return;
    const machine = machineOf(panes().find((p) => p.pane === split.pane)?.terminal);
    const where = machine ?? "";
    this.agents = shared(KNOWN)?.[where] ?? [];
    cx.spawn(async (cx) => {
      try {
        this.agents = await knownAgents({ on: machine });
        setShared(KNOWN, { ...shared(KNOWN), [where]: this.agents });
      } catch {}
      cx.notify();
    });
  }

  items() {
    const p = props() ?? {};
    return p.split ? splitItems(p.split, (this.agents ?? []).filter((a) => a.installed)) : paneItems(p.target ?? {});
  }

  // An act that returns a promise keeps the menu open until it settles:
  // closing the overlay cancels the mod's unfinished work.
  async choose(i) {
    const it = this.items()[i];
    if (!it || this.busy) return;
    this.busy = true;
    try {
      await it.act();
    } finally {
      closeOverlay(props()?.overlay);
    }
  }

  render(cx) {
    const t = theme();
    const list = this.items();
    const icon = (it) => it.agent
      ? (it.agent.tint ? svg(it.agent.icon).size(14).flex_none().text_color(t.muted) : image(it.agent.icon).size(14).flex_none())
      : svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(t.muted);
    return v_flex()
      .id("pane-menu")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter" || (e.key === "right" && list[this.at]?.hint === "▸")) this.choose(this.at);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => v_flex()
        .when(Boolean(it.sep) && i > 0, (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`pm-${i}`).h(ROW).px(8).gap(9).rounded(7).items_center()
          .text_color(t.foreground)
          .when(i === this.at, (el) => el.bg(t.selected))
          .hover((s) => s.bg(t.hover))
          .on_click(() => this.choose(i))
          .child(icon(it))
          .child(div().flex_1().truncate().child(it.label))
          .child(div().text_size(11).text_color(t.dim).child(it.hint ?? "")))));
  }
}
