// Keep cache warm: a switch on a Claude Code terminal. While it's on,
// herdr-claude-keep-warm (scripts/claude-keep-warm.sh), on the terminal's own
// machine, refreshes the agent's prompt cache shortly before it expires.
// pane-header draws the switch and agent-list marks the agents that have it on.
// Everything goes through terminal labels: the person's switch (KEEP), the
// cache's expiry and lifetime from scripts/claude-statusline.sh, and what the
// service reports back.

import { hc, notify } from "herdr";

/** The switch: any value is on. */
export const KEEP = "agent.keep_warm";
const TTL = "agent.cache_ttl";
const STATE = "agent.warm_state";
const FAILED = "agent.warm_failed";
// Matches REFRESH_AT in scripts/claude-keep-warm.sh.
const REFRESH_AT_MIN = 10;

const SHORT_TIP = "This session's cache lasts 5 minutes.";

/** What pane-header's switch shows for a Claude Code terminal with `labels`
 *  whose agent is in `status`, at `now` (ms): { on, kind, text, tip }, or null
 *  for no switch (it's off, and the terminal reports no cache to keep).
 *  `kind`:
 *  - `off`: can be turned on;
 *  - `short`: off, and can't be turned on: its cache lasts 5 minutes;
 *  - `warm`: on, counting down to the next refresh;
 *  - `refreshing`: on, a refresh is running;
 *  - `working`: on, the agent's own requests keep the cache;
 *  - `paused`: on, but no refresh can run;
 *  - `cold`: on, and the cache has expired. */
export function warmth(labels, status, now) {
  const on = Boolean(labels?.[KEEP]);
  const ttl = labels?.[TTL];
  if (!on && !ttl) return null;
  const short = ttl === "5m";
  if (!on) return { on, kind: short ? "short" : "off", text: "Keep cache warm", tip: short ? SHORT_TIP : "" };
  const until = parseInt(labels["agent.cache_until"], 10) * 1000;
  const minutes = Math.floor((until - now) / 60000);
  const left = Number.isNaN(until) ? "" : ` · ${minutes < 1 ? "<1" : minutes}m`;
  const stop = `Refreshes at ${REFRESH_AT_MIN}m left. Click to stop.`;
  if (status === "working") return { on, kind: "working", text: "Warm", tip: stop };
  if (labels[STATE] === "refreshing") return { on, kind: "refreshing", text: "Refreshing", tip: stop };
  if (until <= now) return { on, kind: "cold", text: "Cache cold", tip: "Resumes at the agent's next turn. Click to stop." };
  if (status === "blocked") return { on, kind: "paused", text: `Warm paused${left}`, tip: "Paused while it needs you." };
  if (short) return { on, kind: "paused", text: `Warm paused${left}`, tip: SHORT_TIP };
  return { on, kind: "warm", text: `Warm${left}`, tip: stop };
}

/** Turns the switch on the terminal at `address` (`machine/t7` when remote)
 *  on or off. A failure is shown as a notification. */
export async function setWarm(address, on) {
  const r = await hc(["label", address, `${KEEP}=${on ? "1" : ""}`]);
  if (r.code !== 0) notify({ title: "Couldn't change keep cache warm", body: r.stderr || r.stdout, level: "error" });
}

/** The terminals (terminals() entries) where keeping warm gave up and nobody
 *  was told yet. `seen` maps an address to the failure already reported, and
 *  is updated: each failure comes back once. */
export function newWarmFailures(terms, seen) {
  return terms.filter((k) => {
    const stamp = k.labels?.[FAILED];
    if (!stamp || seen[k.address] === stamp) return false;
    seen[k.address] = stamp;
    return true;
  });
}
