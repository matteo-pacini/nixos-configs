// The Agents sidebar's Visualise dialog: every agent as a pixel-art worker in
// an office. A machine is a building, a repo a floor, a git worktree a room
// on it, and each agent sits at its own cubicle there; agents outside any
// repo go to the building's Lobby. Working and idle agents face their PC;
// one that is blocked or done turns round to the room. Clicking one docks a
// card with where it runs, its model, context and cache, and, while it's
// blocked, what it asks (the `agent.ask` label its app's hooks set).
//
// The art lives in office/ (cubicle layers on one 144×176 canvas, stacked at
// the same spot) and office/sprites (one SVG per pose and app, rendered by
// sprites/render.mjs at build time).

import { div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, spaces, panes, exec, hc, run, theme, shared, closeOverlay, props } from "herdr";

const ART = "mods/agent-tree/office";
// Rects on the cubicle canvas the art in office/ is drawn to.
const CUBE = { w: 144, h: 176 };
const SCREEN = { x: 50, y: 24, w: 44, h: 29 };
const BADGE_FRONT = { x: 63, y: 119, w: 18, h: 18 };
const BADGE_BEHIND = { x: 28, y: 117, w: 18, h: 18 };
const SPRITE_BACK = { x: 42, y: 46, w: 60, h: 84 };
const SPRITE_FACING = { x: 42, y: 66, w: 60, h: 84 };
// Above a cubicle: its name tag and speech bubble.
const HEADROOM = 88;
const METER = 28;
// Apps with their own sprite colours (sprites/palettes.json); the rest get "agent".
const SPRITE_APPS = new Set(["claude-code", "codex", "opencode"]);
// Re-read a folder's worktree this often: a checkout can appear or go.
const GIT_MS = 5 * 60000;
// What `git rev-parse` reports for a folder, `${machine}\0${cwd}` ->
// { at, top, common } (null top: not in a repo; pending while it runs).
const gitInfo = new Map();

// `cwd` on `machine` (null: this one): { top, common } once known, else null
// (and a lookup starts, notifying `cx` when done).
function worktree(machine, cwd, cx) {
  const key = `${machine ?? ""}\0${cwd}`;
  const known = gitInfo.get(key);
  if (!known || Date.now() - known.at > GIT_MS) {
    gitInfo.set(key, { ...known, at: Date.now(), pending: !known });
    cx.spawn(async (cx) => {
      const r = await exec("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir"], { on: machine })
        .catch(() => null);
      const [top, common] = r?.code === 0 ? r.stdout.trim().split("\n") : [];
      gitInfo.set(key, { at: Date.now(), top: top ?? null, common: common ?? null });
      cx.notify();
    });
  }
  return known && !known.pending ? known : null;
}

const base = (p) => p.replace(/\/+$/, "").split("/").pop();
// The repo a git common dir belongs to: the folder holding `.git`, or a bare repo's own name.
const repoName = (common) => (common.endsWith("/.git") ? base(common.slice(0, -5)) : base(common).replace(/\.git$/, ""));

const STATUS = (t) => ({
  blocked: ["Needs you", t.blocked],
  done: ["Done", t.done ?? t.dim],
  working: ["Working", t.working],
  idle: ["Idle", t.dim],
});

// The office's state lives on the AgentTree view that shows it.
export function officeInit(view, cx) {
  view.open = null;
  view.screens = new Map();
  cx.timer.every(30000, (cx) => cx.notify());
}

