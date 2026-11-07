// The status bar for the focused terminal: a copy of herdr-app's shipped
// `workspace-status` mod (machine, agents, palette hint) with that terminal's
// branch and ahead/behind, and its GitHub pull request's state and checks.
// It follows the focused terminal's live folder, so a cd in any pane moves
// it; the sidebar (space-cards) shows each space's own branch.

import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, agents, panes, focused, theme, run, window, keys, settings, home } from "herdr";
import { location, openUrl } from "./lib/ui.js";
import { gitInfo, origin, plain } from "./lib/git.js";
import { lookup, nextDelay, counts, tooltip, checksUrl, onGitHub, relation } from "./lib/pr.js";

// How often a place's git is looked at again while the window is in front:
// commits and pushes from outside a pane's turn move ahead/behind.
const FALLBACK = 30000;
// Narrower than this, the PR title goes and a failed check's name shortens.
const WIDE = 1000;

const where = (loc) => JSON.stringify([loc.on ?? null, loc.cwd]);

// A space's anchor: its first terminal's live folder, else where it was made
// (as space-cards and the shipped mods take a space's repo).
function anchorOf(space, ps) {
  if (!space) return null;
  const tabs = new Set((space.tabs ?? []).map((c) => c.id));
  const cwd = ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || space.folder;
  return cwd ? { on: space.machine ?? null, cwd } : null;
}

export default class StatusBar extends View {
  init(_props, cx) {
    this.git = {}; // where() -> lib/git.js info, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.origins = {}; // info.repo -> origin URL or null
    this.prs = {}; // JSON [repo, branch] -> { pr (null: none), next }
    this.pending = new Set();
    this.here = null; // the focused terminal's { on, cwd }, kept while a mod pane has focus
    this.width = Infinity;
    this.busy = false;
    cx.timer.every(500, (cx) => this.tick(cx));
  }

  // Looks again where the answer could have changed: a new place (focus moved,
  // a cd), the focused pane's command or turn just ended, the fallback is due,
  // or the PR's next look is.
  tick(cx) {
    const ps = panes();
    const f = focused();
    const pane = f?.pane ? ps.find((p) => p.pane === f.pane) : null;
    if (!(pane && !pane.terminal)) {
      const loc = location();
      if (loc.cwd) this.here = { on: loc.on, cwd: loc.cwd };
    }
    this.anchor = anchorOf(spaces().find((s) => s.active), ps);
    const busy = Boolean(pane?.terminal) && (pane.status === "working" || !(pane.program?.shell || pane.program?.agent));
    const ended = this.busy && !busy;
    this.busy = busy;
    const now = Date.now();
    for (const loc of [this.here, this.anchor]) {
      if (!loc) continue;
      const k = where(loc);
      if (!(k in this.git) || (loc === this.here && ended) || (window()?.active && now - (this.checked[k] ?? 0) > FALLBACK)) this.pending.add(k);
    }
    const g = this.here && this.git[where(this.here)];
    const p = g && this.prKey(g);
    if (p && (!this.prs[p] || now >= this.prs[p].next || ended)) this.pending.add(`pr:${where(this.here)}`);
    if (this.pending.size) this.refresh(cx);
    // A place already looked at has nothing to fetch, so nothing else redraws.
    const shown = JSON.stringify([this.here, this.anchor]);
    if (shown !== this.shown) {
      this.shown = shown;
      cx.notify();
    }
  }

  prKey(g) {
    return g.branch && !plain(g.branch) ? JSON.stringify([g.repo, g.branch]) : null;
  }

