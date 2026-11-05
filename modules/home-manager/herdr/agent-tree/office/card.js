// The card docked at the office's top right for the clicked agent: where it
// runs, its model, context and cache, and, while it's blocked, what it asks
// (the `agent.ask` label its app's hooks set; its screen when there is none),
// with buttons to go to its pane or peek at it.

import { div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { hc, run, shared, closeOverlay, props } from "herdr";
import { spriteFile } from "./art.js";
import { cacheState } from "./cache.js";

const STATUS = (t) => ({
  blocked: ["Needs you", t.blocked],
  done: ["Done", t.done ?? t.dim],
  working: ["Working", t.working],
  idle: ["Idle", t.dim],
});

/** The card for floor-plan entry `e` (worktrees.js). `s`: the scene (see index.js). */
export function card(s, e) {
  const { t, view, cx, h, now } = s;
  const { a, labels, machine, room: r, repo } = e;
  const [label, color] = STATUS(t)[a.status] ?? ["", t.dim];
  const expiring = h.expiring(a, labels, now);
  const pct = parseInt(labels["agent.ctx"], 10);
  const k = labels["agent.ctxk"];
  const band = h.band(t, pct, expiring);
  // Who asks: the agent, or the sub-agent it is waiting on.
  const asker = e.kid ?? a;
  const ask = (e.kid?.labels ?? labels)["agent.ask"];
  const detail = (e.kid?.labels ?? labels)["agent.ask_detail"];
  const when = h.changedAt(a.address);
  const fill = (() => {
    const c = (shared("space.colors") ?? {})[a.space] ?? "ansi6";
    return c.startsWith("#") ? c : (h.MARK[c] ?? t[c]);
  })();
  // A blocked agent whose app sets no agent.ask: show its screen instead.
  if (a.status === "blocked" && !ask && !view.screens.has(asker.address)) {
    view.screens.set(asker.address, null);
    cx.spawn(async (cx) => {
      const res = await hc(["read", "--lines", "14", asker.address]).catch(() => null);
      view.screens.set(asker.address, res?.code === 0 ? res.stdout.replace(/\s+$/, "") : "");
      cx.notify();
    });
  }
  if (a.status !== "blocked") view.screens.delete(asker.address);
  const screen = view.screens.get(asker.address);

  const chip = (...kids) => h_flex().flex_none().h(18).px(6).gap(4).rounded(5).bg(t.hover).items_center().children(kids);
  const meter = (iconName, title, pctFill, barColor, text, textColor) => h_flex().gap(8).items_center().text_size(10.5).text_color(t.dim)
    .child(h_flex().w(62).gap(4).items_center().child(svg(`mods/workspace-chrome/${iconName}.svg`).size(11)).child(title))
    .child(div().w(170).flex_none().h(6).rounded(3).bg(t.input)
      .child(div().h_full().rounded(3).bg(barColor).w(Math.round(170 * Math.max(0, Math.min(pctFill, 100)) / 100))))
    .child(div().w(76).text_right().text_color(textColor).child(text));
  const c = cacheState(labels, now);
  const cache = !c ? null : c.cold ? ["cold", t.ansi1] : c.left < 5 ? [`${c.left || "<1"}m left`, h.ORANGE] : [`${c.left}m left`, t.dim];

  return v_flex().id("office-card").absolute().top(12).right(12).w(380)
    .bg(t.popover).border(1).border_color(t.border).rounded(10).shadow_lg().text_color(t.foreground)
    .on_click((_e, cx) => cx.stop_propagation())
    .child(h_flex().gap(10).items_center().px(12).py(10).border_b(1).border_color(t.border)
      .child(image(spriteFile(a.status === "blocked" ? "raise" : a.status === "done" ? "cheer" : "stand", a.app)).w(30).h(42).flex_none())
      .child(div().flex_1().min_w(0).truncate().text_size(13.5).font_semibold().child(h.agentName(a)))
      .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(h.duration(now - when))))
      .child(div().flex_none().h(18).px(7).rounded(5).bg(color + "26").text_color(color).text_size(10.5).font_semibold()
        .flex().items_center().child(label))
      .child(div().id("office-card-close").size(22).rounded(5).flex().items_center().justify_center().cursor_pointer()
        .hover((st) => st.bg(t.hover)).on_click((_e, cx) => { view.open = null; cx.notify(); })
        .child(svg("mods/workspace-chrome/x.svg").size(12).text_color(t.dim))))
    .child(v_flex().gap(9).px(12).pt(10).pb(12)
      .child(h_flex().flex_wrap().gap(4).items_center().text_size(10.5).text_color(t.muted)
        .child(chip(svg(`mods/workspace-chrome/${machine ? "server" : "monitor"}.svg`).size(10).text_color(t.dim), machine ?? "This computer"))
        .child(chip(div().size(12).rounded(3).bg(fill).flex().items_center().justify_center().text_size(8).font_bold().text_color("#ffffff")
          .child([...(a.space_name ?? "")][0]?.toUpperCase() ?? "?"), a.space_name ?? ""))
        .child(chip(/^\d+$/.test(a.tab_name ?? "") ? `Tab ${a.tab_name}` : a.tab_name ?? ""))
        .child(chip(svg("mods/workspace-chrome/git-branch.svg").size(10).text_color(t.dim), r.top ? `${repo} @ ${r.name}` : "outside git")))
      .when(Boolean(labels["agent.model"]), (el) => el.child(h_flex().gap(6).items_center().text_size(11.5)
        .child(div().text_color(t.foreground).child(labels["agent.model"]))
        .when(Boolean(labels["agent.effort"]), (el) => el.child(div().h(16).px(5).rounded(4).border(1).border_color(t.dim)
          .text_size(10).text_color(t.dim).flex().items_center().child(labels["agent.effort"])))
        .child(div().flex_1())
        .child(div().text_size(10.5).text_color(t.dim).child(a.program?.name ?? ""))))
      .when(!Number.isNaN(pct), (el) => el.child(meter("layers", "Context", pct, band, k ? `${pct}% · ${k}k` : `${pct}%`, band)))
      // The bar is out of an hour, Claude's longest cache.
      .when(Boolean(cache), (el) => el.child(meter("clock", "Cache", c.left / 60 * 100, cache[1] === t.dim ? t.accent : cache[1], cache[0], cache[1])))
      .child(a.status === "blocked"
        ? v_flex().gap(4)
          .when(Boolean(e.kid), (el) => el.child(div().text_size(10.5).text_color(t.dim).child(`Sub-agent ${e.kid.name || e.kid.address} asks`)))
          .child(div().text_size(12.5).font_medium().child(ask || "Needs you"))
          .when(Boolean(detail), (el) => el.child(div().text_size(11.5).text_color(t.muted).child(detail)))
          .when(!ask && Boolean(screen), (el) => el.child(div().mt(2).p(8).rounded(6).bg(t.background)
            .text_size(10.5).font_family("monospace").text_color(t.muted).whitespace_normal().child(screen)))
        : div().text_size(12).text_color(t.dim).child(a.status === "working" ? "Busy, nothing needed from you."
          : a.status === "done" ? "Finished. Look at it to mark it read."
          : expiring ? "Idle; its prompt cache goes cold in a few minutes." : "Idle."))
      .child(h_flex().gap(6).pt(2)
        .child(div().id("office-go").h(28).px(10).rounded(7).bg(t.solid).text_color(t.solid_foreground).text_size(12).font_medium()
          .flex().items_center().cursor_pointer().hover((st) => st.opacity(0.88))
          .on_click(() => { run("pane.focus", { pane: a.pane }); closeOverlay(props().overlay); })
          .child("Go to pane"))
        .child(div().id("office-peek").h(28).px(10).rounded(7).border(1).border_color(t.input).bg(t.raised).text_size(12)
          .flex().items_center().cursor_pointer().hover((st) => st.bg(t.hover))
          .on_click(() => run("terminal.peek", { terminal: asker.address }))
          .child("Peek"))));
}
