import { test } from "node:test";
import assert from "node:assert/strict";
import { LOG_FILE, PING_EVERY_MS, isTime, labelsOf, logLine, verdict, wants } from "../../claude-mods/keep-warm/hooks/logic.js";
import { register } from "../../claude-mods/keep-warm/hooks/register.ts";

const NOW = 1795038000000;
// Labels as claude-statusline and the pane header's switch set them, with
// `minutes` of cache left by Claude Code's count.
const on = (minutes, more = {}) => ({
  "agent.keep_warm": "1", "agent.cache_ttl": "1h", "agent.cache_until": String(NOW / 1000 + minutes * 60), ...more,
});

test("isTime: 25 idle minutes, counted from the last turn or ping", () => {
  assert.equal(PING_EVERY_MS, 25 * 60 * 1000);
  assert.equal(isTime(NOW - PING_EVERY_MS + 1, NOW), false);
  assert.equal(isTime(NOW - PING_EVERY_MS, NOW), true);
});

test("wants: only a switched-on terminal with a live 1 h cache", () => {
  assert.equal(wants(on(35), NOW), "yes");
  assert.equal(wants(undefined, NOW), "off");
  assert.equal(wants(null, NOW), "off", "hc get failed");
  assert.equal(wants({ "agent.cache_ttl": "1h", "agent.cache_until": "1795040000" }, NOW), "off");
  assert.equal(wants(on(3, { "agent.cache_ttl": "5m" }), NOW), "short");
  assert.equal(wants({ "agent.keep_warm": "1" }, NOW), "short", "no response yet, so no cache to keep");
  assert.equal(wants(on(0), NOW), "cold");
  assert.equal(wants(on(-90), NOW), "cold");
  assert.equal(wants(on(0, { "agent.cache_until": "0" }), NOW), "cold", "the last response missed the cache");
});

test("wants: an expiry that can't be read isn't taken for an expired one", () => {
  const labels = on(35);
  delete labels["agent.cache_until"];
  assert.equal(wants(labels, NOW), "yes");
});

test("labelsOf: the labels in hc get's output", () => {
  // `hc get --json`, cut to what the mod reads.
  assert.deepEqual(labelsOf('{"address":"t7","labels":{"agent.keep_warm":"1"},"state":"live"}'), { "agent.keep_warm": "1" });
  assert.deepEqual(labelsOf('{"address":"t7","state":"live"}'), {});
  assert.equal(labelsOf(""), null);
  assert.equal(labelsOf('{"error":'), null);
});

// Usage as $.model.fork reported it in Claude Code 2.1.328.
const reply = (read, written, plain = 16) => ({
  isAnswered: true,
  usage: { input_tokens: plain, output_tokens: 4, cache_read_input_tokens: read, cache_creation_input_tokens: written },
});

test("verdict: a ping that read the conversation from the cache", () => {
  assert.equal(verdict(reply(71755, 0)), "warm");
  assert.equal(verdict(reply(253005, 0)), "warm");
  assert.equal(verdict(reply(68888, 27, 45)), "warm", "a few tokens written after the last turn");
});

test("verdict: a ping that found the cache gone wrote the conversation again", () => {
  assert.equal(verdict(reply(31074, 50904)), "cold");
  assert.equal(verdict(reply(32907, 219882)), "cold");
  assert.equal(verdict(reply(31074, 9000)), "cold", "a short conversation under a long system prompt");
  assert.equal(verdict(reply(0, 80000)), "cold");
});

test("verdict: no answer", () => {
  assert.equal(verdict(undefined), "failed", "the call threw");
  assert.equal(verdict({ isAnswered: false, reason: "api-error", usage: reply(0, 0).usage }), "failed");
  assert.equal(verdict({ isAnswered: false, reason: "nothing-to-fork" }), "failed");
});

// register.ts against a stand-in for Claude Code's mod engine: `handlers` by
// event name, every `hc` call it made as its arguments, every other command as
// { argv, stdin }, and `tick()` to run its timer with the clock at `at` (ms).
// `labels` are what `hc get` reports; `fork` answers $.model.fork.
function engine({ env = { HC_TERMINAL_ID: "t56", HOME: "/home/u" }, labels = {}, fork = async () => undefined } = {}) {
  const handlers = {};
  const hcCalls = [];
  const runs = [];
  let clock = NOW;
  let timer;
  const $ = {
    env: { get: async (name) => env[name] },
    process: {
      run: async ([program, ...args], init) => {
        if (program !== "hc") {
          runs.push({ argv: [program, ...args], stdin: init?.stdin });
          return { exitCode: 0, stdout: "" };
        }
        hcCalls.push(args);
        return { exitCode: 0, stdout: args[0] === "get" ? JSON.stringify({ labels }) : "{}" };
      },
    },
    clock: { now: async () => clock, every: (ms, f) => { timer = f; } },
    model: { fork },
    session: { id: async () => "3b02cc2a" },
  };
  register((name, handler) => { handlers[name] = handler; });
  const fire = (name, e = {}) => handlers[name]($, e, () => {});
  const tick = (at) => { clock = at; return timer(); };
  return { fire, tick, hcCalls, runs };
}

