// Upstream tags in a nixos-configs checkout (see its AGENTS.md):
//   WAIT-FOR <unstable|merged|closed|green|version|manual>: <ref>
//   WATCH: <url>
// and whether each one is ready to act on.

import { exec, readTextFile } from "herdr";

const TAG = /(WAIT-FOR (unstable|merged|closed|green|version|manual)|WATCH): (\S.*)$/;
// Only at the start of a comment line: code and strings that quote a tag
// (prompts.js does) aren't tags.
const GREP = "^[[:space:]]*(#|//|/?\\*|--)[[:space:]]*(WAIT-FOR (unstable|merged|closed|green|version|manual): |WATCH: https?://)";
const GITHUB = /github\.com\/([^/]+)\/([^/]+)\/(pull|issues|commit)\/([0-9a-f]+)/;
const HYDRA = /hydra\.nixos\.org\/job\/[^/]+\/[^/]+\/([^/.]+)\.[^/]+$/;

// Lower sorts first.
export const ORDER = { ready: 0, unknown: 1, waiting: 2, manual: 3, closed: 4, open: 5 };

export async function findTags(root, on) {
  const r = await exec("git", ["grep", "-n", "-E", GREP, "--", ".", ":!*.md"], { cwd: root, on });
  // git grep exits 1 when nothing matches.
  if (r.code > 1) throw new Error(r.stderr.trim() || "git grep failed");
  const tags = [], files = {};
  for (const out of r.stdout.split("\n")) {
    const at = /^([^:]+):(\d+):(.*)$/.exec(out), m = at && TAG.exec(at[3]);
    if (!m) continue;
    const rest = m[3].trim();
    tags.push({ file: at[1], line: Number(at[2]), kind: m[2] ?? "watch", rest, url: /^https?:\/\/\S+/.exec(rest)?.[0] ?? null });
  }
  for (const tag of tags) {
    files[tag.file] ??= (await readTextFile(`${root}/${tag.file}`, { on }).catch(() => "")).split("\n");
    tag.label = labelAfter(files[tag.file], tag.line);
  }
  return tags;
}

// Names a tag after the code it annotates: the first non-comment line below it.
function labelAfter(lines, line) {
  for (const text of lines.slice(line)) {
    const s = text.trim();
    if (!s || /^(#|\/\/|\/\*|\*|--)/.test(s)) continue;
    const patch = /\.\/patches\/([\w.-]+?)\.patch/.exec(s);
    if (patch) return patch[1];
    return /^\(?\s*([A-Za-z_][\w-]*)/.exec(s)?.[1] ?? s.slice(0, 30);
  }
  return "?";
}

export function shortRef(tag) {
  const url = tag.url;
  if (!url) return tag.kind === "version" ? tag.rest : "no link";
  const gh = GITHUB.exec(url);
  if (gh) {
    const repo = `${gh[1]}/${gh[2]}` === "NixOS/nixpkgs" ? "nixpkgs" : gh[2];
    return gh[3] === "commit" ? `${repo}@${gh[4].slice(0, 7)}` : `${repo}#${gh[4]}`;
  }
  const gl = /gitlab\.[^/]+\/(?:[^/]+\/)*([^/]+)\/-\/(merge_requests|issues)\/(\d+)/.exec(url);
  if (gl) return `${gl[1]}${gl[2] === "issues" ? "#" : "!"}${gl[3]}`;
  if (HYDRA.test(url)) return `hydra ${HYDRA.exec(url)[1]}`;
  return url.replace(/^https?:\/\//, "").slice(0, 40);
}

async function gh(path, args = []) {
  const r = await exec("gh", ["api", path, ...args]);
  if (r.code !== 0) throw new Error(r.stderr.trim().split("\n").pop() || "gh api failed");
  return r.stdout;
}
const ghJson = async (path) => JSON.parse(await gh(path));

// `version = "…"` of a pkgs/by-name package at a nixpkgs ref, or null.
async function pkgVersion(attr, ref) {
  try {
    const src = await gh(`repos/NixOS/nixpkgs/contents/pkgs/by-name/${attr.slice(0, 2)}/${attr}/package.nix?ref=${ref}`,
      ["-H", "Accept: application/vnd.github.raw"]);
    return /\bversion = "([^"]+)"/.exec(src)?.[1] ?? null;
  } catch {
    return null;
  }
}

function cmpVersion(a, b) {
  const x = a.split(/[.-]/).map(Number), y = b.split(/[.-]/).map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

const is = (state, text) => ({ state, text });

// Whether the tag's condition holds, as { state, text }.
export async function checkTag(tag) {
  try {
    if (tag.kind === "manual") {
      const checked = /\(checked ([^)]+)\)/.exec(tag.rest)?.[1];
      return is("manual", checked ? `manual · ${checked}` : "manual");
    }
    if (tag.kind === "version") {
      const m = /^([\w-]+)\s*>=\s*([\d.]+)/.exec(tag.rest);
      if (!m) return is("unknown", "bad version tag");
      const v = await pkgVersion(m[1], "nixos-unstable");
      if (!v) return is("unknown", `${m[1]} not in pkgs/by-name`);
      return cmpVersion(v, m[2]) >= 0 ? is("ready", `${v} in unstable`) : is("waiting", `${v} < ${m[2]}`);
    }
    if (!tag.url) return is("unknown", "no link");
    if (/gitlab\./.test(tag.url)) return is("unknown", "not checked: GitLab blocks scripts");
    if (tag.kind === "green") {
      const job = HYDRA.exec(tag.url);
      if (!job) return is("unknown", "not a Hydra job URL");
      const r = await exec("curl", ["-sfL", "-m", "20", "-H", "Accept: application/json", `${tag.url}/latest`]);
      // Hydra's /latest is the latest *successful* build.
      const green = r.code === 0 ? /-(\d[^-]*)$/.exec(JSON.parse(r.stdout).nixname ?? "")?.[1] : null;
      const master = await pkgVersion(job[1], "master");
      if (!green) return is("unknown", "Hydra unreachable");
      if (!master) return is("unknown", `last green ${green}`);
      return green === master ? is("ready", `green on ${master}`) : is("waiting", `last green ${green}, master ${master}`);
    }
    const m = GITHUB.exec(tag.url);
    if (!m) return is("unknown", "unsupported link");
    const [, owner, repo, type, id] = m, base = `repos/${owner}/${repo}`;
    if (tag.kind === "watch" || tag.kind === "closed") {
      const i = await ghJson(`${base}/issues/${id}`);
      if (i.state !== "closed") return is(tag.kind === "watch" ? "open" : "waiting", "open");
      const why = i.state_reason === "not_planned" ? "closed, not planned" : "closed";
      return is(tag.kind === "watch" ? "closed" : "ready", why);
    }
    // merged / unstable
    let sha = id;
    if (type === "pull") {
      const p = await ghJson(`${base}/pulls/${id}`);
      if (!p.merged) return is("waiting", p.state === "closed" ? "closed unmerged" : "not merged");
      if (tag.kind === "merged") return is("ready", "merged");
      sha = p.merge_commit_sha;
    }
    const status = (await gh(`${base}/compare/${sha}...nixos-unstable`, ["--jq", ".status"])).trim();
    return status === "ahead" || status === "identical"
      ? is("ready", "in nixos-unstable")
      : is("waiting", "merged, not in unstable");
  } catch (e) {
    return is("unknown", String(e.message ?? e).slice(0, 80));
  }
}
