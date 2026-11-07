// Open NixOS/nixpkgs PRs that involve me: review requested, mentioned, or
// otherwise participating. The `nixpkgs-prs` block of the layout, shown only
// while the focused terminal is in a nixpkgs checkout (NixOS/nixpkgs or any
// fork, worktrees included; any machine). Click opens a PR in the browser;
// right-click starts nixpkgs-review or a Claude Code review in a new tab of
// that space. Merged or closed PRs drop out at the next refresh.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Input, InputState, Textarea, TextareaState } from "gpui-base";
import { exec, theme, run, focused, settings, openOverlay, closeOverlay, props, shared, setShared, readTextFile } from "herdr";
import { location, openUrl } from "./lib/ui.js";
import { reviewPrompt } from "./prompts.js";

const BLOCK = "nixpkgs-prs";
const NIXPKGS = /[:/][^/:\s]+\/nixpkgs(\.git)?\/?$/;
const UPSTREAM = /[:/]NixOS\/nixpkgs(\.git)?\/?$/i;
// One GraphQL call, five searches.
const REFRESH_MS = 5 * 60000;
// While a PR sits in the merge queue, so it drops out soon after it merges.
const QUEUED_REFRESH_MS = 60000;
const LAST = "nixpkgs-prs.last";

// ---- GitHub ----

const FIELDS = "number title isDraft updatedAt reviewDecision baseRefName author { login } labels(first: 30) { nodes { name } } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } mergeQueueEntry { state position }";
// Keys double as the reasons a PR is listed. `involves` covers authored and commented.
const SEARCHES = {
  requested: "review-requested:@me",
  assigned: "assignee:@me",
  mentioned: "mentions:@me",
  reviewed: "reviewed-by:@me",
  involved: "involves:@me",
};
const QUERY = `{ ${Object.entries(SEARCHES).map(([key, q]) =>
  `${key}: search(query: "is:pr is:open archived:false repo:NixOS/nixpkgs ${q}", type: ISSUE, first: 100) { nodes { ... on PullRequest { ${FIELDS} } } }`).join(" ")} }`;

async function graphql(query) {
  const r = await exec("gh", ["api", "graphql", "-f", `query=${query}`]);
  if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim().split("\n").pop() || `gh exited ${r.code}`);
  return JSON.parse(r.stdout).data;
}

const toPR = (n) => ({
  n: n.number, title: n.title, draft: n.isDraft, updated: Date.parse(n.updatedAt), decision: n.reviewDecision,
  base: n.baseRefName, author: n.author?.login ?? "ghost", labels: n.labels.nodes.map((l) => l.name),
  ci: n.commits.nodes[0]?.commit.statusCheckRollup?.state ?? null, queue: n.mergeQueueEntry, why: [],
});

/** Any NixOS/nixpkgs PR by number, open or not. Rejects if there is none. */
async function fetchPR(number) {
  const data = await graphql(`{ repository(owner: "NixOS", name: "nixpkgs") { pullRequest(number: ${number}) { ${FIELDS} } } }`);
  return toPR(data.repository.pullRequest);
}

async function fetchPRs() {
  const byNumber = new Map();
  for (const [why, res] of Object.entries(await graphql(QUERY))) {
    for (const n of res.nodes) {
      if (!n?.number) continue;
      const pr = byNumber.get(n.number) ?? toPR(n);
      pr.why.push(why);
      byNumber.set(n.number, pr);
    }
  }
  return [...byNumber.values()].sort((a, b) => b.updated - a.updated);
}

const url = (n) => `https://github.com/NixOS/nixpkgs/pull/${n}`;

function ago(t) {
  const m = (Date.now() - t) / 60000;
  if (m < 60) return `${Math.max(1, Math.round(m))}m`;
  if (m < 1440) return `${Math.round(m / 60)}h`;
  if (m < 86400) return `${Math.round(m / 1440)}d`;
  return `${Math.round(m / 43200)}mo`;
}

// ---- Nix ----

