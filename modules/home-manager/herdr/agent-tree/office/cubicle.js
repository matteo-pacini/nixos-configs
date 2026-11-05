// One agent's cubicle: the desk, its PC screen, the agent in its pose, the app
// badge on the chair, and around it the name tag, speech bubble, cache clock
// and context meter. Working and idle agents face their PC (seen from behind);
// a blocked or done one turns round to the room.

import { div, svg } from "gpui-kit";
import { v_flex } from "gpui-base";
import { CUBE, BADGE_FRONT, BADGE_BEHIND, SPRITE_BACK, SPRITE_FACING, METER, spriteFile, img, layer } from "./art.js";
import { cacheState, cacheClock } from "./cache.js";
import { dragged } from "./viewport.js";

/**
 * The cubicle for floor-plan entry `e` (worktrees.js). Clicking it opens or
 * closes its card (`s.view.open`). `s`: the scene, `{ t, view, h, now }` (see
 * index.js).
 */
export function cubicle(s, e) {
  const { t, view, h, now } = s;
  const { a, labels } = e;
  const facing = a.status === "blocked" || a.status === "done";
  const sprite = (pose, rect) => img(spriteFile(pose, a.app), rect);
  const expiring = h.expiring(a, labels, now);
  const cache = cacheState(labels, now);
  const ask = a.status === "blocked" ? (e.kid?.labels ?? labels)["agent.ask"] : "";
  const say = a.status === "blocked" ? (ask || "Needs you") : a.status === "done" ? "Done!" : "";
  const icon = a.program?.icon;
  const badge = facing ? BADGE_BEHIND : BADGE_FRONT;
  const pct = parseInt(labels["agent.ctx"], 10);
  const k = labels["agent.ctxk"];
  const shown = view.open === a.address;

  return div().id(`cube-${a.address}`).relative().w(CUBE.w).h(CUBE.h + METER).flex_none().cursor_pointer()
    .on_click((_e, cx) => {
      if (dragged(view)) return;
      view.open = shown ? null : a.address;
      cx.notify();
    })
    .child(layer("cubicle"))
    .child(a.status === "working"
      ? div().absolute().left(0).top(0).size_full()
        .child(layer("screen-code-a"))
        .child(layer("screen-code-b").loop("opacity", { from: 0, to: 1, period: 900, easing: "linear" }))
      : layer(a.status === "blocked" ? "screen-ask" : a.status === "done" ? "screen-done" : "screen-off"))
    .when(facing, (el) => el.child(layer("chair-behind")))
    .child(a.status === "blocked" ? sprite("raise", SPRITE_FACING).loop("top", { from: SPRITE_FACING.y, to: SPRITE_FACING.y - 2, period: 900 })
      : a.status === "done" ? sprite("cheer", SPRITE_FACING)
      : a.status === "working" ? div().absolute().left(0).top(0).size_full()
        .child(sprite("backA", SPRITE_BACK))
        // Hands up and down: the second frame fades over the first.
        .child(sprite("backB", SPRITE_BACK).loop("opacity", { from: 0, to: 1, period: 500, easing: "linear" }))
      : sprite("backSleep", SPRITE_BACK))
    .when(!facing, (el) => el.child(layer("chair-front")))
    // opencode's mark is dark: it gets a light plate over the chair's own.
    .when(a.app === "opencode", (el) => el.child(div().absolute().left(badge.x - 1).top(badge.y - 1).size(badge.w + 2).bg("#eee8d7")))
    .when(Boolean(icon), (el) => el.child(a.program.tint
      ? svg(icon).absolute().left(badge.x).top(badge.y).size(badge.w).text_color("#ece5d2")
      : img(icon, badge)))
    // Name tag on the partition's top edge.
    .child(div().absolute().left(12).top(-20).w(CUBE.w - 24).h(18).px(5).rounded_t(2).flex().items_center().justify_center()
      .bg(a.status === "blocked" ? "#c0574c" : shown ? "#3e5366" : "#263443").border(1).border_b(0).border_color("#869798")
      .text_size(10.5).text_color("#ece5d2").child(div().truncate().child(h.agentName(a))))
    .when(Boolean(say), (el) => el.child(div().absolute().left(-8).top(-76).w(CUBE.w + 16).h(44).flex().items_end().justify_center()
      .loop("top", { from: -76, to: -79, period: 1100 })
      .child(div().max_w(CUBE.w + 16).px(8).py(4).rounded(4).border(2).border_color(a.status === "blocked" ? "#c0574c" : "#253342")
        .bg(a.status === "done" ? "#d8f5e2" : "#f7ecd1").text_color("#35313a").text_size(11).font_semibold()
        .child(div().child(say)))))
    .when(Boolean(cache), (el) => el.child(cacheClock(cache, a.status, expiring)))
    .when(a.status === "idle" && !expiring, (el) => el.child(div().absolute().left(98).top(34).text_size(12).font_bold().text_color("#c4cdd8")
      .loop("opacity", { from: 0.2, to: 1, period: 2400 }).child("z z")))
    // Context fill under the chair.
    .when(!Number.isNaN(pct), (el) => el.child(v_flex().absolute().left(12).top(CUBE.h + 2).w(CUBE.w - 24).gap(3).px(5).py(3)
      .rounded(2).bg("#253340").border(1).border_color("#788b8966")
      .child(div().relative().h(6).bg("#131e29")
        .child(div().absolute().left(0).top(0).h_full().w(Math.round((CUBE.w - 36) * Math.min(pct, 100) / 100)).bg(h.band(t, pct, expiring)))
        // Claude auto-compacts at 80%.
        .child(div().absolute().top(0).h_full().w(1).left(Math.round((CUBE.w - 36) * 0.8)).bg("#e1e4d566")))
      .child(div().text_size(10).text_color("#eee7d4").child(k ? `${pct}% · ${k}k` : `${pct}%`))));
}
