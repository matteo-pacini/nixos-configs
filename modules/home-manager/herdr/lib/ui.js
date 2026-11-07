// Small pieces several mods draw or read the same way.

import { svg, image } from "gpui-kit";
import { exec, focused, layout, panes, spaces, window } from "herdr";

/** A program's icon (`program` as herdr reports it: { icon, tint }) at `size`
 *  px, tinted `color` when it's a tintable SVG; null when it has none. */
export function icon(program, size, color) {
  if (!program?.icon) return null;
  return program.tint ? svg(program.icon).size(size).flex_none().text_color(color) : image(program.icon).w(size).h(size).flex_none();
}

/** The node with `id` in a layout tree (as `layout()` returns it), or null. */
export function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

/** Whether the layout's `sidebar` is down to its icon rail. Goes by its width,
 *  not a flag: dragging its edge narrows it too. */
export const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

/** Opens `url` in the default browser; nothing when it's empty. */
export const openUrl = (url) => {
  if (url) exec(window()?.platform === "macos" ? "open" : "xdg-open", [url]);
};

/** Where the focused terminal is, resolved as the shipped `changes` mod does:
 *  { cwd, on (its machine, null for this one), space (the active space's id) }. */
export function location() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on, space: space?.id };
}
