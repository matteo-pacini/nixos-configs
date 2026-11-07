// Spaces as machine cards: a copy of herdr-app's shipped `spaces` mod (0.1.10)
// with its git, worktree, folding and drag logic kept, drawn differently. Each
// machine is a header with its device tile, OS and connection state, its spaces
// hung off a line below it: the name, its folder when it isn't a repo, and a
// marker while it is working or waiting; a branch other than master/main on a
// second line. Ahead/behind is the status bar's (mods/status-bar).
// Click to switch, right-click for its menu, drag to reorder.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, machines, panes, run, openOverlay, hc, theme, shared, setShared, settings, watchFolder, window, layout } from "herdr";
import { narrow } from "./lib/ui.js";
import { HOSTS, SELF } from "./lib/hosts.js";
import { gitInfo, plain } from "./lib/git.js";

// A machine missing from HOSTS (lib/hosts.js, the SSH mesh by the lower-case
// name hc uses) is drawn as a server with no OS.
const hostOf = (name) => HOSTS[name?.toLowerCase()] ?? { label: name, device: "server", os: null };

// Where a space is now: its first terminal's live folder, else where it was made.
// `ps`: panes(), read once by the caller (each read copies every pane).
function place(s, ps) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);
const base = (path) => path.replace(/\/+$/, "").split("/").pop();
// Changes made outside Herdr (an editor's save, a commit in another app): looked
// for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;

// What a stored color name looks like on an avatar (the same in every mod
// that draws space avatars): one strong color per hue, light and dark alike.
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };

// A space speaks up only when something in it needs you.
export function glyph(status) {
  return status === "blocked" || status === "done" ? "●" : "·";
}

export function tone(t, status) {
  return t[status] ?? t.unknown;
}

