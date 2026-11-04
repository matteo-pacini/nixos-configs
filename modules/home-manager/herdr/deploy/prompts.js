// Prompts the Watch menu hands to a new Claude Code session at the checkout's
// root, for a tag as checkTag left it ({ kind, rest, url, file, line, sites,
// label, state, text }).

import { sitesText } from "./watch.js";

const tagLine = (tag) => (tag.kind === "watch" ? `WATCH: ${tag.rest}` : `WAIT-FOR ${tag.kind}: ${tag.rest}`);

// What to look at, by tag kind, for a tag that isn't ready.
function checkStep(tag) {
  if (tag.url && /gitlab\./.test(tag.url))
    return `${tag.url} can't be fetched by scripts; don't bypass that. Check the code instead (a GitHub mirror, the source in our pin), say the MR state is unverified, and ask me to paste it.`;
  switch (tag.kind) {
    case "unstable":
    case "merged":
      return `Follow ${tag.url}. If it's merged, find the merge commit and check whether the locked input contains it: \`gh api repos/NixOS/nixpkgs/compare/<sha>...<locked rev> --jq .status\` (ahead or identical means it does).`;
    case "closed":
      return `Follow ${tag.url}: look for new activity, a linked fix, or why it's stuck.`;
    case "version":
      return `Find the upstream release that fixes it, using the issue linked in the comment or the release notes. Check our pinned version with \`nix eval .#nixosConfigurations.<Host>.pkgs.<attr>.version\`, and look for any nixpkgs PR that bumps it, including staging. Say whether our patch would still apply to the incoming version.`;
    case "green":
      return `Query Hydra's JSON API for the job's latest builds (${tag.url}), find the failing step and why, check whether our pinned outPath is that build, and search nixpkgs for a fix PR. If there is one, propose \`WAIT-FOR merged: <PR>\`.`;
    case "manual": {
      const date = /\(checked ([^)]+)\)/.exec(tag.rest)?.[1];
      const look = tag.url
        ? `Check ${tag.url} for activity${date ? ` since ${date}` : ""}.`
        : "There's no link: search upstream (issues, PRs, latest release vs our pin) for anything that covers this.";
      return `${look} If nothing changed, propose only bumping the checked date to today. If an upstream ref now exists, propose a non-manual tag.`;
    }
  }
  return `Follow ${tag.url ?? "the links in the comment"}.`;
}

function check(tag) {
  if (tag.kind === "watch")
    return `${tag.url}, WATCHed at ${sitesText(tag)} (no workaround here), is now ${tag.text}.

Read the comment around the tag first. Find what closed it (fix version, flag, duplicate) and whether our pinned ${tag.label} contains it. Propose one of: delete the whole comment bullet, act on it here (describe the change), or point the tag at the successor issue.

Don't change any files.`;
  return `Check the upstream tag at ${sitesText(tag)}:
  ${tagLine(tag)}
The Watch panel says: ${tag.state}, ${tag.text}.

First read the whole comment around the tag and the code it guards. Don't change files, don't build unless an eval can't answer, and don't work around sites that block scripts.

${checkStep(tag)}

Report briefly: where upstream stands; whether the workaround is still needed with our pins (name the flake input the package comes from, e.g. masterPkgs → nixpkgs-master, and its locked rev); and any change you'd propose: a corrected tag in the AGENTS.md format, or comment text that has gone stale.`;
}

function fix(tag) {
  return `The tag at ${sitesText(tag)} reports its condition met:
  ${tagLine(tag)}  → ${tag.text}
Remove the workaround it guards, if it's really done.

1. Read the whole comment around the tag. If it states any other condition for removal (e.g. a runtime test), report it and stop.
2. Find the flake input the package comes from (e.g. masterPkgs → nixpkgs-master) and confirm that input's locked rev contains the fix. If it doesn't, say so and stop.
3. Remove the workaround and its comment, plus any patches, overlays or options only it used.
4. Verify as AGENTS.md › Verification describes: build for this platform, eval the rest, build aarch64-darwin on NightSprings. If the workaround fixes runtime behaviour, list the manual test I should run.
5. Show me the diff and the results. Don't commit or open a PR.`;
}

// One session for every ready tag: they usually share a flake input bump and
// one verification run.
export function fixAll(tags) {
  const list = tags.map((tag, i) => `${i + 1}. ${sitesText(tag)}  ${tagLine(tag)}  → ${tag.text}`).join("\n");
  return `These upstream tags report their condition met. Remove each workaround they guard, if it's really done:

${list}

For each tag:
- Read the whole comment around it. If it states another condition for removal (e.g. a runtime test), report it and skip that tag.
- Find the flake input the package comes from (e.g. masterPkgs → nixpkgs-master) and check that its locked rev contains the fix. If it doesn't, update only that input (nix flake update <input>) and say so.
- Remove the workaround and its comment, plus any patches, overlays, inputs or options only it used.

Then verify once for all of them, as AGENTS.md › Verification describes: build for this platform, eval the rest, build aarch64-darwin on NightSprings. List any manual runtime test I should run.
Show me the diff and the results. Don't commit or open a PR.`;
}

// { label, text } for the tag's Claude Code menu item, or null when there's
// nothing to ask: a WATCH whose issue is still open.
export function claudeAction(tag) {
  if (tag.kind === "watch") return tag.state === "closed" ? { label: "Check in Claude Code", text: check(tag) } : null;
  if (tag.state === "ready") return { label: "Fix in Claude Code", text: fix(tag) };
  return { label: "Check in Claude Code", text: check(tag) };
}
