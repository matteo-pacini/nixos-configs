// The Teleport dialog, opened from `space-menu`: what moving a space's branch
// to a worktree on another machine will do, with the choice to carry its
// uncommitted files, then doing it (lib/teleport.js) and opening a shell in a
// new space there. Agents in the space stay where they are.
// Props: { space, to } (`to`: an hc machine name, null for this computer).

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, theme, spaces, panes, agents, notify, settings } from "herdr";
import { repoOf, homeOf, cloneOn, movable, refusal, teleport, worktreePath, tilde } from "./lib/teleport.js";
import { HOSTS, SELF } from "./lib/hosts.js";

const label = (machine) => (HOSTS[(machine ?? SELF)?.toLowerCase()]?.label ?? machine ?? "This computer");

function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

export default class Teleport extends View {
  init(_props, cx) {
    this.handle = cx.focus_handle();
    this.handle.focus();
    this.bring = true;
    this.busy = false;
    this.error = "";
    this.ready = false;
    const space = spaces().find((s) => s.id === props()?.space);
    this.spaceId = space?.id;
    this.from = space?.machine ?? null;
    this.to = props()?.to ?? null;
    this.agents = agents().filter((a) => a.space === space?.id).length;
    cx.spawn(async (cx) => {
      try {
        if (!space) throw new Error("That space is gone.");
        const repo = await repoOf(place(space), this.from);
        if (!movable(repo)) throw new Error("Only a branch other than the default one can teleport.");
        const home = await homeOf(this.from);
        const clone = await cloneOn(repo, home, this.to);
        if (!clone) throw new Error(`${label(this.to)} has no clone of ${repo.name} at the same place, with the same origin.`);
        this.src = { on: this.from, home, repo, label: label(this.from) };
        this.dst = { on: this.to, home: clone.home, repo: clone.path, label: label(this.to) };
        this.error = (await refusal(this.src, this.dst)) ?? "";
        this.ready = !this.error;
      } catch (e) { this.error = String(e.message ?? e); }
      cx.notify();
    });
  }

  close() { closeOverlay(props().overlay); }

  go(cx) {
    if (!this.ready || this.busy) return;
    this.busy = true;
    this.error = "";
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const { worktree, warnings } = await teleport({
          src: this.src, dst: this.dst, bring: this.bring, self: SELF,
          closeSource: () => run("space.close", { id: this.spaceId, confirmed: true }),
        });
        this.close();
        // Unnamed, so it follows the worktree folder and nests under its repo there.
        run("space.new", { folder: worktree, ...(this.to ? { machine: this.to } : {}) });
        for (const w of warnings) notify({ title: "Teleported, with a problem", body: w, level: "warning" });
      } catch (e) {
        this.busy = false;
        this.error = String(e.message ?? e);
        cx.notify();
      }
    });
  }

  render(cx) {
    const t = theme();
    const r = this.src?.repo;
    const to = label(this.to), here = label(this.from);
    const mono = settings().font_family ?? "JetBrains Mono";
    const pink = t.ansi5;
    const field = (name, value) => h_flex().gap(10).items_start()
      .child(div().w(72).flex_none().text_color(t.dim).child(name))
      .child(div().flex_1().min_w(0).font_family(mono).text_size(11.5).text_color(t.foreground).child(value));
    const choice = (on, title, detail, pick) => h_flex().id(`tp-${title}`).gap(9).p(8).rounded(7).items_start().cursor_pointer()
      .border(1).border_color(on ? pink : t.border).when(on, (el) => el.bg(t.selected))
      .on_click((_e, cx) => { this.bring = pick; cx.notify(); })
      .child(div().mt(2).size(12).flex_none().rounded(6).border(on ? 4 : 1).border_color(on ? pink : t.dim))
      .child(v_flex().flex_1().min_w(0).gap(2)
        .child(div().text_color(t.foreground).child(title))
        .child(div().text_size(11.5).text_color(t.dim).child(detail)));
    const after = r?.linked ? `Here, the worktree ${tilde(r.top, this.src.home)} is removed.` : `Here, ${r?.name} switches back to ${r?.base}.`;
    const moves = this.from ? `fetched from ${here} over SSH, not through GitHub` : `pushed to ${to} over SSH, not to GitHub`;
    return v_flex()
      .id("teleport")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "escape" && !this.busy) this.close();
        else if (e.key === "enter") this.go(cx);
      })
      .size_full()
      .p(18)
      .gap(12)
      .bg(t.popover)
      .text_size(13)
      .child(h_flex().gap(9).items_center()
        .child(svg("mods/space-menu/teleport.svg").size(16).flex_none().text_color(pink))
        .child(div().font_semibold().text_color(t.foreground).child(`Teleport to ${to}`)))
      .when(!r && !this.error, (el) => el.child(div().text_color(t.muted).child("…")))
      .when(Boolean(r), (el) => el
        .child(div().text_color(t.muted).child(`${r.branch} moves to a worktree on ${to}. ${after}`))
        .child(v_flex().gap(3)
          .child(field("Branch", r.branch))
          .child(div().pl(82).text_size(11.5).text_color(t.dim).child(`${r.ahead} commit${r.ahead === 1 ? "" : "s"} ahead of ${r.base} · ${moves}`)))
        .when(r.files > 0, (el) => el
          .child(div().text_color(t.foreground).child(`${r.files} uncommitted file${r.files === 1 ? "" : "s"}`))
          .child(choice(this.bring, "Bring them along", `Applied on ${to}, still uncommitted. Here they go into a stash, in case.`, true))
          .child(choice(!this.bring, "Committed work only", r.linked
            ? `${to} starts at the last commit. The files go into a stash here.`
            : `${to} starts at the last commit. The files stay here, on ${r.base}.`, false)))
        .child(v_flex().gap(4).p(10).rounded(8).bg(t.background)
          .child(field("Repo", `${this.to ?? SELF}:${tilde(this.dst.repo, this.dst.home)}`))
          .child(field("Worktree", tilde(worktreePath(this.dst.home, r, r.branch), this.dst.home)))
          .child(field("Opens", `a shell in a new space on ${to}, nested under ${r.name}`)))
        .when(this.agents > 0, (el) => el.child(div().text_color(t.ansi3)
          .child(`${this.agents} agent${this.agents === 1 ? "" : "s"} in this space stay${this.agents === 1 ? "s" : ""} on ${here}.`))))
      .when(Boolean(this.error), (el) => el.child(div().text_color(t.blocked).child(this.error)))
      .child(div().flex_1())
      .child(h_flex().gap(8).justify_end()
        .child(div().id("tp-cancel").px(14).h(30).flex().items_center().rounded(7).border(1).border_color(t.border).text_color(t.foreground)
          .when(!this.busy, (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)).on_click(() => this.close()))
          .child("Cancel"))
        .child(div().id("tp-go").px(14).h(30).flex().items_center().rounded(7).font_semibold()
          .bg(this.ready && !this.busy ? pink : t.selected).text_color(this.ready && !this.busy ? t.background : t.dim)
          .when(this.ready && !this.busy, (el) => el.cursor_pointer().on_click((_e, cx) => this.go(cx)))
          .child(this.busy ? "Teleporting…" : "Teleport")));
  }
}
