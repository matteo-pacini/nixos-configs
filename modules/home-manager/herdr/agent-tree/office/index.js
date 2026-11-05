// The Agents sidebar's Visualise dialog: every agent as a pixel-art worker in
// an office. This module is the dialog itself (its header, the pannable scene
// and the docked card); README.md maps the rest.
//
// The dialog is the agent-tree mod opened as an overlay with `{ office: true }`
// props: main.js's AgentTree view hands over to `officeInit` / `officeRender`,
// and the office keeps its state on that view.

import { div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { theme, closeOverlay, props } from "herdr";
import { floorPlan } from "./worktrees.js";
import { building } from "./building.js";
import { card } from "./card.js";
import { viewport, viewportInit } from "./viewport.js";

/** Sets up the office's state on `view`; call from the view's init. */
export function officeInit(view, cx) {
  // The agent whose card is open, and the screens read for blocked agents
  // that set no ask (address -> text; null while reading).
  view.open = null;
  view.screens = new Map();
  viewportInit(view);
  // Cache clocks and "since" times count in minutes.
  cx.timer.every(30000, (cx) => cx.notify());
}

/**
 * The dialog. `h`: what it borrows from main.js, `{ agentName(a),
 * blockedKid(a), duration(ms), band(t, pct, expiring), expiring(a, labels,
 * now), changedAt(address), MARK, ORANGE }`.
 */
export function officeRender(view, cx, h) {
  const t = theme();
  const now = Date.now();
  // The scene: what every part of the office is drawn with.
  const s = { t, view, cx, h, now };
  const { buildings, all, pending, worktrees } = floorPlan(cx, h.blockedKid);
  const needs = all.filter((e) => e.a.status === "blocked" || e.a.status === "done");
  const opened = all.find((e) => e.a.address === view.open);
  const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;

  const scene = h_flex().items_end().gap(28).p(28).flex_none()
    .children(buildings.map(([machine, floors]) => building(s, machine, floors)));

  return v_flex().id("office").size_full().min_h(0).bg("#1c2a38").text_color("#ece5d2")
    .child(h_flex().h(46).px(16).flex_none().gap(12).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .text_color(t.foreground)
      .child(div().text_size(15).font_semibold().child("Agents"))
      // Each click opens the next agent that needs the person.
      .when(needs.length > 0, (el) => el.child(div().id("office-needs").px(8).h(22).rounded(6).bg(t.blocked + "26")
        .text_color(t.blocked).text_size(12).font_medium().flex().items_center().cursor_pointer()
        .on_click((_e, cx) => {
          const i = needs.findIndex((e) => e.a.address === view.open);
          view.open = needs[(i + 1) % needs.length].a.address;
          cx.notify();
        })
        .child(`✋ ${needs.length} need${needs.length === 1 ? "s" : ""} you`)))
      .child(div().text_size(12).text_color(t.dim)
        .child(`${plural(all.length, "agent")} in ${plural(worktrees, "worktree")} on ${plural(buildings.length, "machine")}`))
      .when(pending > 0, (el) => el.child(div().text_size(12).text_color(t.dim).child("Finding worktrees…")))
      .child(div().flex_1())
      .child(div().id("office-close").size(26).rounded(6).flex().items_center().justify_center().cursor_pointer()
        .hover((st) => st.bg(t.hover)).on_click(() => closeOverlay(props().overlay))
        .child(svg("mods/workspace-chrome/x.svg").size(14).text_color(t.dim))))
    .child(div().relative().flex_1().min_h(0)
      .child(viewport(view, scene))
      .when(all.length === 0 && pending === 0, (el) => el.child(div().absolute().inset_0().flex().items_center().justify_center()
        .text_size(13).text_color(t.dim).child("No agents yet. They show up here when they report their status.")))
      .when(Boolean(opened), (el) => el.child(card(s, opened))));
}
