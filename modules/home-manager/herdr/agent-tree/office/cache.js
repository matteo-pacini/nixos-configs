// Claude's prompt cache, as its statusLine reports it (`agent.cache_until`,
// epoch seconds; 0 when the last response missed the cache), and the wall
// clock that counts it down above a cubicle. Other apps report no expiry and
// get no clock.

import { div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { ART, img } from "./art.js";

// The clock on the wall between the speech bubble and the name tag, relative
// to the cubicle; its 6×9 digits (art/clock/) sit from (5, 2) inside the frame.
const CLOCK = { x: 92, y: -32, w: 40, h: 12 };
// Digit colours: working (its cache keeps being refreshed), warm, expiring, cold.
const INK = { working: "#72977e", warm: "#a9e4b3", expiring: "#ffb86b", cold: "#f07c72" };

/**
 * The cache of the agent with terminal labels `labels` at `now` (ms):
 * null when its app reports none, else `{ left, cold }`, `left` being whole
 * minutes until it goes cold.
 */
export function cacheState(labels, now) {
  const until = parseInt(labels["agent.cache_until"], 10);
  if (Number.isNaN(until)) return null;
  const ms = until * 1000 - now;
  return { left: Math.max(0, Math.floor(ms / 60000)), cold: ms <= 0 };
}

/**
 * The wall clock for `cache` (from `cacheState`) of an agent with `status`;
 * `expiring` (main.js's cacheExpiring) makes it blink orange.
 */
export function cacheClock(cache, status, expiring) {
  const text = cache.cold ? "--:--" : `${String(Math.min(cache.left, 99)).padStart(2, "0")}:00`;
  const ink = INK[cache.cold ? "cold" : expiring ? "expiring" : status === "working" ? "working" : "warm"];
  const glyph = (c) => (c === ":" ? "colon" : c === "-" ? "dash" : c);
  const digits = h_flex().absolute().left(5).top(2)
    .children([...text].map((c) => svg(`${ART}/clock/clock-${glyph(c)}.svg`).w(6).h(9).flex_none().text_color(ink)));
  return div().absolute().left(CLOCK.x).top(CLOCK.y).w(CLOCK.w).h(CLOCK.h)
    .child(img(`${ART}/clock/clock-frame.svg`, { x: 0, y: 0, w: CLOCK.w, h: CLOCK.h }))
    .child(expiring ? digits.loop("opacity", { from: 0.15, to: 1, period: 1100 }) : digits);
}
