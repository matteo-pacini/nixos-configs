// The space right-click menu `space-cards` opens: the shipped `menu` mod's
// space items, and "Back to <default branch>" (the back-to-master dialog).
// Props: { tab: "space", target: { id }, overlay }.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, theme, keys, spaces, panes, hc } from "herdr";
import { gitInfo } from "./lib/git.js";
import { MENU_PROBE, sh, fields, backItem } from "./lib/back.js";

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
    // undefined while git is asked; then { info }, { none }, { unsure } or { away: hint }.
    this.git = undefined;
    this.probe = null;
    if (!this.space) return;
    const where = place(this.space), on = this.space.machine;
    cx.spawn(async (cx) => {
      try {
        this.git = await gitInfo(where, on);
      } catch {
        this.git = { away: "asleep" };
        try {
          const r = await hc(["machine", "ls", "--json"]);
          const m = (JSON.parse(r.stdout).machines ?? []).find((x) => x.name === on);
          if (m?.state) this.git = { away: m.state.replace(/_/g, " ") };
        } catch {}
      }
      cx.notify();
    });
    cx.spawn(async (cx) => {
      try {
        const r = await sh(MENU_PROBE, where, on);
        if (r.code === 0) this.probe = fields(r.stdout);
      } catch {}
      cx.notify();
    });
  }

  // An item is { label, icon, hint?, line?, off?, act, sep? }. An item that
  // can't run stays, disabled, with why in its hint.
  items() {
    const s = this.space;
    if (!s) return [];
    const g = this.git;
    const r = g?.info;
    const why = g === undefined ? "checking\u2026" : g.away ?? (g.none ? "not a git repo" : g.unsure ? "git didn\u2019t answer" : "");
    const worktree = (label, action, size) => ({ label, icon: "mods/workspace-chrome/git-branch.svg", hint: why, off: Boolean(why),
      act: () => openOverlay({ mod: "worktree", kind: "dialog", ...size, props: { space: s.id, action } }) });
    const back = r && this.probe ? backItem(this.probe, s) : null;
    return [
      { label: "Rename", icon: "mods/workspace-chrome/square-pen.svg", hint: shortcut("space.rename"), act: () => run("space.rename", { id: s.id }) },
      worktree("New worktree", "new", { width: 440, height: 260 }),
      worktree("Open worktree", "open", { width: 560, height: 480 }),
      ...(r?.linked ? [worktree("Remove worktree", "remove", { width: 440, height: 260 })] : []),
      ...(back ? [{ label: back.label, icon: "mods/back-to-master/back.svg", sep: true, hint: back.hint, off: Boolean(back.hint),
        line: back.hint ? "" : "stash or commit, then switch",
        act: () => openOverlay({ mod: "back-to-master", kind: "dialog", modal: true, width: 440, height: 400, props: { space: s.id } }) }] : []),
      { label: "Close", icon: "mods/workspace-chrome/x.svg", sep: true, hint: shortcut("space.close"), act: () => run("space.close", { id: s.id }) },
    ];
  }

  choose(i) {
    const it = this.items()[i];
    if (!it || it.off) return;
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
        .child(h_flex().id(`sm-${i}`).h(it.line ? 44 : ROW).px(8).gap(9).rounded(7).items_center()
          .text_color(it.off ? t.dim : t.foreground)
          .when(i === this.at, (el) => el.bg(t.selected))
          .when(!it.off, (el) => el.hover((s) => s.bg(t.hover)).on_click(() => this.choose(i)))
          .child(svg(it.icon).size(14).flex_none().text_color(it.off ? t.dim : t.muted))
          .child(v_flex().flex_1().min_w(0)
            .child(div().truncate().child(it.label))
            .when(Boolean(it.line), (el) => el.child(div().truncate().text_size(11).text_color(t.dim).child(it.line))))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(it.hint ?? "")))));
  }
}