// `h`: helpers from main.js { agentName, duration, band, expiring, changedAt }.
export function officeRender(view, cx, h) {
  const t = theme();
  const now = Date.now();
  const list = agents();
  const terms = new Map(terminals().map((k) => [k.address, k]));
  const paneOf = new Map(panes().map((p) => [p.pane, p]));
  const machineOf = new Map(spaces().map((s) => [s.id, s.machine ?? null]));

  // building (machine) -> floor (repo, or the Lobby) -> room (worktree) -> agents
  const buildings = new Map();
  let pending = 0;
  for (const a of list) {
    const machine = machineOf.get(a.space) ?? (a.address.includes("/") ? a.address.split("/")[0] : null);
    const pane = paneOf.get(a.pane);
    const git = pane?.cwd ? worktree(machine, pane.cwd, cx) : { top: null };
    if (!git) { pending++; continue; }
    const floorKey = git.top ? repoName(git.common) : "";
    const roomKey = git.top ?? "";
    if (!buildings.has(machine)) buildings.set(machine, new Map());
    const floors = buildings.get(machine);
    if (!floors.has(floorKey)) floors.set(floorKey, new Map());
    const rooms = floors.get(floorKey);
    if (!rooms.has(roomKey)) {
      rooms.set(roomKey, {
        top: git.top,
        main: Boolean(git.top) && `${git.top}/.git` === git.common,
        name: git.top ? (pane?.branch || base(git.top)) : "outside git",
        agents: [],
      });
    }
    rooms.get(roomKey).agents.push({ a, labels: terms.get(a.address)?.labels ?? {}, machine, room: rooms.get(roomKey), repo: floorKey });
  }

  const byName = (x, y) => x.localeCompare(y);
  const ordered = [...buildings.entries()].sort(([x], [y]) => (x === null ? -1 : y === null ? 1 : byName(x, y)));
  const all = ordered.flatMap(([, floors]) => [...floors.values()].flatMap((rooms) => [...rooms.values()].flatMap((r) => r.agents)));
  const needs = all.filter((e) => e.a.status === "blocked" || e.a.status === "done");
  const opened = all.find((e) => e.a.address === view.open);
  const worktrees = ordered.reduce((n, [, floors]) => n + [...floors.entries()].filter(([k]) => k).reduce((m, [, r]) => m + r.size, 0), 0);

  const scene = h_flex().items_end().gap(28).p(28).flex_none()
    .children(ordered.map(([machine, floors]) => building(t, machine, floors, view, cx, h, now)));

  return v_flex().id("office").size_full().min_h(0).bg("#1c2a38").text_color("#ece5d2")
    .child(h_flex().h(46).px(16).flex_none().gap(12).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .text_color(t.foreground)
      .child(div().text_size(15).font_semibold().child("Agents"))
      .when(needs.length > 0, (el) => el.child(div().id("office-needs").px(8).h(22).rounded(6).bg(t.blocked + "26")
        .text_color(t.blocked).text_size(12).font_medium().flex().items_center().cursor_pointer()
        .on_click((_e, cx) => {
          const i = needs.findIndex((e) => e.a.address === view.open);
          view.open = needs[(i + 1) % needs.length].a.address;
          cx.notify();
        })
        .child(`✋ ${needs.length} need${needs.length === 1 ? "s" : ""} you`)))
      .child(div().text_size(12).text_color(t.dim)
        .child(`${all.length} agent${all.length === 1 ? "" : "s"} in ${worktrees} worktree${worktrees === 1 ? "" : "s"} on ${ordered.length} machine${ordered.length === 1 ? "" : "s"}`))
      .when(pending > 0, (el) => el.child(div().text_size(12).text_color(t.dim).child("Finding worktrees…")))
      .child(div().flex_1())
      .child(div().id("office-close").size(26).rounded(6).flex().items_center().justify_center().cursor_pointer()
        .hover((s) => s.bg(t.hover)).on_click(() => closeOverlay(props().overlay))
        .child(svg("mods/workspace-chrome/x.svg").size(14).text_color(t.dim))))
    .child(div().relative().flex_1().min_h(0)
      .child(div().id("office-scene").size_full().overflow_scrollbar().child(scene))
      .when(list.length === 0, (el) => el.child(div().absolute().inset_0().flex().items_center().justify_center()
        .text_size(13).text_color(t.dim).child("No agents yet. They show up here when they report their status.")))
      .when(Boolean(opened), (el) => el.child(card(t, opened, view, cx, h, now))));
}

function building(t, machine, floors, view, cx, h, now) {
  const order = [...floors.entries()].sort(([x], [y]) => (x === "" ? 1 : y === "" ? -1 : x.localeCompare(y)));
  return v_flex().flex_none().items_center()
    .child(h_flex().h(30).px(16).gap(8).items_center().bg("#344451").border(3).border_color("#172635").border_b(0)
      .text_color("#f2dfb5").text_size(12.5).font_semibold()
      .child(div().size(6).bg(machine ? "#e8b27d" : "#aed0a1"))
      .child(machine ?? "This computer"))
    .child(v_flex().border(3).border_color("#172635").bg("#455968")
      .children(order.map(([repo, rooms], i) => floor(t, repo, rooms, i, view, cx, h, now))))
    .child(div().w_full().h(14).bg("#637583").border(3).border_t(0).border_color("#172635"));
}

function floor(t, repo, rooms, i, view, cx, h, now) {
  const order = [...rooms.values()].sort((x, y) => (x.main !== y.main ? (x.main ? -1 : 1) : x.name.localeCompare(y.name)));
  return h_flex().items_stretch().when(i > 0, (el) => el.border_t(3).border_color("#172635"))
    .child(v_flex().w(112).flex_none().p(10).justify_center().gap(2).bg("#2d3e4c").border_r(3).border_color("#172635")
      .child(div().text_size(12.5).font_semibold().text_color("#e9dfc7").child(repo || "Lobby"))
      .child(div().text_size(10.5).text_color("#b4c1c5")
        .child(repo ? `${rooms.size} room${rooms.size === 1 ? "" : "s"}` : "outside git")))
    .child(h_flex().gap(8).p(8).items_stretch().children(order.map((r) => room(t, r, view, cx, h, now))));
}

