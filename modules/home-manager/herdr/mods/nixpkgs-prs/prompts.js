// The prompt for a Claude Code review of a nixpkgs PR. It names the guideline
// files in the checkout that apply to the files the PR touches, so the agent
// reads the current conventions instead of recalling them.

const has = (files, re) => files.some((f) => re.test(f));

// Section names are headings in the checkout's docs; keep them in step if
// those files are reorganised.
function guides(pr, files) {
  const kind = /\binit at\b/i.test(pr.title) ? "New packages" : /->/.test(pr.title) ? "Package updates" : null;
  const out = [
    "CONTRIBUTING.md: \"How to review pull requests\", \"Review and Merge conventions\" and \"Commit conventions\" (check every commit message)",
  ];
  if (has(files, /^pkgs\//)) {
    out.push(`pkgs/README.md: "Reviewing contributions"${kind ? ` › "${kind}"` : ""} (its "Reviewed points" checklist is the backbone of the review), and "Conventions" (naming, versioning, meta, sources, patches, package tests)`);
    out.push("doc/languages-frameworks/<lang>.section.md for the builder each package uses (buildPythonPackage: python, buildGoModule: go, rustPlatform.buildRustPackage: rust, buildNpmPackage: javascript, and so on)");
  }
  if (has(files, /^pkgs\/by-name\//)) out.push("pkgs/by-name/README.md: the by-name layout and its CI checks");
  if (has(files, /^nixos\//)) out.push("nixos/README.md: \"Reviewing contributions\" (module updates or new modules)");
  if (has(files, /^nixos\/tests\//)) out.push("nixos/doc/manual/development/writing-nixos-tests.section.md");
  if (has(files, /^maintainers\/maintainer-list\.nix$/)) out.push("maintainers/README.md: new entries are sorted, complete, and their githubId matches `gh api users/<login> --jq .id`");
  if (has(files, /^lib\//)) out.push("lib/README.md");
  if (has(files, /^doc\//)) out.push("doc/README.md");
  if (has(files, /^ci\//)) out.push("ci/README.md");
  if (has(files, /release-notes/)) out.push("the release notes conventions in CONTRIBUTING.md › \"Release notes\"");
  return out;
}

/** The first message for a Claude Code session in the checkout at `root`.
 *  `pr`: { n, title, author, base }; `files`: the paths it changes;
 *  `remote`: the checkout's git remote for NixOS/nixpkgs, or null. */
export function reviewPrompt(pr, files, remote) {
  const repo = "--repo NixOS/nixpkgs";
  const shown = files.slice(0, 60).map((f) => `  ${f}`).join("\n");
  const more = files.length > 60 ? `\n  … and ${files.length - 60} more` : "";
  const fetch = remote ? `git fetch ${remote} pull/${pr.n}/head` : `git fetch https://github.com/NixOS/nixpkgs pull/${pr.n}/head`;
  return `Help me review nixpkgs PR #${pr.n}: ${pr.title}
https://github.com/NixOS/nixpkgs/pull/${pr.n} · by ${pr.author} · into ${pr.base}

Files changed:
${shown}${more}

1. Read the guidelines that apply, from this checkout, before the diff. Don't rely on memory, because nixpkgs conventions change:
${guides(pr, files).map((g) => `   - ${g}`).join("\n")}
2. Read the PR: \`gh pr view ${pr.n} ${repo} --comments\`, \`gh pr diff ${pr.n} ${repo}\`, \`gh pr view ${pr.n} ${repo} --json commits\` and \`gh pr checks ${pr.n} ${repo}\`. Earlier reviews count: don't repeat points already raised and resolved.
3. For a version bump, read upstream's changelog or release notes between the two versions, and look for breaking changes, new or dropped dependencies, and license changes.
4. Check the diff against the guidelines: meta (description, homepage, license, maintainers, mainProgram, changelog), sources and hashes, unrelated or formatting-only changes, tests (passthru.tests, versionCheckHook, NixOS tests), strictDeps and structuredAttrs where the guidelines call for them, and anything security-sensitive.
5. Leave this checkout as it is. If you need to evaluate or build, ${fetch}, put it in a temporary \`git worktree\`, and remove the worktree when you're done. For builds of many dependents, tell me to run nixpkgs-review instead.
6. Don't post, approve, request changes or push anything on GitHub.

Report back:
- Verdict: approve, approve with nits, or request changes, and why.
- Blocking issues, each with file:line and a suggested fix.
- Non-blocking suggestions, labelled as such (conventional comments).
- A draft review comment I can paste, using the "Reviewed points" template from the README that applies, ticking only what you actually checked.`;
}