  // One look at a time; each place once however often it was asked for meanwhile.
  refresh(cx) {
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) {
          try {
            if (key.startsWith("pr:")) await this.lookPr(JSON.parse(key.slice(3)));
            else await this.lookGit(key);
          } catch {
            // The machine is away: keep what was shown, look again later.
          }
        }
        cx.notify();
      }
      this.refreshing = false;
    });
  }

  async lookGit(key) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    const r = await gitInfo(cwd, on);
    if (r.info) this.git[key] = r.info;
    else if (r.none) this.git[key] = null;
    const g = r.info;
    if (g && !(g.repo in this.origins)) this.origins[g.repo] = await origin(cwd, on);
  }

  async lookPr([on, cwd]) {
    const g = this.git[JSON.stringify([on, cwd])];
    const key = g && this.prKey(g);
    if (!key) return;
    const was = this.prs[key];
    if (!onGitHub(this.origins[g.repo])) {
      this.prs[key] = { pr: null, next: Infinity };
      return;
    }
    const r = await lookup(cwd, on);
    const pr = r.pr ?? (r.none ? null : was?.pr ?? null);
    this.prs[key] = { pr, next: Date.now() + nextDelay(pr, window()?.active) };
  }

  // The palette key as actually bound, not a hardcoded one; without a
  // binding the hint stays useful ("commands") instead of lying.
  hint() {
    const mac = window()?.platform === "macos";
    const mod = { cmd: mac ? "⌘" : "Ctrl+", ctrl: mac ? "⌃" : "Ctrl+", shift: mac ? "⇧" : "Shift+", alt: mac ? "⌥" : "Alt+", option: mac ? "⌥" : "Alt+" };
    const b = keys().find((k) => k.section === "global" && k.action === "app.palette");
    const parts = b && b.keys.endsWith("--") ? [...b.keys.slice(0, -2).split("-"), "-"] : b?.keys.split("-");
    const key = parts && parts.map((p) => mod[p.toLowerCase()] ?? p.toUpperCase()).join("");
    return key ? `${key}  commands` : "commands";
  }

  // `a`: the space anchor's git info, null outside git, undefined until looked at.
  branch(g, a, t) {
    const rel = a === undefined ? "same" : relation(g, a);
    const mono = settings().font_family ?? "JetBrains Mono";
    const count = (text, color) => div().flex_none().text_size(11).font_semibold().text_color(color).child(text);
    const path = this.here.on ? this.here.cwd : this.here.cwd.replace(new RegExp(`^${home().replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?=/|$)`), "~");
    return h_flex().id("branch").flex_none().gap(6).items_center()
      .child(svg("mods/workspace-chrome/branch.svg").size(13).flex_none())
      .when(rel === "repo", (el) => el.child(div().text_color(t.foreground).child(`${g.name} ·`)))
      .child(g.branch ? div().font_family(mono).text_size(11).text_color(t.accent).child(g.branch) : div().text_color(t.dim).child("detached"))
      .when(g.ahead > 0, (el) => el.child(count(`↑${g.ahead}`, t.ansi2)))
      .when(g.behind > 0, (el) => el.child(count(`↓${g.behind}`, t.ansi3)))
      .when(rel !== "same", (el) => el.tooltip([
        "Outside this space",
        `This pane: ${path} · ${g.branch ?? "detached"}`,
        `The space: ${a ? `${a.name} · ${a.branch ?? "detached"}` : "not in a repo"}`,
      ].join("\n")));
  }

  pr(pr, wide, t) {
    const word = pr.state === "open" ? null : pr.state;
    const title = wide && Boolean(pr.title);
    // With a title it shrinks well before the other segments, down to its
    // number: the title is the first thing to go. Without one it can't shrink.
    return h_flex().id("pr").when(title, (el) => el.min_w(0).flex_shrink(20)).when(!title, (el) => el.flex_none()).h(22).px(6).mx(-6).gap(6).items_center().rounded(5).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => openUrl(pr.url))
      .child(svg(`mods/status-bar/pr-${pr.state}.svg`).size(13).flex_none())
      .child(div().flex_none().text_color(t.foreground).child(`PR ${pr.number}`))
      .when(Boolean(word), (el) => el.child(div().flex_none().child(`· ${word}`)))
      .when(title, (el) => el.child(div().min_w(0).max_w(360).truncate().text_color(t.dim).child(pr.title)));
  }

  checks(pr, wide, t) {
    const c = pr.checks;
    const glyph = { failed: t.blocked, running: t.muted, passed: t.ansi2 }[pr.worst];
    const rest = counts(c);
    const tip = tooltip(c);
    return h_flex().id("checks").min_w(0).h(22).px(6).mx(-6).gap(6).items_center().rounded(5).cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => openUrl(checksUrl(pr)))
      .when(Boolean(tip), (el) => el.tooltip(tip))
      .child(svg(`mods/status-bar/${pr.worst}.svg`).size(12).flex_none().text_color(glyph))
      .when(c.failed.length > 0, (el) => el
        .child(div().flex_none().text_color(t.blocked).child(`${c.failed.length} failed:`))
        .child(div().min_w(0).max_w(wide ? 320 : 150).truncate().text_color(t.foreground).child(c.failed[0].name))
        .when(Boolean(rest), (el) => el.child(div().min_w(0).truncate().child(`· ${rest}`))))
      .when(!c.failed.length, (el) => el.child(div().min_w(0).truncate().child(rest)));
  }

  render() {
    const t = theme();
    const space = spaces().find((s) => s.active);
    const list = agents();
    const needs = list.filter((a) => a.status === "blocked").length;
    const g = this.here ? this.git[where(this.here)] : null;
    const a = this.anchor ? this.git[where(this.anchor)] : null;
    const p = g ? this.prKey(g) : null;
    const pr = p ? this.prs[p]?.pr : null;
    const live = pr && (pr.state === "open" || pr.state === "draft");
    const wide = this.width >= WIDE;
    const caution = (id, icon, text) => h_flex().id(id).min_w(0).gap(6).items_center()
      .child(svg(`mods/status-bar/${icon}.svg`).size(12).flex_none().text_color(t.ansi3)).child(div().min_w(0).truncate().child(text));
    const label = (icon, text) => h_flex().flex_none().gap(6).items_center().child(svg(`mods/workspace-chrome/${icon}.svg`).size(13)).child(text);
    return h_flex().size_full().px(14).gap(16).items_center().bg(t.chrome).border_t(1).border_color(t.border).text_size(11.8).text_color(t.muted)
      .on_size_change((size, cx) => {
        if (size.width !== this.width) { this.width = size.width; cx.notify(); }
      })
      .child(label(space?.machine ? "server" : "monitor", space?.machine ?? "This computer"))
      .when(Boolean(g), (el) => el.child(this.branch(g, a, t)))
      .when(Boolean(pr), (el) => el.child(this.pr(pr, wide, t)))
      .when(Boolean(live && pr.changes), (el) => el.child(caution("changes", "changes", "changes requested")))
      .when(Boolean(live && pr.conflicts), (el) => el.child(caution("conflicts", "conflicts", `conflicts with ${pr.base ?? "the base branch"}`)))
      .when(Boolean(live && pr.worst), (el) => el.child(this.checks(pr, wide, t)))
      .child(h_flex().flex_none().gap(6).items_center().child(div().size(6).rounded(3).bg(t.dim)).child(`${list.length} agents`)
        .when(needs > 0, (el) => el.child(div().text_color(t.blocked).child(`· ${needs} needs you`))))
      .child(div().flex_1())
      .child(div().id("palette").flex_none().text_color(t.dim).on_click(() => run("app.palette")).child(this.hint()));
  }
}