function room(t, r, view, cx, h, now) {
  const attn = r.agents.some((e) => e.a.status === "blocked");
  const [wall, ground] = !r.top ? ["#485467", "#56524b"] : r.main ? ["#485b60", "#515e57"] : ["#55536b", "#65584e"];
  return v_flex().flex_none().border(3).border_color(attn ? "#c0574c" : "#1f2b38").bg(ground)
    .child(h_flex().h(24).px(10).gap(8).items_center().bg("#1f2b38")
      .child(div().text_size(12).font_semibold().text_color("#ece5d2").child(r.name))
      .child(div().flex_1())
      .child(div().text_size(9.5).text_color("#9aa7ad").child(!r.top ? "" : r.main ? "CHECKOUT" : "WORKTREE")))
    .child(div().relative()
      // The wall: the upper part of the room behind the cubicles.
      .child(div().absolute().top(0).left(0).w_full().h(HEADROOM + 70).bg(wall))
      .child(div().absolute().top(HEADROOM + 70).left(0).w_full().h(4).bg("#252d38"))
      .child(h_flex().gap(12).px(14).pt(HEADROOM).pb(12)
        .children(r.agents.map((e) => cubicle(t, e, view, cx, h, now)))));
}

const img = (file, rect) => image(file).absolute().left(rect.x).top(rect.y).w(rect.w).h(rect.h);
const layer = (name) => img(`${ART}/${name}.svg`, { x: 0, y: 0, ...CUBE });

function cubicle(t, e, view, cx, h, now) {
  const { a, labels } = e;
  const facing = a.status === "blocked" || a.status === "done";
  const art = SPRITE_APPS.has(a.app) ? a.app : "agent";
  const sprite = (pose, rect) => img(`${ART}/sprites/${pose}-${art}.svg`, rect);
  const expiring = h.expiring(a, labels, now);
  const ask = a.status === "blocked" ? labels["agent.ask"] : "";
  const say = a.status === "blocked" ? (ask || "Needs you")
    : a.status === "done" ? "Done!"
    : expiring ? `⌛ cache cold in ${Math.max(0, Math.floor((labels["agent.cache_until"] * 1000 - now) / 60000))}m`
    : "";
  const icon = a.program?.icon;
  const badge = facing ? BADGE_BEHIND : BADGE_FRONT;
  const pct = parseInt(labels["agent.ctx"], 10);
  const k = labels["agent.ctxk"];
  const band = h.band(t, pct, expiring);
  const shown = view.open === a.address;

  return div().id(`cube-${a.address}`).relative().w(CUBE.w).h(CUBE.h + METER).flex_none().cursor_pointer()
    .on_click((_e, cx) => { view.open = shown ? null : a.address; cx.notify(); })
    .child(layer("cubicle"))
    .child(a.status === "working"
      ? div().absolute().left(0).top(0).size_full()
        .child(layer("screen-code-a"))
        .child(layer("screen-code-b").loop("opacity", { from: 0, to: 1, period: 900, easing: "linear" }))
      : layer(a.status === "blocked" ? "screen-ask" : a.status === "done" ? "screen-done" : "screen-off"))
    .when(facing, (el) => el.child(layer("chair-behind")))
    .child(a.status === "blocked" ? sprite("raise", SPRITE_FACING).loop("top", { from: SPRITE_FACING.y, to: SPRITE_FACING.y - 2, period: 900 })
      : a.status === "done" ? sprite("cheer", SPRITE_FACING)
      : a.status === "working" ? div().absolute().left(0).top(0).size_full()
        .child(sprite("backA", SPRITE_BACK))
        // Hands up and down: the second frame fades over the first.
        .child(sprite("backB", SPRITE_BACK).loop("opacity", { from: 0, to: 1, period: 500, easing: "linear" }))
      : sprite("backSleep", SPRITE_BACK))
    .when(!facing, (el) => el.child(layer("chair-front")))
    // opencode's mark is dark: it gets a light plate over the chair's own.
    .when(a.app === "opencode", (el) => el.child(div().absolute().left(badge.x - 1).top(badge.y - 1).size(badge.w + 2).bg("#eee8d7")))
    .when(Boolean(icon), (el) => el.child(a.program.tint
      ? svg(icon).absolute().left(badge.x).top(badge.y).size(badge.w).text_color("#ece5d2")
      : img(icon, badge)))
    // Name tag on the partition's top edge.
    .child(div().absolute().left(12).top(-20).w(CUBE.w - 24).h(18).px(5).rounded_t(2).flex().items_center().justify_center()
      .bg(a.status === "blocked" ? "#c0574c" : shown ? "#3e5366" : "#263443").border(1).border_b(0).border_color("#869798")
      .text_size(10.5).text_color("#ece5d2").child(div().truncate().child(h.agentName(a))))
    .when(Boolean(say), (el) => el.child(div().absolute().left(-8).top(-76).w(CUBE.w + 16).h(44).flex().items_end().justify_center()
      .loop("top", { from: -76, to: -79, period: 1100 })
      .child(div().max_w(CUBE.w + 16).px(8).py(4).rounded(4).border(2).border_color(a.status === "blocked" ? "#c0574c" : "#253342")
        .bg(a.status === "done" ? "#d8f5e2" : expiring ? "#ffe0cc" : "#f7ecd1").text_color("#35313a").text_size(11).font_semibold()
        .child(div().child(say)))))
    .when(a.status === "idle" && !expiring, (el) => el.child(div().absolute().left(98).top(34).text_size(12).font_bold().text_color("#c4cdd8")
      .loop("opacity", { from: 0.2, to: 1, period: 2400 }).child("z z")))
    // Context fill under the chair.
    .when(!Number.isNaN(pct), (el) => el.child(v_flex().absolute().left(12).top(CUBE.h + 2).w(CUBE.w - 24).gap(3).px(5).py(3)
      .rounded(2).bg("#253340").border(1).border_color("#788b8966")
      .child(div().relative().h(6).bg("#131e29")
        .child(div().absolute().left(0).top(0).h_full().w(Math.round((CUBE.w - 36) * Math.min(pct, 100) / 100)).bg(band))
        // Claude auto-compacts at 80%.
        .child(div().absolute().top(0).h_full().w(1).left(Math.round((CUBE.w - 36) * 0.8)).bg("#e1e4d566")))
      .child(div().text_size(10).text_color("#eee7d4").child(k ? `${pct}% · ${k}k` : `${pct}%`))));
}

