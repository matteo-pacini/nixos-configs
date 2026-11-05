// The office's architecture, drawn from worktrees.js's floor plan: a building
// per machine, a floor per repo (the Lobby last), a room per worktree (the main
// checkout first), cubicles side by side in one row per room.

import { div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { HEADROOM } from "./art.js";
import { cubicle } from "./cubicle.js";

/**
 * The building for `machine` (null: this computer) with `floors` (a repo name,
 * "" for the Lobby, -> its rooms). `s`: the scene (see index.js).
 */
export function building(s, machine, floors) {
  const order = [...floors.entries()].sort(([x], [y]) => (x === "" ? 1 : y === "" ? -1 : x.localeCompare(y)));
  return v_flex().flex_none().items_center()
    .child(h_flex().h(30).px(16).gap(8).items_center().bg("#344451").border(3).border_color("#172635").border_b(0)
      .text_color("#f2dfb5").text_size(12.5).font_semibold()
      .child(div().size(6).bg(machine ? "#e8b27d" : "#aed0a1"))
      .child(machine ?? "This computer"))
    .child(v_flex().border(3).border_color("#172635").bg("#455968")
      .children(order.map(([repo, rooms], i) => floor(s, repo, rooms, i))))
    .child(div().w_full().h(14).bg("#637583").border(3).border_t(0).border_color("#172635"));
}

function floor(s, repo, rooms, i) {
  const order = [...rooms.values()].sort((x, y) => (x.main !== y.main ? (x.main ? -1 : 1) : x.name.localeCompare(y.name)));
  return h_flex().items_stretch().when(i > 0, (el) => el.border_t(3).border_color("#172635"))
    .child(v_flex().w(112).flex_none().p(10).justify_center().gap(2).bg("#2d3e4c").border_r(3).border_color("#172635")
      .child(div().text_size(12.5).font_semibold().text_color("#e9dfc7").child(repo || "Lobby"))
      .child(div().text_size(10.5).text_color("#b4c1c5")
        .child(repo ? `${rooms.size} room${rooms.size === 1 ? "" : "s"}` : "outside git")))
    .child(h_flex().gap(8).p(8).items_stretch().children(order.map((r) => room(s, r))));
}

// A room's frame turns red while anyone in it is blocked.
function room(s, r) {
  const attn = r.agents.some((e) => e.a.status === "blocked");
  const [wall, ground] = !r.top ? ["#485467", "#56524b"] : r.main ? ["#485b60", "#515e57"] : ["#55536b", "#65584e"];
  return v_flex().flex_none().border(3).border_color(attn ? "#c0574c" : "#1f2b38").bg(ground)
    .child(h_flex().h(24).px(10).gap(8).items_center().bg("#1f2b38")
      .child(div().text_size(12).font_semibold().text_color("#ece5d2").child(r.name))
      .child(div().flex_1())
      .child(div().text_size(9.5).text_color("#9aa7ad").child(!r.top ? "" : r.main ? "CHECKOUT" : "WORKTREE")))
    .child(div().relative()
      // The wall: the upper part of the room behind the cubicles.
      .child(div().absolute().top(0).left(0).w_full().h(HEADROOM + 70).bg(wall))
      .child(div().absolute().top(HEADROOM + 70).left(0).w_full().h(4).bg("#252d38"))
      .child(h_flex().gap(12).px(14).pt(HEADROOM).pb(12)
        .children(r.agents.map((e) => cubicle(s, e)))));
}
