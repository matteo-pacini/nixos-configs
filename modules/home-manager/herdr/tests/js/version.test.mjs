import { test } from "node:test";
import assert from "node:assert/strict";
import { cmpVersion } from "../../lib/version.js";

test("orders parts numerically, not as text", () => {
  assert.equal(cmpVersion("2.1.318", "2.1.99"), 1);
  assert.equal(cmpVersion("0.9.0", "0.10.0"), -1);
});

test("a missing part counts as 0", () => {
  assert.equal(cmpVersion("1.2", "1.2.0"), 0);
  assert.equal(cmpVersion("1.2", "1.2.1"), -1);
});

test("splits on dashes too (nixpkgs versions like 2024-05-01)", () => {
  assert.equal(cmpVersion("2024-05-01", "2024-04-30"), 1);
  assert.equal(cmpVersion("1.0-2", "1.0-10"), -1);
});

test("equal versions compare 0", () => {
  assert.equal(cmpVersion("0.1.15", "0.1.15"), 0);
});
