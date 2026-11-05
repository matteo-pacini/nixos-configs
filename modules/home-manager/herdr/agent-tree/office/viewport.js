// The office scene's viewport: the scene is dragged, or wheel-scrolled, around
// inside the dialog like a canvas, however small it is. Hand-made rather than a
// scroll container: GPUI's scrolls by wheel only, and only content that overflows.

import { div } from "gpui-kit";

// However far it's dragged, at least this many px of the scene stay in view.
const KEEP = 120;

/** Puts the state `viewport` keeps on `view`; call once from init. */
export function viewportInit(view) {
  // The scene's offset, the press a drag started from, whether that press has
  // moved (its release is then no click), and the viewport's and scene's sizes.
  view.pan = { x: 0, y: 0 };
  view.drag = null;
  view.moved = false;
  view.vp = null;
  view.size = null;
}

/**
 * True while the press that is ending was a drag: a click handler inside the
 * scene should ignore it.
 */
export const dragged = (view) => view.moved;

/** `scene` in a pannable viewport filling its parent. */
export function viewport(view, scene) {
  const clamp = () => {
    if (!view.vp || !view.size) return;
    view.pan.x = Math.min(view.vp.width - KEEP, Math.max(KEEP - view.size.width, view.pan.x));
    view.pan.y = Math.min(view.vp.height - KEEP, Math.max(KEEP - view.size.height, view.pan.y));
  };
  clamp();
  return div().id("office-viewport").size_full().overflow_hidden()
    .when(Boolean(view.drag && view.moved), (el) => el.cursor_grabbing())
    .on_size_change((size, cx) => { view.vp = size; cx.notify(); })
    .on_mouse_down("left", (e) => {
      view.drag = { x: e.position.x - view.pan.x, y: e.position.y - view.pan.y };
      view.moved = false;
    })
    .on_mouse_move((e, cx) => {
      if (!view.drag) return;
      const x = e.position.x - view.drag.x;
      const y = e.position.y - view.drag.y;
      // A few pixels of wobble is still a click.
      if (!view.moved && Math.abs(x - view.pan.x) + Math.abs(y - view.pan.y) < 4) return;
      view.moved = true;
      view.pan = { x, y };
      clamp();
      cx.notify();
    })
    .on_mouse_up("left", (_e, cx) => { view.drag = null; cx.notify(); })
    // No mouse_up arrives once the pointer has left: end the drag there.
    .on_hover((over) => { if (!over) view.drag = null; })
    .on_scroll_wheel((e, cx) => {
      view.pan.x += e.delta.x;
      view.pan.y += e.delta.y;
      clamp();
      cx.notify();
    })
    .child(div().id("office-scene").absolute().left(view.pan.x).top(view.pan.y)
      .on_size_change((size, cx) => { view.size = size; cx.notify(); })
      .child(scene));
}