const CLEAR = ["label", "t56", "agent.warm_failed="];

test("register: a starting session clears the failure an earlier one left on the terminal", async () => {
  const { fire, hcCalls } = engine();
  await fire("session.start", { isInteractive: true });
  assert.deepEqual(hcCalls, [CLEAR]);
});

test("register: a turn clears the failure label though this session never stopped", async () => {
  const { fire, hcCalls } = engine();
  await fire("session.start", { isInteractive: true });
  hcCalls.length = 0;
  await fire("prompt.submit");
  await fire("turn.complete");
  assert.deepEqual(hcCalls, [CLEAR]);
});

test("register: outside a herdr-core terminal it calls nothing", async () => {
  const { fire, hcCalls } = engine({ env: {} });
  await fire("session.start", { isInteractive: true });
  await fire("turn.complete");
  assert.deepEqual(hcCalls, []);
});

test("logLine: an answered ping, with its verdict and the fork's token counts", () => {
  const usage = reply(32907, 219882).usage;
  assert.deepEqual(JSON.parse(logLine({ now: NOW + 999, terminal: "t56", session: "s1", reply: { ...reply(32907, 219882), text: "ok", effort: "high" }, state: "cold", stopped: true })), {
    at: NOW / 1000, terminal: "t56", session: "s1", state: "cold", stopped: true, effort: "high", usage,
  });
  assert.ok(logLine({ now: NOW, reply: reply(1, 0), state: "warm", stopped: false }).endsWith("}\n"), "one line each");
});

test("logLine: a ping with no answer says why", () => {
  const apiError = { isAnswered: false, reason: "api-error", status: 529, error: "overloaded", usage: reply(0, 0).usage };
  assert.deepEqual(JSON.parse(logLine({ now: NOW, terminal: "t56", reply: apiError, state: "failed", stopped: false })), {
    at: NOW / 1000, terminal: "t56", state: "failed", stopped: false, reason: "api-error", status: 529, error: "overloaded", usage: apiError.usage,
  });
  const threw = JSON.parse(logLine({ now: NOW, terminal: "t56", thrown: new Error("socket hang up"), state: "failed", stopped: true }));
  assert.equal(threw.reason, "threw");
  assert.equal(threw.error, "Error: socket hang up");
  assert.equal(threw.usage, undefined);
});

test("register: each ping appends its log line to the shared file", async () => {
  const forks = [reply(253005, 0), reply(32907, 219882)];
  const { fire, tick, runs, hcCalls } = engine({ labels: on(120), fork: async () => forks.shift() });
  await fire("session.start", { isInteractive: true });
  await tick(NOW + PING_EVERY_MS);
  await tick(NOW + 2 * PING_EVERY_MS);
  assert.equal(runs.length, 2);
  for (const run of runs) assert.deepEqual(run.argv.slice(0, 2).concat(run.argv.slice(3)), ["sh", "-c", "sh", `/home/u/${LOG_FILE}`]);
  const [first, second] = runs.map((run) => JSON.parse(run.stdin));
  assert.deepEqual([first.state, first.stopped, first.usage.cache_read_input_tokens], ["warm", false, 253005]);
  assert.deepEqual([second.state, second.stopped, second.usage.cache_creation_input_tokens, second.session], ["cold", true, 219882, "3b02cc2a"]);
  assert.deepEqual(hcCalls.at(-1), ["label", "t56", "agent.warm_state=", `agent.warm_failed=${(NOW + 2 * PING_EVERY_MS) / 1000}`]);
  await tick(NOW + 3 * PING_EVERY_MS);
  assert.equal(runs.length, 2, "stopped: no more pings, no more lines");
});

test("register: the second unanswered ping is logged as the one that stopped", async () => {
  const { fire, tick, runs } = engine({ labels: on(120), fork: async () => { throw new Error("socket hang up"); } });
  await fire("session.start", { isInteractive: true });
  await tick(NOW + PING_EVERY_MS);
  await tick(NOW + 2 * PING_EVERY_MS);
  assert.deepEqual(runs.map((run) => JSON.parse(run.stdin)).map((l) => [l.state, l.stopped, l.reason]), [["failed", false, "threw"], ["failed", true, "threw"]]);
});
