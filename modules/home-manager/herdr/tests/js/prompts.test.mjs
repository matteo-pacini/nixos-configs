import { test } from "node:test";
import assert from "node:assert/strict";
import { reviewPrompt } from "../../mods/nixpkgs-prs/prompts.js";
import { claudeAction, fixAll } from "../../mods/fleet/prompts.js";

const pr = (title) => ({ n: 1, title, author: "me", base: "master" });

test("reviewPrompt names the guidelines for the paths a PR touches", () => {
  const text = reviewPrompt(pr("foo: init at 1.0"), ["pkgs/by-name/fo/foo/package.nix", "maintainers/maintainer-list.nix"], null);
  assert.match(text, /"Reviewing contributions" › "New packages"/);
  assert.match(text, /pkgs\/by-name\/README\.md/);
  assert.match(text, /maintainers\/README\.md/);
  assert.doesNotMatch(text, /nixos\/README\.md/);
});

test("reviewPrompt: a bump is a package update; a module change gets the NixOS guide", () => {
  assert.match(reviewPrompt(pr("foo: 1.0 -> 1.1"), ["pkgs/by-name/fo/foo/package.nix"], null), /› "Package updates"/);
  const mod = reviewPrompt(pr("nixos/foo: add option"), ["nixos/modules/services/foo.nix", "nixos/tests/foo.nix"], null);
  assert.match(mod, /nixos\/README\.md/);
  assert.match(mod, /writing-nixos-tests/);
  assert.doesNotMatch(mod, /pkgs\/README\.md/);
});

test("reviewPrompt fetches from the checkout's remote when it has one, and caps the file list", () => {
  const files = Array.from({ length: 65 }, (_, i) => `pkgs/f${i}.nix`);
  const text = reviewPrompt(pr("x"), files, "upstream");
  assert.match(text, /git fetch upstream pull\/1\/head/);
  assert.match(text, /… and 5 more/);
  assert.match(reviewPrompt(pr("x"), [], null), /git fetch https:\/\/github\.com\/NixOS\/nixpkgs pull\/1\/head/);
});

const site = { file: "overlays/shared.nix", line: 3, label: "foo" };
const t = (kind, state, extra = {}) => ({ kind, rest: "https://github.com/a/b/pull/1", url: "https://github.com/a/b/pull/1", state, text: "x", sites: [site], label: "foo", ...extra });

test("claudeAction: fix when ready, check otherwise, nothing for an open WATCH", () => {
  assert.equal(claudeAction(t("merged", "ready")).label, "Fix in Claude Code");
  assert.equal(claudeAction(t("merged", "waiting")).label, "Check in Claude Code");
  assert.equal(claudeAction(t("watch", "open")), null);
  assert.equal(claudeAction(t("watch", "closed")).label, "Check in Claude Code");
});

test("prompts quote the tag in the AGENTS.md format and name its sites", () => {
  assert.match(claudeAction(t("merged", "ready")).text, /WAIT-FOR merged: https:\/\/github\.com\/a\/b\/pull\/1/);
  assert.match(fixAll([t("merged", "ready"), t("closed", "ready")]), /1\. overlays\/shared\.nix:3 .*\n2\. overlays\/shared\.nix:3 .*WAIT-FOR closed/);
});
