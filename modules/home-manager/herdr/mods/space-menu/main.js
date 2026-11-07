// The space right-click menu `space-cards` opens: the shipped `menu` mod's
// space items, plus "Teleport to ›" while the space is on a branch other than
// its default and another machine is there to take it. That opens a second
// menu of machines, each with the clone it would use; picking one opens the
// `teleport` dialog. A space here teleports to a connected machine, a space
// on another machine back to this computer (lib/teleport.js: one side is
// always this one).
// Props: { tab: "space", target: { id }, overlay }; the second menu gets
// { teleport: { space } }.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, theme, keys, spaces, panes, hc } from "herdr";
import { repoOf, movable, cloneOn, homeOf, tilde } from "./lib/teleport.js";
import { HOSTS, SELF } from "./lib/hosts.js";

const ROW = 31;
const MACHINE_ROW = 44;
const label = (machine) => (HOSTS[(machine ?? SELF)?.toLowerCase()]?.label ?? machine ?? "This computer");
const device = (machine) => HOSTS[(machine ?? SELF)?.toLowerCase()]?.device ?? "server";

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

// hc's other machines, connected or not (asleep ones are listed, greyed).
async function otherMachines() {
  const r = await hc(["machine", "ls", "--json"]);
  return r.code === 0 ? (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary) : [];
}

// Where a space can teleport: from here to each other machine, from another
// machine only back here. { name (null: this computer), connected }.
function targets(space, machines) {
  return space.machine
    ? [{ name: null, connected: true }]
    : machines.map((m) => ({ name: m.name, connected: m.state === "connected" }));
}

const shortcut = (name) => keys().find((b) => b.section === "global" && b.action === name)?.keys ?? "";

export default class SpaceMenu extends View {
  init(_props, cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.space = spaces().find((s) => s.id === (props()?.teleport?.space ?? props()?.target?.id));
    this.repo = null;
    this.machines = [];
    this.clones = {}; // machine ("" for this computer) -> { path, home } | null, once looked at
    if (!this.space) return;
    cx.spawn(async (cx) => {
      try {
        this.repo = await repoOf(place(this.space), this.space.machine);
        this.machines = await otherMachines();
      } catch {}
      cx.notify();
      if (props()?.teleport && this.repo) await this.findClones(cx);
    });
  }

  async findClones(cx) {
    const fromHome = await homeOf(this.space.machine).catch(() => null);
    for (const m of targets(this.space, this.machines)) {
      if (!m.connected || !fromHome) { this.clones[m.name ?? ""] = null; continue; }
      this.clones[m.name ?? ""] = await cloneOn(this.repo, fromHome, m.name).catch(() => null);
      cx.notify();
    }
  }

  // An item is { label, icon, hint?, act, sep?, pink?, sub?, disabled? }.
  items() {
    const s = this.space;
    if (!s) return [];
    if (props()?.teleport) return this.machineItems();
    const r = this.repo;
    const canTeleport = movable(r) && targets(s, this.machines).some((m) => m.connected);
    const worktree = (label, action, size) => ({ label, icon: "git-branch",
      act: () => openOverlay({ mod: "worktree", kind: "dialog", ...size, props: { space: s.id, action } }) });
    return [
      { label: "Rename", icon: "square-pen", hint: shortcut("space.rename"), act: () => run("space.rename", { id: s.id }) },
      ...(r ? [worktree("New worktree", "new", { width: 440, height: 260 }), worktree("Open worktree", "open", { width: 560, height: 480 })] : []),
      ...(r?.linked ? [worktree("Remove worktree", "remove", { width: 440, height: 260 })] : []),
      ...(canTeleport ? [{ label: "Teleport to", icon: "teleport", pink: true, hint: "▸", act: () => this.openMachines() }] : []),
      { label: "Close", icon: "x", sep: true, hint: shortcut("space.close"), act: () => run("space.close", { id: s.id }) },
    ];
  }

  machineItems() {
    return targets(this.space, this.machines).map((m) => {
      const key = m.name ?? "";
      const clone = this.clones[key];
      const sub = !m.connected ? "asleep" : clone === undefined ? "looking for its clone…" : clone ? `clone at ${tilde(clone.path, clone.home)}` : "no clone of this repo";
      return { label: label(m.name), device: device(m.name), sub, disabled: !clone,
        act: () => openOverlay({ mod: "teleport", kind: "dialog", modal: true, width: 480, height: 560, props: { space: this.space.id, to: m.name } }) };
    });
  }

  openMachines() {
    const n = targets(this.space, this.machines).length;
    openOverlay({ mod: "space-menu", kind: "popup", width: 270, height: n * MACHINE_ROW + 40, props: { teleport: { space: this.space.id } } });
  }

  choose(i) {
    const it = this.items()[i];
    if (!it || it.disabled) return;
    closeOverlay(props()?.overlay);
    it.act();
  }

  render(cx) {
    const t = theme();
    const list = this.items();
    const machines = Boolean(props()?.teleport);
    const icon = (it) => it.device
      ? svg(`mods/space-cards/${it.device}.svg`).size(15).flex_none().text_color(it.disabled ? t.dim : t.muted)
      : svg(it.icon === "teleport" ? "mods/space-menu/teleport.svg" : `mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(it.pink ? t.ansi5 : t.muted);
    return v_flex()
      .id("space-menu")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .on_key_down((e, cx) => {
        if (!list.length) return;
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter" || (e.key === "right" && list[this.at]?.hint === "▸")) this.choose(this.at);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .when(machines && Boolean(this.repo?.branch), (el) => el.child(div().px(8).pt(4).pb(6).text_size(10.5).font_semibold().text_color(t.dim)
        .child(`${this.repo.branch.toUpperCase()} AS A WORKTREE ON`)))
      .children(list.map((it, i) => v_flex()
        .when(Boolean(it.sep) && i > 0, (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`sm-${i}`).h(it.sub ? MACHINE_ROW : ROW).px(8).gap(9).rounded(7).items_center()
          .text_color(it.disabled ? t.dim : it.pink ? t.ansi5 : t.foreground)
          .when(i === this.at && !it.disabled, (el) => el.bg(t.selected))
          .when(!it.disabled, (el) => el.hover((s) => s.bg(t.hover)))
          .on_click(() => this.choose(i))
          .child(icon(it))
          .child(v_flex().flex_1().min_w(0)
            .child(div().truncate().child(it.label))
            .when(Boolean(it.sub), (el) => el.child(div().truncate().text_size(11).text_color(t.dim).child(it.sub))))
          .child(div().text_size(11).text_color(t.dim).child(it.hint ?? "")))));
  }
}