export default class Spaces extends View {
  init(_props, cx) {
    this.git = {}; // where() -> { name, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.folded = new Set(JSON.parse(localStorage.getItem("machines.folded") ?? "[]"));
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
    // Names this computer's card: hc has no name for the local machine.
    this.local = SELF;
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx) {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.due(now, sp, panes());
    if (due.size) this.refreshGit(due, cx);
    if (sp.some((s) => !this.shown.has(s.id))) cx.notify();
  }

  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those on
  // a machine that is back, and repos in view whose fallback is due.
  due(now, sp, ps) {
    // Moved there: what it knew of that place may be old.
    const at = {};
    for (const s of sp) at[s.id] = where(s, ps);
    const keys = new Set(Object.values(at).filter((k) => JSON.parse(k)[1]));
    const due = new Set([...keys].filter((k) => !(k in this.git)));
    for (const [id, k] of Object.entries(at)) if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] = p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      if (ready && this.ready[m.name] === false) for (const k of keys) if (JSON.parse(k)[0] === m.name) due.add(k);
      this.ready[m.name] = ready;
    }
    if (window().active) {
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (asks && !this.folded.has(JSON.parse(k)[0]) && now - (this.checked[k] ?? 0) > FALLBACK) due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their ahead/behind).
  sameRepo(key, keys) {
    const repo = this.git[key]?.repo;
    return [key, ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : [])];
  }

  refreshMachines(cx) {
    cx.spawn(async cx => {
      try { const r = await hc(["machine", "ls", "--json"]); if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary); } catch {}
      cx.notify();
    });
  }

  // One look at a time, each place once however often it was asked for meanwhile.
  refreshGit(keys, cx) {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(Object.values(this.git).filter(Boolean).map((g) => JSON.parse(g.repo)).filter(([on]) => !on).map(([, repo]) => repo));
      for (const repo of this.watching) if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One place's git: branch, ahead/behind, its repo.
  async check(key, cx) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      const r = await gitInfo(cwd, on);
      if (!r.info) {
        // Only git's own "no" is remembered as no repo; anything else is asked again.
        if (r.unsure) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      const info = r.info;
      this.git[key] = info;
      if (!on) this.watch(JSON.parse(info.repo)[1], cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  watch(repo, cx) {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(repo);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo)) this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === mine), cx);
        }
      } catch { this.watching.delete(repo); }
    });
  }

  menu(w) {
    // A popup is as tall as its items; height is only the most.
    openOverlay({ mod: "space-menu", kind: "popup", width: 210, height: 230, props: { tab: "space", target: { id: w.id } } });
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered() {
    const sp = spaces(), ps = panes();
    const ready = (w) => this.shown.has(w.id) || where(w, ps) in this.git || Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp) if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp.map((w, i) => ({ w, i, g: this.git[where(w, ps)] ?? null })).filter((r) => this.shown.has(r.w.id));
    const mains = new Set(list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo));
    const nested = (r) => r.g?.linked && mains.has(r.g.repo);
    const out = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) => out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─" }));
    }
    return out;
  }

  // The rows, under a header per machine once one isn't this computer.
  grouped(t, collapsed) {
    const rows = this.ordered();
    const draw = (r) => (collapsed ? this.compact(r, t) : this.row(r, t));
    const remote = [...new Set([...rows.map(r => r.w.machine).filter(Boolean), ...this.machines.map(m => m.name)])].sort();
    const loading = m => {
      const layout = machines().find(k => k.name === m)?.layout;
      return layout === "loading" || (!layout && this.machines.some(k => k.name === m && k.state === "connected"))
        || spaces().some(s => (s.machine ?? null) === m && !this.shown.has(s.id));
    };
    const loadingRow = m => div().id(`machine-loading-${m ?? "local"}`).h(28).flex_none().px(8).text_size(12).text_color(t.dim).child(collapsed ? "…" : "Loading…");
    // The rail keeps the shipped flat list; the full width always draws cards.
    if (collapsed && !remote.length) return loading(null) && !rows.length ? [loadingRow(null)] : rows.map(draw);
    const machineNames = [null, ...remote];
    return machineNames.flatMap((m) => {
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const machine = this.machines.find(k => k.name === m);
      const connected = !m || machine?.state === "connected";
      const folded = this.folded.has(m);
      const toggle = (_e, cx) => {
        folded ? this.folded.delete(m) : this.folded.add(m);
        localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
        cx.notify();
      };
      const empty = h_flex().id(`machine-new-${m ?? "local"}`).h(28).flex_none().px(8).gap(7).items_center().rounded(7)
        .text_size(12).text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => run("space.new", m ? { machine: m } : {}))
        .child(svg("mods/workspace-chrome/plus.svg").size(12)).when(!collapsed, el => el.child("New space there"));
      const body = folded ? [] : mine.length ? mine.map(draw) : [loading(m) ? loadingRow(m) : empty];
      if (!collapsed) return [this.machineCard(m, machine, connected, folded, toggle, body, t, mine.length)];
      const head = h_flex().id(`machine-${m ?? "local"}`).h(26).flex_none().px(collapsed ? 2 : 8).gap(7).items_center().text_size(11).text_color(t.dim)
        .cursor_pointer().hover(s => s.bg(t.hover))
        .on_click(toggle)
        .child(svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(13).flex_none())
        .when(!collapsed, el => el.child(div().flex_1().truncate().child(m ?? "This computer"))
          .when(!connected, el => el.child(div().flex_none().child((machine?.state ?? "asleep").replace(/_/g, " "))))
          .when(connected, el => el.child(div().id(`machine-add-${m ?? "local"}`).flex_none().px(4).rounded(4).hover(s => s.bg(t.hover).text_color(t.foreground))
            .on_click((_e, cx) => { cx.stop_propagation(); run("space.new", m ? { machine: m } : {}); }).child("+")))
          .child(div().size(6).rounded(3).flex_none().bg(connected ? t.ansi2 : t.dim))
          .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none()));
      return [head, ...body];
    });
  }

  // A machine: its device in a tile, name over OS and connection, then its
  // spaces hung off a line down from the tile. Its + and chevron show on hover
  // (the chevron always, once folded).
  machineCard(m, machine, connected, folded, toggle, body, t, count) {
    const host = hostOf(m ?? this.local);
    const state = (machine?.state ?? "asleep").replace(/_/g, " ");
    const key = m ?? "local";
    const shown = this.hovered === key;
    const sub = [m && !connected ? state : null, host.os, m ? null : "this computer"].filter(Boolean).join(" · ");
    const head = h_flex().id(`machine-${key}`).h(34).flex_none().gap(9).pl(2).pr(6).items_center().cursor_pointer().rounded(8)
      .on_hover((over, cx) => {
        if (over) this.hovered = key;
        else if (this.hovered === key) this.hovered = null;
        cx.notify();
      })
      .on_click(toggle)
      .child(div().size(26).flex_none().rounded(7).bg(t.selected).flex().items_center().justify_center()
        .child(svg(`mods/space-cards/${host.device}.svg`).size(15).text_color(connected ? t.foreground : t.dim)))
      .child(v_flex().flex_1().min_w(0)
        .child(div().truncate().font_semibold().text_color(connected ? t.foreground : t.muted).child(host.label ?? "This computer"))
        .child(h_flex().gap(5).items_center().text_size(10.5).text_color(t.dim)
          .when(Boolean(m), (el) => el.child(div().size(6).flex_none().rounded(3).bg(connected ? t.ansi2 : t.dim)))
          .child(div().min_w(0).truncate().child(sub))))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(String(count)))
      .when(connected && shown, (el) => el.child(div().id(`machine-add-${key}`).size(20).flex_none().rounded(5).flex().items_center().justify_center()
        .text_color(t.dim).hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => { cx.stop_propagation(); run("space.new", m ? { machine: m } : {}); })
        .child(svg("mods/workspace-chrome/plus.svg").size(12))))
      .when(shown || folded, (el) => el.child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none().text_color(t.dim)));
    return v_flex().id(`machine-card-${key}`).flex_none().mt(10).gap(1)
      .child(head)
      .when(body.length > 0, (el) => el.child(v_flex().ml(14).pl(8).border_l(1.5).border_color(t.border).gap(1).children(body)));
  }

  // Right of the name, on the same line: the repo's name when it differs from
  // the space's (on master/main), the folder's last part when it isn't a repo.
  // A worktree not nested under its repo (its repo isn't open) gets the
  // compare icon, here on master/main, else on its branch line.
  // Ahead/behind is the status bar's, for the focused terminal.
  detail(g, w, tree, t) {
    const line = () => h_flex().flex_1().min_w(0).gap(6).justify_end().items_center().text_size(11).text_color(t.dim);
    if (!g) {
      const folder = place(w, this.ps ?? panes());
      return folder ? line().child(div().min_w(0).truncate().child(`${base(folder)}/`)) : null;
    }
    if (!plain(g.branch)) return null;
    return line()
      .when(g.linked && !tree, (el) => el.child(svg("mods/workspace-chrome/git-compare.svg").size(10).flex_none().text_color(t.ansi5)))
      .when(!tree && g.name.toLowerCase() !== w.name.toLowerCase(), (el) => el.child(div().min_w(0).truncate().child(g.name)));
  }

  // The second line of a space on a branch other than master/main: the branch
  // under the name's first letter. `lead`: how far in the name starts.
  branchLine(g, tree, lead, t) {
    if (!g || plain(g.branch)) return null;
    return h_flex().h(14).pl(lead).gap(6).items_center()
      .when(g.linked && !tree, (el) => el.child(svg("mods/workspace-chrome/git-compare.svg").size(10).flex_none().text_color(t.ansi5)))
      .child(g.branch
        ? div().min_w(0).truncate().font_family(settings().font_family ?? "JetBrains Mono").text_size(10.5).text_color(t.accent).child(g.branch)
        : div().text_size(10.5).text_color(t.dim).child("detached"));
  }

  // Shown only while something in the space is going on or needs you.
  marker(w, t) {
    if (w.status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900);
    if (w.status === "blocked" || w.status === "done") return div().size(7).flex_none().rounded(4).bg(tone(t, w.status));
    return null;
  }

  row({ w, i, g, tree }, t) {
    const on = w.active;
    const colors = shared("space.colors") ?? {};
    const color = colors[w.id] ?? "ansi6";
    const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    const mark = this.marker(w, t);
    const detail = this.detail(g, w, tree, t);
    // Line 2 starts where the name does: past the connector (8 + 10 + gap 8)
    // or the avatar (16 + gap 8).
    const second = this.branchLine(g, tree, tree ? 26 : 24, t);
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .px(6)
      .h(second ? 40 : 28)
      .gap(1)
      .flex_none()
      .justify_center()
      .rounded(6)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .when(this.pressed === i && this.over !== i, (el) => el.opacity(0.5))
      .when(this.pressed !== null && this.over === i && this.pressed !== i, (el) => el.child(
        div().absolute().left(0).right(0).h(2).bg(t.accent)
          .when(this.pressed < i, line => line.bottom(0))
          .when(this.pressed > i, line => line.top(0)),
      ))
      .on_mouse_down("left", () => {
        this.pressed = i;
        this.over = i;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces()[this.pressed];
        const over = source && (source.machine ?? null) === (w.machine ?? null) ? i : null;
        if (this.pressed !== null && this.over !== over) {
          this.over = over;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.pressed = null;
        this.over = null;
        if (from !== null && over === i && from !== i) run("space.move", { id: spaces()[from].id, index: i + 1 });
        else if (from === i) run("space.select", { id: w.id });
        cx.notify();
      })
      .on_mouse_down("right", () => this.menu(w))
      .child(
        h_flex()
          .gap(8)
          .items_center()
          .when(Boolean(tree), el => el.pl(8).child(div().w(10).h(14).flex_none().self_start().border_l(1).border_b(1).border_color(t.border).rounded_bl(4)))
          .when(!tree, el => el.child(h_flex().size(16).flex_none().rounded(4).bg(fill).items_center().justify_center().text_size(9.5).font_bold().text_color("#ffffff").child([...w.name][0]?.toUpperCase() ?? "?")))
          .child(div().min_w(0).truncate().font_medium().text_color(tree ? t.muted : t.foreground).child(w.name))
          .child(detail ?? div().flex_1())
          .when(Boolean(mark), (el) => el.child(mark)),
      )
      .when(Boolean(second), (el) => el.child(second));
  }

  compact({ w, i }, t) {
    return h_flex()
      .id(`space-${w.id}`)
      .h(26)
      .flex_none()
      .justify_center()
      .gap(4)
      .when(w.active, (el) => el.bg(t.raised))
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("space.select", { id: w.id }))
      .child(div().text_color(w.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().text_color(tone(t, w.status)).child(glyph(w.status)));
  }

  render() {
    const t = theme();
    this.ps = panes();
    const collapsed = narrow();
    const palette = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
    const sp = spaces();
    const ids = new Set(sp.map(p => p.id));
    const kept = Object.fromEntries(Object.entries(shared("space.colors") ?? {}).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(shared("space.colors") ?? {}).length;
    for (const p of sp) {
      if (kept[p.id] || p.name === "~") continue;
      const uses = c => Object.values(kept).filter(v => v === c).length;
      kept[p.id] = palette.reduce((best, c) => uses(c) < uses(best) ? c : best);
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).pl(16).pr(10).items_center().justify_between().text_size(11.5).text_color(t.dim)
        .when(!collapsed, el => el.child("Spaces"))
        .child(div().id("space-new").size(26).flex_none().flex().items_center().justify_center().rounded(6).hover(s => s.bg(t.hover).text_color(t.foreground))
          .on_click(() => run("space.new")).child(svg("mods/workspace-chrome/plus.svg").size(14))))
      .child(v_flex().flex_1().min_h(0).px(8).pb(14).overflow_y_scrollbar().mode("always")
        .on_mouse_up("left", (_e, cx) => { this.pressed = null; cx.notify(); })
        .children(this.grouped(t, collapsed)));
  }
}