// This machine's system and extra-platforms, and its remote builders, from
// `nix config show` on the machine the review would run on. `builders` may
// name a machines file (`@/etc/nix/machines`).
async function nixConfig(on) {
  const get = async (key) => {
    const r = await exec("nix", ["config", "show", key], { on }).catch(() => null);
    return r?.code === 0 ? r.stdout.trim() : "";
  };
  const [system, extra, builders] = await Promise.all([get("system"), get("extra-platforms"), get("builders")]);
  const spec = builders.startsWith("@") ? (await readTextFile(builders.slice(1), { on }).catch(() => null)) ?? "" : builders;
  const machines = spec.split(/[;\n]/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#")).map((line) => {
    const f = line.split(/\s+/);
    const host = f[0].replace(/^[a-z-]+:\/\//, "").replace(/^[^@]*@/, "").replace(/[:/].*$/, "");
    return {
      name: host.split(".")[0], line,
      systems: f[1] && f[1] !== "-" ? f[1].split(",") : [system],
      jobs: Number(f[3]) || 1,
    };
  });
  return { system, extra: extra.split(/\s+/).filter(Boolean), machines };
}

// Splits the free-text field into arguments. Quotes group words; there is no
// escaping, which nixpkgs-review's own flags never need.
function words(s) {
  const out = [], re = /"([^"]*)"|'([^']*)'|(\S+)/g;
  let m;
  while ((m = re.exec(s))) out.push(m[1] ?? m[2] ?? m[3]);
  return out;
}
const quote = (a) => (/^[\w@%+=:,./#-]+$/.test(a) ? a : `'${a.replace(/'/g, "'\\''")}'`);

// What the dialog's choices mean as nixpkgs-review 4 flags.
const RESULTS = [
  { id: "nothing", label: "Nothing", about: "report only", flags: [] },
  { id: "post", label: "Post result", about: "comment on the PR", flags: ["--post-result"] },
  { id: "approve", label: "Post + approve", about: "approves if all builds pass", flags: ["--post-result", "--approve-pr"] },
  { id: "merge", label: "Post + approve + merge", about: "merges if all builds pass", flags: ["--post-result", "--approve-pr", "--merge-pr"] },
];

// ---- Drawing helpers ----

const button = (t, id, text, primary, action, disabled = false) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
  .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
  .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium()
  .when(disabled, (el) => el.opacity(0.45))
  .when(!disabled, (el) => el.cursor_pointer().hover((s) => s.opacity(0.88)).on_click(action))
  .child(text);

const tick = (t, on, round) => round
  ? div().size(13).flex_none().rounded(7).border(1.5).border_color(on ? t.accent : t.input).flex().items_center().justify_center()
    .child(on ? div().size(6).rounded(3).bg(t.accent) : div())
  : div().size(13).flex_none().rounded(3).border(1.5).border_color(on ? t.accent : t.input).bg(on ? t.accent : t.background)
    .flex().items_center().justify_center()
    .child(on ? svg("mods/workspace-chrome/check.svg").size(10).text_color(t.accent_foreground) : div());

const chip = (t, text, color) => div().flex_none().h(16).px(5).rounded(4).bg(color + "26").text_color(color)
  .text_size(10).font_semibold().flex().items_center().child(text);

const MENU = [
  { id: "open", label: "Open in browser", icon: "search" },
  { id: "review", label: "nixpkgs-review…", icon: "layers" },
  { id: "claude", label: "Review in Claude Code…", icon: "terminal" },
];

export default class NixpkgsPRs extends View {
  init(_props, cx) {
    if (props()?.menu) return this.initMenu(cx);
    if (props()?.review) return this.initReview(cx);
    if (props()?.claude) return this.initClaude(cx);
    this.prs = null;
    this.lookup = InputState.new({ placeholder: "PR # or link" });
    this.lookup.on("submit", (_e, cx) => this.lookUp(cx));
    this.collapsed = JSON.parse(localStorage.getItem("collapsed") ?? "{}");
    this.follow(cx);
    // A hidden block isn't rendered, so only a timer can show it again.
    cx.timer.every(1000, (cx) => this.follow(cx));
    cx.timer.every(QUEUED_REFRESH_MS, (cx) => {
      if (!this.shown) return;
      const queued = this.prs?.some((p) => p.queue);
      if (queued || Date.now() - (this.fetched ?? 0) >= REFRESH_MS) this.refresh(cx);
    });
  }

  // Shows the block in a nixpkgs checkout and hides it elsewhere. Acts only
  // when the location changes, so a manual `layout.toggle` sticks until then.
  follow(cx) {
    const loc = location(), where = JSON.stringify(loc);
    if (where === this.where) return;
    this.where = where;
    cx.spawn(async (cx) => {
      let repo = null;
      if (loc.cwd) {
        try {
          const git = (...a) => exec("git", ["-C", loc.cwd, ...a], { on: loc.on });
          const remotes = await git("remote", "-v");
          const lines = remotes.code === 0 ? remotes.stdout.split("\n").map((l) => l.split(/\s+/)) : [];
          if (lines.some(([, u]) => u && NIXPKGS.test(u))) {
            const root = (await git("rev-parse", "--show-toplevel")).stdout.trim();
            repo = { root, on: loc.on, space: loc.space, remote: lines.find(([, u]) => u && UPSTREAM.test(u))?.[0] ?? null };
          }
        } catch {}
      }
      if (this.where !== where) return;
      run(repo ? "layout.show" : "layout.hide", { id: BLOCK });
      if (repo && !this.shown) this.refresh(cx);
      this.shown = Boolean(repo);
      if (repo) this.repo = repo;
      cx.notify();
    });
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        this.prs = await fetchPRs();
        this.error = null;
        this.fetched = Date.now();
      } catch (e) {
        this.error = String(e.message ?? e);
      }
      this.loading = false;
      cx.notify();
    });
  }

  // The header's PR field: "583697", "#583697" or a PR link opens that PR's
  // right-click menu, whether or not it involves me.
  lookUp(cx) {
    const number = /(\d+)\D*$/.exec(this.lookup.value())?.[1];
    if (!number) { this.lookupError = "Type a PR number or link"; cx.notify(); return; }
    this.lookupError = null;
    this.lookingUp = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const pr = await fetchPR(number);
        this.lookup.set_value("");
        this.openMenu(pr);
      } catch (e) {
        this.lookupError = `#${number}: ${e.message ?? e}`;
      }
      this.lookingUp = false;
      cx.notify();
    });
  }

  toggle(key, cx) {
    this.collapsed[key] = !this.collapsed[key];
    localStorage.setItem("collapsed", JSON.stringify(this.collapsed));
    cx.notify();
  }

  // ---- Panel ----

  openMenu(pr) {
    if (!this.repo) return;
    openOverlay({ mod: BLOCK, kind: "popup", width: 230, height: MENU.length * 31 + 10, props: { menu: { pr, ...this.repo } } });
  }

  row(pr, t) {
    const ci = { SUCCESS: t.ansi2, FAILURE: t.ansi1, ERROR: t.ansi1, PENDING: t.working, EXPECTED: t.working }[pr.ci] ?? t.dim;
    const chips = [];
    // UNMERGEABLE: the queue's checks failed and it will be removed.
    if (pr.queue) chips.push(pr.queue.state === "UNMERGEABLE"
      ? chip(t, "merge queue: failing", t.ansi1)
      : chip(t, `merge queue #${pr.queue.position}`, t.accent));
    if (pr.draft) chips.push(chip(t, "draft", t.dim));
    if (pr.decision === "CHANGES_REQUESTED") chips.push(chip(t, "changes requested", t.ansi3));
    if (pr.decision === "APPROVED") chips.push(chip(t, "approved", t.ansi2));
    if (pr.labels.includes("2.status: merge conflict")) chips.push(chip(t, "conflict", t.ansi1));
    if (pr.labels.includes("2.status: stale")) chips.push(chip(t, "stale", t.dim));
    const mono = settings().font_family ?? "JetBrains Mono";
    return v_flex().id(`pr-${pr.n}`).flex_none().px(8).py(5).gap(3).rounded(8).cursor_pointer().hover((s) => s.bg(t.hover))
      .on_click(() => openUrl(url(pr.n)))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(pr); })
      .tooltip(`${pr.title}\nClick opens on GitHub · right-click to review`)
      .child(h_flex().gap(8).items_center()
        .child(div().size(7).flex_none().rounded(4).bg(ci))
        .child(div().flex_1().min_w(0).truncate().text_size(12.5).text_color(pr.draft ? t.muted : t.foreground).child(pr.title))
        .child(div().flex_none().text_size(10.5).text_color(t.dim).child(ago(pr.updated))))
      .child(h_flex().pl(15).flex_wrap().gap(4).gap_y(3).items_center().text_size(10.5).text_color(t.dim)
        .child(div().font_family(mono).child(`#${pr.n}`))
        .child(div().child(pr.author))
        .children(chips));
  }

  group(key, label, list, t) {
    if (!list.length) return [];
    const folded = Boolean(this.collapsed[key]);
    const head = h_flex().id(`grp-${key}`).px(8).pt(10).pb(4).flex_none().gap(6).items_center().cursor_pointer()
      .text_size(10.5).font_semibold().text_color(t.dim).on_click((_e, cx) => this.toggle(key, cx))
      .child(div().child(`${label.toUpperCase()} · ${list.length}`))
      .when(folded, (el) => el.child(svg("mods/workspace-chrome/chevron-right.svg").size(10).flex_none()));
    return [head, ...(folded ? [] : list.map((pr) => this.row(pr, t)))];
  }

  panel(t) {
    const prs = this.prs ?? [];
    // Each PR once, in the first group that matches.
    const requested = prs.filter((p) => p.why.includes("requested") || p.why.includes("assigned"));
    const mentioned = prs.filter((p) => !requested.includes(p) && p.why.includes("mentioned"));
    const rest = prs.filter((p) => !requested.includes(p) && !mentioned.includes(p));
    const refresh = div().id("refresh").px(6).py(2).rounded(6).cursor_pointer().text_size(11).text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => this.refresh(cx))
      .child(this.loading ? "…" : "Refresh");
    return v_flex().id("nixpkgs-prs").size_full().min_h(0).pb(8).overflow_y_scrollbar().bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(h_flex().h(41).px(16).pt(14).pb(5).flex_none().gap(6).items_center()
        .child(div().flex_1().text_size(11.5).font_medium().text_color(t.dim).child(`nixpkgs PRs${this.prs ? ` · ${prs.length}` : ""}`))
        .when(Boolean(this.fetched), (el) => el.child(div().text_size(10.5).text_color(t.dim).child(ago(this.fetched))))
        .child(refresh))
      .child(div().px(16).pb(6).flex_none().child(div().id("lookup").h(28).px(10).flex().items_center().gap(6).rounded(7)
        .border_1().border_color(t.border).bg(t.background).cursor_text()
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .child(Input.new(this.lookup).flex_1().h_full().text_size(12).text_color(t.foreground))
        .when(Boolean(this.lookingUp), (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.dim).spin(900)))))
      .when(Boolean(this.lookupError), (el) => el.child(div().px(16).pb(4).text_size(11).text_color(t.ansi1).child(this.lookupError)))
      .when(Boolean(this.error), (el) => el.child(div().px(16).pb(4).text_size(11).text_color(t.ansi1).child(`GitHub: ${this.error}`)))
      .when(!this.prs && !this.error, (el) => el.child(div().px(16).py(8).text_size(12).text_color(t.dim).child("Loading…")))
      .when(Boolean(this.prs) && !prs.length, (el) => el.child(div().px(16).py(8).text_size(12).text_color(t.dim).child("No open PRs involve you.")))
      .child(v_flex().px(8).gap(1)
        .children(this.group("requested", "Review requested", requested, t))
        .children(this.group("mentioned", "Mentioned", mentioned, t))
        .children(this.group("participating", "Participating", rest, t)));
  }

  // ---- Right-click menu ----

  initMenu(cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  chooseMenu(i) {
    const o = props(), m = o.menu, it = MENU[i];
    if (!it) return;
    // Act before closing: a closed popup's new overlays are dropped.
    if (it.id === "open") openUrl(url(m.pr.n));
    else if (it.id === "review") openOverlay({ mod: BLOCK, kind: "dialog", modal: true, width: 520, height: 640, props: { review: m } });
    else if (it.id === "claude") openOverlay({ mod: BLOCK, kind: "dialog", modal: true, width: 680, height: 560, props: { claude: m } });
    closeOverlay(o.overlay);
  }

  menuPopup(t) {
    const p = props();
    return v_flex().id("menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % MENU.length;
        else if (e.key === "up") this.at = (this.at + MENU.length - 1) % MENU.length;
        else if (e.key === "enter") this.chooseMenu(this.at);
        else if (e.key === "escape") closeOverlay(p.overlay);
        else return;
        cx.notify();
      })
      .children(MENU.map((it, i) => h_flex().id(`m-${i}`).h(31).px(8).gap(9).rounded(7).items_center().text_color(t.foreground)
        .when(i === this.at, (el) => el.bg(t.selected))
        .hover((s) => s.bg(t.hover)).on_click(() => this.chooseMenu(i))
        .child(svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(t.muted))
        .child(div().flex_1().child(it.label))));
  }

  // ---- nixpkgs-review dialog ----

  initReview(cx) {
    const last = shared(LAST) ?? {};
    this.extra = InputState.new({ placeholder: "-p hello -p hello.tests", value: last.extra ?? "" });
    this.sel = { off: new Set(), systems: last.systems ?? null, tests: Boolean(last.tests), checkout: last.checkout ?? "merge", result: last.result ?? "nothing" };
    cx.spawn(async (cx) => {
      try {
        this.cfg = await nixConfig(props().review.on);
        if (!this.cfg.system) throw new Error("`nix config show system` gave nothing");
        const avail = this.available();
        const kept = (this.sel.systems ?? []).filter((s) => avail.includes(s));
        this.sel.systems = kept.length ? kept : [this.cfg.system];
      } catch (e) {
        this.cfgError = String(e.message ?? e);
      }
      cx.notify();
    });
  }

  // Systems the selected machines build: this one's own and extra-platforms,
  // and each selected builder's.
  available() {
    const c = this.cfg, off = this.sel.off;
    const list = off.has("local") ? [] : [c.system, ...c.extra];
    for (const m of c.machines) if (!off.has(m.line)) list.push(...m.systems);
    return [...new Set(list)];
  }

  argv() {
    const { n } = props().review.pr, c = this.cfg, s = this.sel;
    const out = ["nix", "run", "nixpkgs#nixpkgs-review", "--", "pr", String(n), "--systems", s.systems.join(" ")];
    const kept = c.machines.filter((m) => !s.off.has(m.line));
    if (kept.length !== c.machines.length) out.push("--option", "builders", kept.map((m) => m.line).join(" ; "));
    // No local builds: everything goes to the builders.
    if (s.off.has("local")) out.push("--option", "max-jobs", "0");
    if (s.checkout === "commit") out.push("--checkout", "commit");
    if (s.tests) out.push("--tests");
    out.push(...words(this.extra.value()));
    out.push(...RESULTS.find((r) => r.id === s.result).flags);
    return out;
  }

  startReview() {
    const p = props(), r = p.review, s = this.sel;
    setShared(LAST, { systems: s.systems, tests: s.tests, checkout: s.checkout, result: s.result, extra: this.extra.value() });
    run("tab.new", { name: `review #${r.pr.n}`, space: r.space, folder: r.root, argv: this.argv() });
    closeOverlay(p.overlay);
  }

  reviewDialog(t) {
    const p = props(), r = p.review, c = this.cfg, s = this.sel;
    const mono = settings().font_family ?? "JetBrains Mono";
    const label = (text, aside) => h_flex().pt(12).pb(6).gap(8).text_size(11.5).text_color(t.muted)
      .child(div().flex_1().child(text)).child(div().text_color(t.dim).child(aside ?? ""));
    const option = (id, on, round, text, about, action) => h_flex().id(id).h(30).px(8).gap(8).items_center().rounded(7)
      .border_1().border_color(on ? t.input : t.border).cursor_pointer().hover((st) => st.bg(t.hover))
      .on_click((_e, cx) => { action(); cx.notify(); })
      .child(tick(t, on, round)).child(div().flex_1().min_w(0).truncate().text_size(12.5).child(text))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(about ?? ""));
    const head = v_flex().gap(2)
      .child(div().text_size(15).font_semibold().child(`nixpkgs-review #${r.pr.n}`))
      .child(div().truncate().text_size(11.5).text_color(t.dim).child(r.pr.title));
    const shell = v_flex().size_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(p.overlay); cx.stop_propagation(); } })
      .child(head);
    if (!c) return shell.child(div().flex_1().pt(16).text_size(12.5).text_color(this.cfgError ? t.ansi1 : t.dim)
      .child(this.cfgError ? `Couldn't read the nix config: ${this.cfgError}` : "Reading nix config…"))
      .child(h_flex().justify_end().child(button(t, "rv-cancel", "Cancel", false, () => closeOverlay(p.overlay))));
    const avail = this.available();
    s.systems = s.systems.filter((x) => avail.includes(x));
    const toggleMachine = (key) => { s.off.has(key) ? s.off.delete(key) : s.off.add(key); };
    const all = [...new Set([c.system, ...c.extra, ...c.machines.flatMap((m) => m.systems)])];
    const cmd = this.argv().map(quote).join(" ");
    return shell
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar()
        .child(label("Machines", "nix config show builders"))
        .child(v_flex().gap(4)
          .child(option("m-local", !s.off.has("local"), false, `${r.on ?? "This computer"}`, [c.system, ...c.extra].join(", "), () => toggleMachine("local")))
          .children(c.machines.map((m, i) => option(`m-${i}`, !s.off.has(m.line), false, m.name, `${m.systems.join(", ")} · ${m.jobs} jobs`, () => toggleMachine(m.line))))
          .when(!c.machines.length, (el) => el.child(div().text_size(11).text_color(t.dim).child("No remote builders configured."))))
        .child(label("Systems", "--systems"))
        .child(h_flex().flex_wrap().gap(6).children(all.map((x) => {
          const can = avail.includes(x), on = s.systems.includes(x);
          return h_flex().id(`s-${x}`).h(24).px(8).gap(6).items_center().rounded(6).border_1().border_color(on ? t.input : t.border)
            .font_family(mono).text_size(11.5).when(!can, (el) => el.opacity(0.4))
            .when(can, (el) => el.cursor_pointer().hover((st) => st.bg(t.hover)).on_click((_e, cx) => {
              s.systems = on ? s.systems.filter((y) => y !== x) : [...s.systems, x];
              cx.notify();
            }))
            .child(tick(t, on, false)).child(x);
        })))
        .child(label("What to build", "blank: everything the PR rebuilds"))
        .child(div().id("extra").h(30).px(10).flex().items_center().rounded(7).border_1().border_color(t.input).bg(t.background)
          .cursor_text().on_mouse_down("left", (_e, cx) => cx.stop_propagation())
          .child(Input.new(this.extra).w_full().h_full().font_family(mono).text_size(12).text_color(t.foreground)))
        .child(h_flex().pt(6).gap(6)
          .child(div().flex_1().child(option("tests", s.tests, false, "Also build passthru.tests", "--tests", () => { s.tests = !s.tests; })))
          .child(option("co-merge", s.checkout === "merge", true, "merge", null, () => { s.checkout = "merge"; }))
          .child(option("co-commit", s.checkout === "commit", true, "commit", null, () => { s.checkout = "commit"; })))
        .child(label("After the build"))
        .child(v_flex().gap(4).children(RESULTS.map((x) => option(`r-${x.id}`, s.result === x.id, true, x.label, x.about, () => { s.result = x.id; }))))
        .child(div().mt(12).p(8).rounded(7).bg(t.background).border_1().border_color(t.border)
          .font_family(mono).text_size(11).text_color(t.muted).child(cmd)))
      .child(h_flex().pt(14).gap(8).items_center()
        .child(div().flex_1().text_size(11).text_color(t.dim).child("Opens a new tab in this space"))
        .child(button(t, "rv-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button(t, "rv-start", "Start review", true, () => this.startReview(), !s.systems.length)));
  }

  // ---- Claude Code dialog ----

  initClaude(cx) {
    const m = props().claude;
    this.prompt = TextareaState.new({ value: "Reading the PR's files…" });
    cx.spawn(async (cx) => {
      const r = await exec("gh", ["pr", "view", String(m.pr.n), "--repo", "NixOS/nixpkgs", "--json", "files", "--jq", ".files[].path"]).catch((e) => ({ code: 1, stderr: String(e.message ?? e) }));
      // Without the file list the prompt still works; it just names fewer guides.
      const files = r.code === 0 ? r.stdout.split("\n").filter(Boolean) : [];
      if (r.code !== 0) this.filesError = (r.stderr || "").trim().split("\n").pop();
      this.prompt.set_value(reviewPrompt(m.pr, files, m.remote));
      this.prompt.focus();
      this.ready = true;
      cx.notify();
    });
  }

  claudeDialog(t) {
    const p = props(), m = p.claude;
    return v_flex().size_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(p.overlay); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child(`Review #${m.pr.n} in Claude Code`))
      .child(div().pt(4).pb(10).text_size(11.5).text_color(this.filesError ? t.ansi3 : t.dim)
        .child(this.filesError ? `Couldn't list the PR's files (${this.filesError}); the prompt names only the general guides.`
          : `${m.pr.title} · runs in a new tab at the checkout. Edit the prompt if you like.`))
      .child(Textarea.new(this.prompt).flex_1().min_h(0).p(10).rounded(9).border_1().border_color(t.accent)
        .bg(t.background).text_size(12.5).text_color(t.foreground))
      .child(h_flex().pt(14).gap(8).justify_end()
        .child(button(t, "cl-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button(t, "cl-start", "Start in Claude Code", true, () => {
          run("tab.new", { name: `claude: #${m.pr.n}`, space: m.space, folder: m.root, argv: ["claude", this.prompt.value()] });
          closeOverlay(p.overlay);
        }, !this.ready)));
  }

  render(cx) {
    const t = theme();
    if (props()?.menu) return this.menuPopup(t);
    if (props()?.review) return this.reviewDialog(t);
    if (props()?.claude) return this.claudeDialog(t);
    return this.panel(t);
  }
}
