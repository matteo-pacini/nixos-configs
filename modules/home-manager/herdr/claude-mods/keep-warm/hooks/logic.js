// The keep-warm mod's decisions, apart from the engine so that plain Node can
// test them (tests/js/keep-warm.test.mjs).

/** How long a session sits idle before each ping. Well inside the cache's
 *  hour: the expiry Claude Code reports moves an hour on after a ping whether
 *  or not the ping reached the cache, so it can't time the next one. */
export const PING_EVERY_MS = 25 * 60 * 1000;

/** The fork's question. It names no effort level, which would cost the cache
 *  on models that take effort per request; it asks for haste in words. */
export const PROMPT = "This is a keep-alive, not a question. You have no tools. Answer at once, without thinking it over, with the single word: ok";

/** The labels of the terminal `hc get --json` printed as `stdout`, or null
 *  when that isn't its output. */
export function labelsOf(stdout) {
  try {
    return JSON.parse(stdout).labels ?? {};
  } catch {
    return null;
  }
}

/** Whether a session idle since `lastActivityAt` (ms) is due a ping at `now`. */
export function isTime(lastActivityAt, now) {
  return now - lastActivityAt >= PING_EVERY_MS;
}

/** Whether the terminal with `labels` wants its cache kept at `now` (ms):
 *  "yes", or why not:
 *  - "off": the switch is off;
 *  - "short": the session's cache lasts 5 minutes, or it reports none yet;
 *  - "cold": the cache has expired, so a ping would pay for the whole
 *    conversation and renew nothing. */
export function wants(labels, now) {
  if (!labels?.["agent.keep_warm"]) return "off";
  if (labels["agent.cache_ttl"] !== "1h") return "short";
  const until = parseInt(labels["agent.cache_until"], 10) * 1000;
  if (!Number.isNaN(until) && until <= now) return "cold";
  return "yes";
}

/** What a fork's `reply` (a ModelForkResult, or undefined when the call threw)
 *  says of the cache:
 *  - "warm": the conversation was read from it;
 *  - "cold": the fork wrote the conversation again, so the cache had gone;
 *  - "failed": no answer came back. */
export function verdict(reply) {
  if (!reply?.isAnswered) return "failed";
  const usage = reply.usage ?? {};
  const read = usage.cache_read_input_tokens ?? 0;
  const written = usage.cache_creation_input_tokens ?? 0;
  const plain = usage.input_tokens ?? 0;
  // A ping on a warm cache writes nothing. The system prompt is cached apart
  // from the conversation and stays warm, so a cold ping still reads that much.
  return written * 10 > read + written + plain ? "cold" : "warm";
}

/** The ping log, under the home directory: one JSON object a line. */
export const LOG_FILE = ".local/state/herdr-keep-warm/pings.jsonl";

/** The log line, newline included, for the ping started at `now` (ms) on
 *  `terminal` in `session`: its `reply` (undefined when the fork threw
 *  `thrown`), the `state` verdict() made of it, and whether it `stopped` the
 *  pings. `at` is in epoch seconds, as agent.warm_failed is; `usage` is the
 *  fork's token counts in the API's spelling. */
export function logLine({ now, terminal, session, reply, thrown, state, stopped }) {
  return JSON.stringify({
    at: Math.floor(now / 1000),
    terminal,
    session,
    state,
    stopped,
    reason: reply === undefined ? "threw" : reply.isAnswered ? undefined : reply.reason,
    status: reply?.status,
    error: reply?.error ?? (thrown === undefined ? undefined : String(thrown)),
    effort: reply?.effort,
    usage: reply?.usage,
  }) + "\n";
}
