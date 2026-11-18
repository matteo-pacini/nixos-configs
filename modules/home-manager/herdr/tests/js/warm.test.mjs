import { test } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { KEEP, warmth, setWarm, newWarmFailures } from "../../lib/warm.js";

const NOW = 1795038000000;
// Labels as claude-statusline sets them, with `minutes` of cache left.
const labels = (minutes, more = {}) => ({
  "agent.cache_until": String(NOW / 1000 + minutes * 60), "agent.cache_ttl": "1h", ...more,
});
const on = (minutes, more = {}) => labels(minutes, { [KEEP]: "1", ...more });
const show = (l, status = "idle") => {
  const w = warmth(l, status, NOW);
  return w && `${w.kind}: ${w.text}`;
};

test("warmth: no switch on a terminal that reports no cache", () => {
  assert.equal(warmth(undefined, "idle", NOW), null);
  assert.equal(warmth({ "agent.model": "Fable 5.2" }, "idle", NOW), null);
});

test("warmth: off, by the cache's lifetime", () => {
  assert.deepEqual(warmth(labels(52), "idle", NOW), { on: false, kind: "off", text: "Keep cache warm", tip: "" });
  assert.deepEqual(warmth(labels(3, { "agent.cache_ttl": "5m" }), "idle", NOW),
    { on: false, kind: "short", text: "Keep cache warm", tip: "This session's cache lasts 5 minutes." });
});

test("warmth: on and idle counts the cache down", () => {
  assert.deepEqual(warmth(on(52), "idle", NOW),
    { on: true, kind: "warm", text: "Warm · 52m", tip: "Refreshes at 10m left. Click to stop." });
  assert.equal(show(on(52), "done"), "warm: Warm · 52m");
  assert.equal(show(on(0.5)), "warm: Warm · <1m");
  assert.equal(show({ [KEEP]: "1" }), "warm: Warm", "before the first response there is no expiry");
});

test("warmth: on, by what the agent and the service are doing", () => {
  assert.equal(show(on(52), "working"), "working: Warm");
  assert.equal(show(on(-5), "working"), "working: Warm", "a working agent's cache isn't cold");
  assert.equal(show(on(8, { "agent.warm_state": "refreshing" })), "refreshing: Refreshing");
  assert.equal(show(on(38), "blocked"), "paused: Warm paused · 38m");
  assert.equal(warmth(on(38), "blocked", NOW).tip, "Paused while it needs you.");
  assert.equal(show(on(3, { "agent.cache_ttl": "5m" })), "paused: Warm paused · 3m");
  assert.equal(warmth(on(3, { "agent.cache_ttl": "5m" }), "idle", NOW).tip, "This session's cache lasts 5 minutes.");
});

test("warmth: cold once the cache has expired, blocked or not", () => {
  assert.equal(show(on(-1)), "cold: Cache cold");
  assert.equal(show(on(0)), "cold: Cache cold");
  assert.equal(show(on(-1), "blocked"), "cold: Cache cold");
  assert.equal(show(on(-1, { "agent.cache_until": "0" })), "cold: Cache cold", "the last response missed the cache");
});

test("setWarm: sets and removes the label, remote terminals too", async () => {
  mock({ hc: () => ({ code: 0, stdout: "", stderr: "" }) });
  await setWarm("t7", true);
  await setWarm("nexus/t7", false);
  assert.deepEqual(calls, [
    ["hc", ["label", "t7", "agent.keep_warm=1"]],
    ["hc", ["label", "nexus/t7", "agent.keep_warm="]],
  ]);
});

test("setWarm: a failure is shown", async () => {
  mock({ hc: () => ({ code: 1, stdout: "", stderr: "no such terminal" }), notify: () => "n1" });
  await setWarm("t7", true);
  assert.deepEqual(calls.at(-1), ["notify", { title: "Couldn't change keep cache warm", body: "no such terminal", level: "error" }]);
});

test("newWarmFailures: each failure once, a later one again", () => {
  const seen = {};
  const terms = [
    { address: "t1", labels: on(5) },
    { address: "t2", labels: on(5, { "agent.warm_failed": "1795037000" }) },
    { address: "nexus/t2", labels: on(5, { "agent.warm_failed": "1795037100" }) },
    { address: "t3" },
  ];
  assert.deepEqual(newWarmFailures(terms, seen).map((k) => k.address), ["t2", "nexus/t2"]);
  assert.deepEqual(newWarmFailures(terms, seen), []);
  assert.deepEqual(seen, { t2: "1795037000", "nexus/t2": "1795037100" });
  terms[1].labels["agent.warm_failed"] = "1795040000";
  assert.deepEqual(newWarmFailures(terms, seen).map((k) => k.address), ["t2"]);
});
