// A pane's header, for layouts that frame their panes:
//   { "tab": "active", "pane": { "header": { "content": { "mod": "pane-header" } } } }
// Shows the program's icon (the app's program table), the agent's name or
// the terminal's title, the folder, and the agent's status; buttons split, zoom and close
// this pane. Props from the app: { pane, terminal }. Click: focus the pane.
// Derived from Herdr's shipped `pane` mod: an agent (Claude Code, Codex,
// opencode) older than the one installed on its machine gets an OUTDATED badge
// and a button that restarts it on the new version, resuming the same session.

import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { panes, terminals, props, run, theme, home } from "herdr";
import { APPS, agentVersion, restartAgent } from "./lib/agents.js";
import { icon } from "./lib/ui.js";

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

export default class Pane extends View {
  init() { this.hovered = false; }

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

  render(cx) {
    const t = theme();
    const p = this.me();
    if (!p) return div();
    const name = ((p.program?.agent || p.program?.shell) && p.program.name) || p.title || p.program?.name || "shell";
    const pic = icon(p.program, 14, t.dim);
    const st = p.status;
    const pane = p.pane;
    const term = p.terminal && APPS[p.app] ? terminals().find((k) => k.address === p.terminal) : null;
    const { app, running, latest, outdated, session } = agentVersion(p.app, p.terminal, term?.labels, cx);
    const busy = st === "working" || st === "blocked";
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