// The docked card for the clicked agent.
function card(t, e, view, cx, h, now) {
  const { a, labels, machine, room: r, repo } = e;
  const [label, color] = STATUS(t)[a.status] ?? ["", t.dim];
  const expiring = h.expiring(a, labels, now);
  const pct = parseInt(labels["agent.ctx"], 10);
  const k = labels["agent.ctxk"];
  const until = parseInt(labels["agent.cache_until"], 10);
  const left = Math.floor((until * 1000 - now) / 60000);
  const band = h.band(t, pct, expiring);
  const ask = labels["agent.ask"];
  const detail = labels["agent.ask_detail"];
  const when = h.changedAt(a.address);
  const fill = (() => {
    const c = (shared("space.colors") ?? {})[a.space] ?? "ansi6";
    return c.startsWith("#") ? c : (h.MARK[c] ?? t[c]);
  })();
  // A blocked agent whose app sets no agent.ask: show its screen instead.
  if (a.status === "blocked" && !ask && !view.screens.has(a.address)) {
    view.screens.set(a.address, null);
    cx.spawn(async (cx) => {
      const r = await hc(["read", "--lines", "14", a.address]).catch(() => null);
      view.screens.set(a.address, r?.code === 0 ? r.stdout.replace(/\s+$/, "") : "");
      cx.notify();
    });
  }
  if (a.status !== "blocked") view.screens.delete(a.address);
  const screen = view.screens.get(a.address);

  const chip = (...kids) => h_flex().flex_none().h(18).px(6).gap(4).rounded(5).bg(t.hover).items_center().children(kids);
  const meter = (iconName, title, pctFill, barColor, text, textColor) => h_flex().gap(8).items_center().text_size(10.5).text_color(t.dim)
    .child(h_flex().w(62).gap(4).items_center().child(svg(`mods/workspace-chrome/${iconName}.svg`).size(11)).child(title))
    .child(div().w(170).flex_none().h(6).rounded(3).bg(t.input)
      .child(div().h_full().rounded(3).bg(barColor).w(Math.round(170 * Math.max(0, Math.min(pctFill, 100)) / 100))))
    .child(div().w(76).text_right().text_color(textColor).child(text));
  const cache = Number.isNaN(until) ? null : left < 0 ? ["cold", t.ansi1] : left < 5 ? [`${Math.max(left, 0) || "<1"}m left`, h.ORANGE] : [`${left}m left`, t.dim];

  return v_flex().id("office-card").absolute().top(12).right(12).w(380)
    .bg(t.popover).border(1).border_color(t.border).rounded(10).shadow_lg().text_color(t.foreground)
    .on_click((_e, cx) => cx.stop_propagation())
    .child(h_flex().gap(10).items_center().px(12).py(10).border_b(1).border_color(t.border)
      .child(image(`${ART}/sprites/${a.status === "blocked" ? "raise" : a.status === "done" ? "cheer" : "stand"}-${SPRITE_APPS.has(a.app) ? a.app : "agent"}.svg`).w(30).h(42).flex_none())
      .child(div().flex_1().min_w(0).truncate().text_size(13.5).font_semibold().child(h.agentName(a)))
      .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(h.duration(now - when))))
      .child(div().flex_none().h(18).px(7).rounded(5).bg(color + "26").text_color(color).text_size(10.5).font_semibold()
        .flex().items_center().child(label))
      .child(div().id("office-card-close").size(22).rounded(5).flex().items_center().justify_center().cursor_pointer()
        .hover((s) => s.bg(t.hover)).on_click((_e, cx) => { view.open = null; cx.notify(); })
        .child(svg("mods/workspace-chrome/x.svg").size(12).text_color(t.dim))))
    .child(v_flex().gap(9).px(12).pt(10).pb(12)
      .child(h_flex().flex_wrap().gap(4).items_center().text_size(10.5).text_color(t.muted)
        .child(chip(svg(`mods/workspace-chrome/${machine ? "server" : "monitor"}.svg`).size(10).text_color(t.dim), machine ?? "This computer"))
        .child(chip(div().size(12).rounded(3).bg(fill).flex().items_center().justify_center().text_size(8).font_bold().text_color("#ffffff")
          .child([...(a.space_name ?? "")][0]?.toUpperCase() ?? "?"), a.space_name ?? ""))
        .child(chip(/^\d+$/.test(a.tab_name ?? "") ? `Tab ${a.tab_name}` : a.tab_name ?? ""))
        .child(chip(svg("mods/workspace-chrome/git-branch.svg").size(10).text_color(t.dim), r.top ? `${repo} @ ${r.name}` : "outside git")))
      .when(Boolean(labels["agent.model"]), (el) => el.child(h_flex().gap(6).items_center().text_size(11.5)
        .child(div().text_color(t.foreground).child(labels["agent.model"]))
        .when(Boolean(labels["agent.effort"]), (el) => el.child(div().h(16).px(5).rounded(4).border(1).border_color(t.dim)
          .text_size(10).text_color(t.dim).flex().items_center().child(labels["agent.effort"])))
        .child(div().flex_1())
        .child(div().text_size(10.5).text_color(t.dim).child(a.program?.name ?? ""))))
      .when(!Number.isNaN(pct), (el) => el.child(meter("layers", "Context", pct, band, k ? `${pct}% · ${k}k` : `${pct}%`, band)))
      .when(Boolean(cache), (el) => el.child(meter("clock", "Cache", Math.max(0, left) / 60 * 100, cache[1] === t.dim ? t.accent : cache[1], cache[0], cache[1])))
      .child(a.status === "blocked"
        ? v_flex().gap(4)
          .child(div().text_size(12.5).font_medium().child(ask || "Needs you"))
          .when(Boolean(detail), (el) => el.child(div().text_size(11.5).text_color(t.muted).child(detail)))
          .when(!ask && Boolean(screen), (el) => el.child(div().mt(2).p(8).rounded(6).bg(t.background)
            .text_size(10.5).font_family("monospace").text_color(t.muted).whitespace_normal().child(screen)))
        : div().text_size(12).text_color(t.dim).child(a.status === "working" ? "Busy, nothing needed from you."
          : a.status === "done" ? "Finished. Look at it to mark it read."
          : expiring ? "Idle; its prompt cache goes cold in a few minutes." : "Idle."))
      .child(h_flex().gap(6).pt(2)
        .child(div().id("office-go").h(28).px(10).rounded(7).bg(t.solid).text_color(t.solid_foreground).text_size(12).font_medium()
          .flex().items_center().cursor_pointer().hover((s) => s.opacity(0.88))
          .on_click(() => { run("pane.focus", { pane: a.pane }); closeOverlay(props().overlay); })
          .child("Go to pane"))
        .child(div().id("office-peek").h(28).px(10).rounded(7).border(1).border_color(t.input).bg(t.raised).text_size(12)
          .flex().items_center().cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click(() => run("terminal.peek", { terminal: a.address }))
          .child("Peek"))));
}
