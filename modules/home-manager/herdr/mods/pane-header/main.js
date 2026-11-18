// A pane's header, for layouts that frame their panes:
//   { "tab": "active", "pane": { "header": { "content": { "mod": "pane-header" } } } }
// Shows the program's icon (the app's program table), the terminal's address,
// the agent's name (lib/name.js) or the terminal's title, the folder, and the
// agent's status; buttons split, zoom and close
// this pane. Props from the app: { pane, terminal }. Click: focus the pane.
// A Claude Code pane also gets the keep-cache-warm switch (lib/warm.js).
// Derived from Herdr's shipped `pane` mod: an agent (Claude Code, Codex,
// opencode) older than the one installed on its machine gets an OUTDATED badge
// and a button that restarts it on the new version, resuming the same session.

import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { panes, terminals, props, run, theme, home, settings } from "herdr";
import { APPS, agentVersion, restartAgent } from "./lib/agents.js";
import { icon } from "./lib/ui.js";
import { warmth, setWarm } from "./lib/warm.js";
import { paneName } from "./lib/name.js";

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

export default class Pane extends View {
  init(_props, cx) {
    this.hovered = false;
    // The switch counts the cache down in minutes.
    cx.timer.every(30000, (cx) => cx.notify());
  }

  me() {
    return panes().find((p) => p.pane === props()?.pane);
  }

  button(t, id, icon, command, args) {
    return div()
      .id(id)
      .p(3)
      .rounded(4)
      .text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run(command, args);
      })
      .child(svg(`mods/pane/${icon}.svg`).size(14));
  }

  // The keep-cache-warm switch; `w` is warmth()'s answer for this pane. Off,
  // it is only its flame until the pointer is on the header.
  warmSwitch(t, p, w) {
    const filled = ["warm", "refreshing", "working"].includes(w.kind);
    const bare = !w.on && !this.hovered;
    const color = filled ? t.ansi2 : w.kind === "cold" ? t.ansi3 : bare || w.kind === "short" ? t.dim : t.muted;
    return div().id(`ph-warm-${p.pane}`).flex_none().px(bare ? 3 : 8).h(20).rounded(6).flex().items_center().gap(5)
      .text_size(11).font_semibold().text_color(color)
      .when(filled, (el) => el.bg(t.ansi2 + "26"))
      .when(!filled && !bare, (el) => el.border_1().border_color(w.kind === "cold" ? t.ansi3 + "66" : w.kind === "short" ? t.border : t.input))
      .when(w.kind !== "short", (el) => el.cursor_pointer().hover((s) => s.bg(color + (filled ? "40" : "1a"))))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        if (w.kind !== "short") setWarm(p.terminal, !w.on);
      })
      .when(Boolean(w.tip), (el) => el.tooltip(w.tip))
      .child(w.kind === "refreshing"
        ? svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().spin(900)
        : svg("mods/pane-header/flame.svg").size(11).flex_none())
      .when(!bare, (el) => el.child(w.text));
  }

  render(cx) {
    const t = theme();
    const p = this.me();
    if (!p) return div();
    const pic = icon(p.program, 14, t.dim);
    const st = p.status;
    const pane = p.pane;
    const self = p.terminal ? terminals().find((k) => k.address === p.terminal) : null;
    const name = paneName(p, self);
    const term = APPS[p.app] ? self : null;
    const { app, running, latest, outdated, session } = agentVersion(p.app, p.terminal, term?.labels, cx);
    const busy = st === "working" || st === "blocked";
    const warm = p.app === "claude-code" && term ? warmth(term.labels, st, Date.now()) : null;
    return h_flex()
      .id(`pane-head-${pane}`)
      .size_full()
      .px(10)
      .gap(8)
      .items_center()
      .bg(t.background)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .on_hover((hovered, cx) => { this.hovered = hovered; cx.notify(); })
      .on_click(() => run("pane.focus", { pane }))
      .when(Boolean(pic), (el) => el.child(pic))
      .when(Boolean(p.terminal), (el) => el.child(div().flex_none().px(5).h(17).rounded(4).bg(t.hover).flex().items_center()
        .font_family(settings().font_family ?? "JetBrains Mono").text_size(10.5).text_color(t.muted).child(p.terminal)))
      .child(div().flex_none().truncate().max_w(260).font_medium().text_color(t.foreground).child(name))
      .when(outdated, (el) => el
        .child(div().id(`ph-old-${pane}`).flex_none().px(6).h(17).rounded(4).bg(t.ansi3 + "26").flex().items_center()
          .text_size(10).font_bold().text_color(t.ansi3).child("OUTDATED")
          .tooltip(`${app?.name} ${running} is running; ${latest} is installed.`))
        .when(Boolean(session), (el) => el.child(div().id(`ph-restart-${pane}`).flex_none().px(8).h(20).rounded(6)
          .border_1().border_color(t.ansi3 + "66").flex().items_center().text_size(11).font_semibold()
          .text_color(busy ? t.dim : t.ansi3)
          .when(!busy, (el) => el.cursor_pointer().hover((s) => s.bg(t.ansi3 + "1a"))
            .on_click((_e, cx) => { cx.stop_propagation(); restartAgent(p.terminal, app, session); }))
          .tooltip(busy ? "Wait until it's idle" : "Exit and resume this session on the installed version")
          .child(`Restart on ${latest}`))))
      .child(div().flex_1().truncate().text_color(t.dim).child(folder(p.cwd)))
      .when(Boolean(warm), (el) => el.child(this.warmSwitch(t, p, warm)))
      .when(st === "working", el => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)))
      .when(st === "blocked", el => el.child(div().flex_none().px(6).h(18).flex().items_center().rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).child("Needs you")))
      .when(st === "done", el => el.child(div().size(7).flex_none().rounded(4).bg(t.done)))
      .when(this.hovered, el => el
        .child(this.button(t, `ph-r-${pane}`, "split-right", "pane.split", { direction: "right", pane }))
        .child(this.button(t, `ph-d-${pane}`, "split-down", "pane.split", { direction: "down", pane }))
        .child(this.button(t, `ph-z-${pane}`, p.zoomed ? "unzoom" : "zoom", "pane.zoom", { pane }))
        .child(this.button(t, `ph-x-${pane}`, "close", "pane.close", { pane })));
  }
}
