import { test } from "node:test";
import assert from "node:assert/strict";
import { mock } from "herdr";
import { findTags, checkTag, shortRef } from "../../mods/fleet/watch.js";

// Spelled from parts: a whole tag at the start of a line here would be one
// in this repo, listed in its own Watch panel.
const W = "WAIT-FOR", WATCH = "WATCH:";
const FILES = {
  "/r/flake.nix": `{
    # ${W} merged: https://github.com/NixOS/nixpkgs/pull/100
    foo-source.url = "github:x/foo";
  }`,
  "/r/overlays/shared.nix": `
    # ${W} merged: https://github.com/NixOS/nixpkgs/pull/100
    # (and more comment)
    foo = super.foo.overrideAttrs (o: { patches = [ ./patches/foo-fix.patch ]; });
    # ${WATCH} https://github.com/a/b/issues/7
    barbazquux = 1;`,
};
const GREP = [
  "flake.nix:2:    # WAIT-FOR merged: https://github.com/NixOS/nixpkgs/pull/100",
  "overlays/shared.nix:2:    # WAIT-FOR merged: https://github.com/NixOS/nixpkgs/pull/100",
  "overlays/shared.nix:5:    # WATCH: https://github.com/a/b/issues/7",
].join("\n");

test("findTags: one tag per condition and ref, every site kept, labelled by the code below", async () => {
  mock({
    exec: async () => ({ code: 0, stdout: GREP }),
    readTextFile: async (path) => FILES[path],
  });
  const tags = await findTags("/r", null);
  assert.equal(tags.length, 2);
  const [merged, watch] = tags;
  assert.equal(merged.kind, "merged");
  assert.deepEqual(merged.sites.map((s) => `${s.file}:${s.line}`), ["flake.nix:2", "overlays/shared.nix:2"]);
  assert.equal(merged.label, "foo-fix", "the shortest label: the patch name");
  assert.equal(watch.kind, "watch");
  assert.equal(watch.url, "https://github.com/a/b/issues/7");
  assert.equal(watch.label, "barbazquux");
});

test("findTags: no matches is no tags; a git failure throws", async () => {
  mock({ exec: async () => ({ code: 1, stdout: "", stderr: "" }) });
  assert.deepEqual(await findTags("/r", null), []);
  mock({ exec: async () => ({ code: 128, stdout: "", stderr: "fatal: not a git repository" }) });
  await assert.rejects(findTags("/r", null), /not a git repository/);
});

test("shortRef", () => {
  const ref = (url, kind = "merged", rest = url) => shortRef({ url, kind, rest });
  assert.equal(ref("https://github.com/NixOS/nixpkgs/pull/582675"), "nixpkgs#582675");
  assert.equal(ref("https://github.com/herdrdev/herdr-app/issues/12"), "herdr-app#12");
  assert.equal(ref("https://github.com/NixOS/nixpkgs/commit/0123456789abcdef"), "nixpkgs@0123456");
  assert.equal(ref("https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/9"), "mesa!9");
  assert.equal(ref("https://hydra.nixos.org/job/nixos/trunk/foo.x86_64-linux"), "hydra foo");
  assert.equal(shortRef({ url: null, kind: "version", rest: "foo >= 1.2" }), "foo >= 1.2");
});

// gh api answers by path, for checkTag.
const gh = (answers) => async (cmd, args) => {
  assert.equal(cmd, "gh");
  const path = args[1];
  const hit = Object.keys(answers).find((p) => path.startsWith(p));
  return hit ? { code: 0, stdout: answers[hit] } : { code: 1, stdout: "", stderr: `no answer for ${path}` };
};
const tag = (kind, url, rest = url) => ({ kind, url, rest });

test("checkTag merged/unstable: PR state, then whether nixos-unstable has the merge", async () => {
  const pr = "https://github.com/NixOS/nixpkgs/pull/100";
  mock({ exec: gh({ "repos/NixOS/nixpkgs/pulls/100": JSON.stringify({ merged: false, state: "open" }) }) });
  assert.deepEqual(await checkTag(tag("merged", pr)), { state: "waiting", text: "not merged" });

  mock({ exec: gh({ "repos/NixOS/nixpkgs/pulls/100": JSON.stringify({ merged: true, merge_commit_sha: "abc" }) }) });
  assert.deepEqual(await checkTag(tag("merged", pr)), { state: "ready", text: "merged" });

  mock({ exec: gh({
    "repos/NixOS/nixpkgs/pulls/100": JSON.stringify({ merged: true, merge_commit_sha: "abc" }),
    "repos/NixOS/nixpkgs/compare/abc...nixos-unstable": "behind\n",
  }) });
  assert.deepEqual(await checkTag(tag("unstable", pr)), { state: "waiting", text: "merged, not in unstable" });

  mock({ exec: gh({
    "repos/NixOS/nixpkgs/pulls/100": JSON.stringify({ merged: true, merge_commit_sha: "abc" }),
    "repos/NixOS/nixpkgs/compare/abc...nixos-unstable": "ahead\n",
  }) });
  assert.deepEqual(await checkTag(tag("unstable", pr)), { state: "ready", text: "in nixos-unstable" });
});

test("checkTag closed/watch: an issue's state, read the other way round for WATCH", async () => {
  const issue = "https://github.com/a/b/issues/7";
  mock({ exec: gh({ "repos/a/b/issues/7": JSON.stringify({ state: "closed", state_reason: "completed" }) }) });
  assert.deepEqual(await checkTag(tag("closed", issue)), { state: "ready", text: "closed" });
  assert.deepEqual(await checkTag(tag("watch", issue)), { state: "closed", text: "closed" });
  mock({ exec: gh({ "repos/a/b/issues/7": JSON.stringify({ state: "open" }) }) });
  assert.deepEqual(await checkTag(tag("closed", issue)), { state: "waiting", text: "open" });
  assert.deepEqual(await checkTag(tag("watch", issue)), { state: "open", text: "open" });
});

test("checkTag version: the by-name package's version in nixos-unstable", async () => {
  mock({ exec: gh({ "repos/NixOS/nixpkgs/contents/pkgs/by-name/he/herdr-desktop/package.nix": 'version = "0.1.13";' }) });
  assert.deepEqual(await checkTag(tag("version", null, "herdr-desktop >= 0.1.13")), { state: "ready", text: "0.1.13 in unstable" });
  assert.deepEqual(await checkTag(tag("version", null, "herdr-desktop >= 0.1.14")), { state: "waiting", text: "0.1.13 < 0.1.14" });
  assert.equal((await checkTag(tag("version", null, "nonsense"))).text, "bad version tag");
});

test("checkTag: manual and unfetchable links are never fetched", async () => {
  mock({});
  assert.deepEqual(await checkTag(tag("manual", null, "none (checked 2026-10-01)")), { state: "manual", text: "manual · 2026-10-01" });
  assert.equal((await checkTag(tag("merged", "https://gitlab.freedesktop.org/m/m/-/merge_requests/1"))).state, "unknown");
  assert.equal((await checkTag(tag("merged", null, "x"))).text, "no link");
});

test("checkTag: a gh failure is unknown, not a crash", async () => {
  mock({ exec: async () => ({ code: 1, stdout: "", stderr: "HTTP 403: rate limited" }) });
  assert.deepEqual(await checkTag(tag("closed", "https://github.com/a/b/issues/7")), { state: "unknown", text: "HTTP 403: rate limited" });
});
