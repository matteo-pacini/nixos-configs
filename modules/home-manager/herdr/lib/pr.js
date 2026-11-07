// A GitHub pull request's status for the status bar: what `gh pr view` says
// about the branch checked out in a folder, boiled down to what the bar draws.
// No drawing here, so Node tests can load it.

import { exec } from "herdr";

/** The fields asked of `gh pr view --json`. */
export const FIELDS = "number,title,state,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,url,baseRefName";

// CheckRun conclusions that count as failed; SKIPPED and NEUTRAL count as nothing.
const FAILED = new Set(["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"]);

/** One entry of `statusCheckRollup` (a CheckRun or a StatusContext) as
 *  { name, url, result: "failed" | "running" | "passed" | null }. */
export function check(c) {
  if (c.__typename === "StatusContext") {
    const result = c.state === "SUCCESS" ? "passed" : c.state === "PENDING" || c.state === "EXPECTED" ? "running" : "failed";
    return { name: c.context, url: c.targetUrl || null, result };
  }
  const result = c.status !== "COMPLETED" ? "running" : c.conclusion === "SUCCESS" ? "passed" : FAILED.has(c.conclusion) ? "failed" : null;
  return { name: c.name, url: c.detailsUrl || null, result };
}

/** `gh pr view --json FIELDS` output as what the bar draws:
 *  { number, title, url, base (the branch it merges into),
 *    state: "open" | "draft" | "merged" | "closed",
 *    changes (changes requested), conflicts, checks: { failed: [{name, url}],
 *    running: [name], passed: n }, worst }.
 *  `worst` is the one glyph the checks segment leads with, the first of
 *  "failed", "running", "passed" that applies; null with no checks. Merged and
 *  closed PRs carry no checks, review or conflicts: they no longer matter. */
export function parse(json) {
  const state = json.state === "MERGED" ? "merged" : json.state === "CLOSED" ? "closed" : json.isDraft ? "draft" : "open";
  const live = state === "open" || state === "draft";
  const checks = { failed: [], running: [], passed: 0 };
  for (const c of live ? json.statusCheckRollup ?? [] : []) {
    const k = check(c);
    if (k.result === "failed") checks.failed.push({ name: k.name, url: k.url });
    else if (k.result === "running") checks.running.push(k.name);
    else if (k.result === "passed") checks.passed++;
  }
  const worst = checks.failed.length ? "failed" : checks.running.length ? "running" : checks.passed ? "passed" : null;
  return {
    number: json.number, title: json.title ?? "", url: json.url, base: json.baseRefName ?? null, state,
    changes: live && json.reviewDecision === "CHANGES_REQUESTED",
    conflicts: live && json.mergeStateStatus === "DIRTY",
    checks, worst,
  };
}

/** The checks segment's counts after the failed part: "5 passed", "4 passed · 2 running". */
export function counts(checks) {
  return [checks.passed && `${checks.passed} passed`, checks.running.length && `${checks.running.length} running`].filter(Boolean).join(" · ");
}

/** The checks segment's tooltip: failed then running checks, one per line,
 *  and what a click opens. null when nothing failed or runs. */
export function tooltip(checks) {
  const lines = [...checks.failed.map((c) => `Failed: ${c.name}`), ...checks.running.map((n) => `Running: ${n}`)];
  if (!lines.length) return null;
  return [...lines, checks.failed.length ? "Click: open the first failed check" : "Click: open the checks"].join("\n");
}

/** Where a click on the checks segment goes: the first failed check's page,
 *  else the PR's checks tab. */
export const checksUrl = (pr) => pr.checks.failed.find((c) => c.url)?.url ?? `${pr.url}/checks`;

/** Whether `origin` (a remote URL) is on github.com, over SSH or HTTPS. */
export const onGitHub = (origin) => /^(?:https?:\/\/(?:[^@/]+@)?|ssh:\/\/(?:[^@/]+@)?|[^@/]+@)github\.com[:/]/.test(origin ?? "");

/** The PR for the branch checked out at `cwd` on `on` (null: this computer):
 *  { pr } (parsed), { none: true } when the branch has none, or
 *  { unknown: true } when gh couldn't say (not installed, signed out,
 *  offline, rate limited), so the caller keeps what it had. */
export async function lookup(cwd, on) {
  try {
    // env: GH_PROMPT_DISABLED keeps gh from waiting on a question nobody sees.
    const r = await exec("env", ["GH_PROMPT_DISABLED=1", "gh", "pr", "view", "--json", FIELDS], { cwd, on });
    if (r.code === 0) return { pr: parse(JSON.parse(r.stdout)) };
    if (/no pull requests found/i.test(`${r.stderr}${r.stdout}`)) return { none: true };
    return { unknown: true };
  } catch {
    return { unknown: true };
  }
}

/** How long until the PR is asked about again: a minute while a check runs
 *  and the window is in front, else ten. */
export const nextDelay = (pr, active) => (active && pr?.checks.running.length ? 60_000 : 600_000);

/** How the focused terminal's place relates to its space's anchor (each a
 *  lib/git.js info, or null outside git): "same" (same checkout, any
 *  subfolder), "worktree" (another checkout of the same repo) or "repo". */
export function relation(here, anchor) {
  if (!here) return "same";
  if (!anchor || here.repo !== anchor.repo) return "repo";
  return here.top === anchor.top ? "same" : "worktree";
}
