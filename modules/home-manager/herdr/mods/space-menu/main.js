// The space right-click menu `space-cards` opens: the shipped `menu` mod's
// space items.
// Props: { tab: "space", target: { id }, overlay }.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, theme, keys, spaces, panes } from "herdr";
import { gitInfo } from "./lib/git.js";

const ROW = 31;

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

const shortcut = (name) => keys().find((b) => b.section === "global" && b.action === name)?.keys ?? "";

export default class SpaceMenu extends View {
  init(_props, cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.space = spaces().find((s) => s.id === props()?.target?.id);
    this.repo = null;
    if (!this.space) return;
    cx.spawn(async (cx) => {
      try {
        this.repo = (await gitInfo(place(this.space), this.space.machine)).info ?? null;
      } catch {}
      cx.notify();
    });
  }

  // An item is { label, icon, hint?, act, sep? }.
  items() {
    const s = this.space;
    if (!s) return [];
    const r = this.repo;
    const worktree = (label, action, size) => ({ label, icon: "git-branch",
      act: () => openOverlay({ mod: "worktree", kind: "dialog", ...size, props: { space: s.id, action } }) });
    return [
      { label: "Rename", icon: "square-pen", hint: shortcut("space.rename"), act: () => run("space.rename", { id: s.id }) },
      ...(r ? [worktree("New worktree", "new", { width: 440, height: 260 }), worktree("Open worktree", "open", { width: 560, height: 480 })] : []),
      ...(r?.linked ? [worktree("Remove worktree", "remove", { width: 440, height: 260 })] : []),
      { label: "Close", icon: "x", sep: true, hint: shortcut("space.close"), act: () => run("space.close", { id: s.id }) },
    ];
  }

  choose(i) {
    const it = this.items()[i];
    if (!it) return;
    closeOverlay(props()?.overlay);
    it.act();
  }

  render(cx) {
    const t = theme();
    const list = this.items();
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
        else if (e.key === "enter") this.choose(this.at);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => v_flex()
        .when(Boolean(it.sep) && i > 0, (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`sm-${i}`).h(ROW).px(8).gap(9).rounded(7).items_center()
          .text_color(t.foreground)
          .when(i === this.at, (el) => el.bg(t.selected))
          .hover((s) => s.bg(t.hover))
          .on_click(() => this.choose(i))
          .child(svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(t.muted))
          .child(div().flex_1().min_w(0).truncate().child(it.label))
          .child(div().text_size(11).text_color(t.dim).child(it.hint ?? "")))));
  }
}
