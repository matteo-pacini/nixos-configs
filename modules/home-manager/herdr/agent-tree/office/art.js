// Where the office art is and where it goes. The cubicle layers in art/ share
// one 144×176 canvas and stack at the same spot; art/sprites holds one SVG per
// pose and app (rendered at build time by ../sprites/render.mjs). The rects
// below are positions on that canvas, in px, as the art was drawn to them.

import { image } from "gpui-kit";

/** The art folder, as `image()` and `svg()` paths resolve it (app-relative). */
export const ART = "mods/agent-tree/office/art";

export const CUBE = { w: 144, h: 176 };
/** The app badge on the chair back (seated) and on its side tag (turned round). */
export const BADGE_FRONT = { x: 63, y: 119, w: 18, h: 18 };
export const BADGE_BEHIND = { x: 28, y: 117, w: 18, h: 18 };
/** A 60×84 sprite seated facing the PC, and turned round to the room. */
export const SPRITE_BACK = { x: 42, y: 46, w: 60, h: 84 };
export const SPRITE_FACING = { x: 42, y: 66, w: 60, h: 84 };
/** Wall above a cubicle: room for its speech bubble, cache clock and name tag. */
export const HEADROOM = 88;
/** Below a cubicle: room for its context meter. */
export const METER = 28;

// Apps with their own sprite colours (../sprites/palettes.json).
const SPRITE_APPS = new Set(["claude-code", "codex", "opencode"]);

/** The sprite file for `pose` (a key of ../sprites/poses.json) and agent app `app`. */
export const spriteFile = (pose, app) => `${ART}/sprites/${pose}-${SPRITE_APPS.has(app) ? app : "agent"}.svg`;

/** `file` drawn absolutely at `rect` ({ x, y, w, h }). */
export const img = (file, rect) => image(file).absolute().left(rect.x).top(rect.y).w(rect.w).h(rect.h);

/** The cubicle layer art/`name`.svg, covering the whole canvas. */
export const layer = (name) => img(`${ART}/${name}.svg`, { x: 0, y: 0, ...CUBE });
