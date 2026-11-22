import { test } from "node:test";
import assert from "node:assert/strict";
import { PING_EVERY_MS, isTime, labelsOf, verdict, wants } from "../../claude-mods/keep-warm/hooks/logic.js";
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
// event name, and every `hc` call it made, as its arguments.
function engine(env = { HC_TERMINAL_ID: "t56" }) {
  const handlers = {};
  const hcCalls = [];
  const $ = {
    env: { get: async (name) => env[name] },
    process: {
      run: async ([program, ...args]) => {
        assert.equal(program, "hc");
        hcCalls.push(args);
        return { exitCode: 0, stdout: "{}" };
      },
    },
    clock: { now: async () => NOW, every: () => {} },
  };
  register((name, handler) => { handlers[name] = handler; });
  const fire = (name, e = {}) => handlers[name]($, e, () => {});
  return { fire, hcCalls };
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
  const { fire, hcCalls } = engine({});
  await fire("session.start", { isInteractive: true });
  await fire("turn.complete");
  assert.deepEqual(hcCalls, []);
});
