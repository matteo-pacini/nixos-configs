// Agents grouped by what they need: Needs you, Cache expiring, Working, Idle;
// each says where it runs (machine, space, tab). Each agent is named
// by its terminal's `agent.name` label (right-click a row, or
// `hc label <t> agent.name=...`), falling back to its hc name, then its title.
// Derived from Herdr's shipped `agents` mod.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { agents, terminals, spaces, focused, run, hc, exec, theme, shared, setShared, setAgentOrder, openOverlay, closeOverlay, notify, props, window, layout } from "herdr";

const LABEL = "agent.name";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Other mods may still read the flag rather than the width.
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", { id: "sidebar", px: narrow() ? (shared("sidebar.width") ?? 268) : window()?.platform === "macos" ? 76 : 44 });
}

const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}]+/u, "").trim();

const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };
// A sub-agent without a pane isn't in agents(): its raw word, error counting as
// blocked. It's never done: it reports to its parent, and the parent's done is the news.
const kidStatus = (k, listed) => {
  const s = listed.get(k.address) ?? k.status;
  return s === "error" ? "blocked" : s === "done" ? "idle" : s;
};
// Space avatar colours, as the spaces mod draws them.
const MARK = { ansi6: "#22a99a", ansi3: "#e3814f", ansi4: "#5b8def", ansi5: "#8b7cf6", ansi2: "#3fae6a", ansi1: "#d9649a" };
const ORANGE = MARK.ansi3;
// An idle agent counts as cache expiring with less than this much prompt cache
// left and at least EXPIRING_CTX % of its context filled: letting the cache go
// cold would mean paying for that context again.
const EXPIRING_MS = 5 * 60000;
const EXPIRING_CTX = 20;
const top = (statuses) => statuses.reduce((m, s) => ((RANK[s] ?? 0) > (RANK[m] ?? 0) ? s : m), null);

function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

// `term`: the agent's entry in terminals(), if listed yet.
function agentName(a, term) {
  return term?.labels?.[LABEL] || term?.name || clean(a.title) || a.program?.name || a.address;
}

// The right-click menu for an agent; `p` holds `claude` and `blocked`.
// The slash commands are Claude-only, and off while the agent waits on a
// prompt: the Enter after the command would answer that prompt instead.
function menuItems(p) {
  const slash = (label, icon, command) =>
    ({ label, icon, send: command, disabled: p.blocked, hint: p.blocked ? "needs you" : command });
  return [
    { label: "Rename", icon: "square-pen", action: "rename" },
    ...(p.claude ? [slash("Clear", "terminal", "/clear"), slash("Compact", "layers", "/compact")] : []),
    ...(p.restart ? [{ label: `Restart on ${p.restart.latest}`, icon: "terminal", action: "restart",
      disabled: p.busy, hint: p.busy ? "wait for idle" : "resume" }] : []),
  ];
}

// Types `text` and Enter into an agent's terminal (`machine/t7` for a remote one).
// The claude-code version on PATH per machine ("" for this one), re-read at
// most once a minute: { version, at }. Same check as the claude-pane mod.
const installed = new Map();
const INSTALLED_MS = 60000;
const INSTALLED = 'readlink -f /etc/profiles/per-user/"$USER"/bin/claude 2>/dev/null || readlink -f "$(command -v claude)"';

function cmpVersion(a, b) {
  const x = a.split(".").map(Number), y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

// Exits Claude in `address`, waits for its shell, then resumes `session` with
// the claude now on PATH. hc addresses remote terminals itself, so this runs here.
const RESTART = `hc send "$1" /exit >/dev/null || exit 1
for _ in $(seq 60); do
  hc get "$1" --json | grep -q 'claude-code-[0-9]' || break
  sleep 0.5
done
hc send "$1" "claude --resume $2" >/dev/null`;

async function restartClaude(address, session) {
  const r = await exec("sh", ["-c", RESTART, "restart", address, session]);
  if (r.code !== 0) notify({ title: "Couldn't restart Claude Code", body: r.stderr || r.stdout, level: "error" });
}

async function sendTo(address, text) {
  const r = await hc(["send", address, text]);
  if (r.code !== 0) notify({ title: `Couldn't send ${text}`, body: r.stderr || r.stdout, level: "error" });
}

export default class AgentTree extends View {
  init(_props, cx) {
    if (props()?.rename) return this.initRename();
    if (props()?.menu) return this.initMenu(cx);
    this.folded = new Set(JSON.parse(localStorage.getItem("folded") ?? "[]"));
    // Each agent's last state and when it changed (ms), kept across restarts.
    this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    cx.timer.every(30000, (cx) => cx.notify());
  }

  initRename() {
    const value = props().value ?? "";
    this.input = InputState.new({ value });
    if (value) this.input.set_selected_range({ start: 0, end: value.length });
    this.input.on("submit", () => this.saveName());
    this.input.focus();
  }

  async saveName() {
    const p = props();
    closeOverlay(p.overlay);
    const r = await hc(["label", p.rename, `${LABEL}=${this.input.value().trim()}`]);
    if (r.code !== 0) notify({ title: "Couldn't rename agent", body: r.stderr || r.stdout, level: "error" });
  }

  renameDialog(t) {
    const p = props();
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    return v_flex().w_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(p.overlay); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child("Rename agent"))
      .child(div().pt(16).pb(7).text_size(11.5).text_color(t.dim).child("Name"))
      .child(Input.new(this.input).h(36).px(10).rounded(9).border_1().border_color(t.accent).bg(t.background).text_size(12.8).text_color(t.foreground))
      .child(div().pt(6).text_size(11.5).text_color(t.dim).child("Empty goes back to the agent's own title."))
      .child(h_flex().pt(20).gap(8).justify_end()
        .child(button("rn-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button("rn-save", "Save", true, () => this.saveName())));
  }

  rename(a, current) {
    openOverlay({ mod: "agent-tree", kind: "dialog", width: 380, height: 220, props: { rename: a.address, value: current } });
  }

  // Right-click menu, a popup at the pointer drawn like the shipped `menu` mod.
  // `restart`: { latest, session } when this Claude is older than the installed one.
  openMenu(a, current, restart = null) {
    const p = { menu: a.address, value: current, claude: a.app === "claude-code", blocked: a.status === "blocked",
      restart, busy: a.status === "blocked" || a.status === "working" };
    openOverlay({ mod: "agent-tree", kind: "popup", width: 220, height: menuItems(p).length * 31 + 10, props: p });
  }

  initMenu(cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  chooseMenu(i) {
    const p = props(), it = menuItems(p)[i];
    if (!it || it.disabled) return;
    closeOverlay(p.overlay);
    if (it.action === "rename") this.rename({ address: p.menu }, p.value ?? "");
    if (it.send) sendTo(p.menu, it.send);
    if (it.action === "restart") restartClaude(p.menu, p.restart.session);
  }

  // The installed claude-code version on `machine`, or null until read.
  installed(machine, cx) {
    const key = machine ?? "";
    const known = installed.get(key);
    if (!known || Date.now() - known.at > INSTALLED_MS) {
      installed.set(key, { version: known?.version ?? null, at: Date.now() });
      cx.spawn(async (cx) => {
        const r = await exec("sh", ["-c", INSTALLED], { on: machine }).catch(() => null);
        const version = /-claude-code-([\d.]+)\//.exec(r?.stdout ?? "")?.[1] ?? null;
        installed.set(key, { version, at: Date.now() });
        cx.notify();
      });
    }
    return known?.version ?? null;
  }

  menuPopup(t) {
    const p = props(), list = menuItems(p);
    return v_flex().id("ag-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") this.chooseMenu(this.at);
        else if (e.key === "escape") closeOverlay(p.overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => h_flex().id(`agm-${i}`).h(31).px(8).gap(9).rounded(7).items_center()
        .text_color(it.disabled ? t.dim : t.foreground)
        .when(i === this.at && !it.disabled, (el) => el.bg(t.selected))
        .when(!it.disabled, (el) => el.hover((s) => s.bg(t.hover)).on_click(() => this.chooseMenu(i)))
        .child(svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(it.disabled ? t.dim : t.muted))
        .child(div().flex_1().child(it.label))
        .when(Boolean(it.hint), (el) => el.child(div().text_size(11).text_color(t.dim).child(it.hint)))));
  }

  toggle(id, cx) {
    this.folded.has(id) ? this.folded.delete(id) : this.folded.add(id);
    localStorage.setItem("folded", JSON.stringify([...this.folded]));
    cx.notify();
  }

  // Stamps agents whose state changed. Done and idle count as one: looking at a
  // finished agent turns done into idle, and looking isn't the agent doing anything.
  track(list, now) {
    let dirty = false;
    for (const a of list) {
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s === s) continue;
      this.changed[a.address] = { s, at: now };
      dirty = true;
    }
    if (!dirty) return;
    const listed = new Set(list.map((a) => a.address));
    for (const [k, c] of Object.entries(this.changed)) if (!listed.has(k) && now - c.at > 30 * 86400000) delete this.changed[k];
    localStorage.setItem("changed", JSON.stringify(this.changed));
  }

  // Live sub-agents of `addr`, depth first, each with the tree lines in front of it.
  tree(all, addr, lead = []) {
    const kids = all.filter((k) => k.parent === addr && k.state === "live");
    return kids.flatMap((k, i) => {
      const last = i === kids.length - 1;
      return [
        { t: k, lines: [...lead, last ? "└" : "├"] },
        ...this.tree(all, k.address, [...lead, last ? "" : "│"]),
      ];
    });
  }

  status(t, status, compact = false) {
    if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).mx(1).flex_none().text_color(t.working).spin(900);
    if (status === "blocked" && compact) return div().size(14).flex_none().rounded(4).bg(t.blocked + "26").text_size(10.5).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
    if (status === "blocked") return div().flex_none().px(6).h(18).rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).flex().items_center().child("Needs you");
    if (status === "idle") return div().size(7).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
    return div().size(7).mx(3).flex_none().rounded(4).bg(status === "done" ? (t.done ?? t.dim) : t.dim + "00");
  }

  subRow(t, s, depth, shown) {
    const k = s.t;
    const pic = icon(k.program, 14, t.foreground);
    const on = k.address === shown;
    return h_flex()
      .id(`sub-${k.address}`)
      .pl(8 + depth * 12 + 22)
      .pr(8)
      .rounded(8)
      .h(26)
      .flex_none()
      .items_center()
      .text_size(12.5)
      .when(on, (el) => el.bg(t.raised))
      .hover((el) => el.bg(t.hover))
      .on_click(() => run("terminal.peek", { terminal: k.address }))
      .children(s.lines.map((l) => div().self_start().mt(-4).w(9).h(17).mr(4).flex_none()
        .when(Boolean(l), (el) => el.border_l(1.5).border_color(t.input))
        .when(l === "└" || l === "├", (el) => el.border_b(1.5).rounded_bl(6))))
      .when(Boolean(pic), (el) => el.child(div().mr(8).child(pic)))
      .child(div().flex_1().truncate().text_color(on ? t.foreground : t.muted).child(k.labels?.[LABEL] || k.name || k.template || k.program?.name || k.address))
      .child(this.status(t, kidStatus(k, this.listed), true));
  }

  // Context fill and prompt-cache time left, from the labels Claude's statusLine
  // sets (modules/home-manager/herdr/claude-statusline.sh); null without them.
  metrics(t, labels, now, expiring = false) {
    const pct = parseInt(labels?.["agent.ctx"], 10);
    const until = parseInt(labels?.["agent.cache_until"], 10);
    if (Number.isNaN(pct) && Number.isNaN(until)) return null;
    // Bands match herdr-agent-report: Claude auto-compacts at 80%.
    const band = expiring ? ORANGE : pct >= 70 ? t.ansi1 : pct >= 50 ? t.ansi3 : t.ansi2;
    const k = labels?.["agent.ctxk"];
    const left = Math.floor((until * 1000 - now) / 60000);
    const cache = left < 0 ? ["cold", t.ansi1] : left < 1 ? ["<1m", ORANGE] : left < 5 ? [`${left}m`, ORANGE] : [`${left}m`, t.dim];
    return h_flex().gap(6).items_center().text_size(10.5).text_color(t.dim)
      .when(!Number.isNaN(pct), (el) => el
        .child(div().w(48).h(4).flex_none().rounded(2).bg(t.input)
          .child(div().h_full().rounded(2).bg(band).w(Math.round(48 * Math.min(pct, 100) / 100))))
        .child(div().text_color(band).child(`${pct}%`))
        .when(Boolean(k), (el) => el.child(div().child(`${k}k`))))
      .when(!Number.isNaN(until), (el) => el
        .child(div().flex_1())
        .child(h_flex().gap(3).items_center().text_color(cache[1])
          .child(svg("mods/workspace-chrome/clock.svg").size(10).flex_none())
          .child(div().child(cache[0]))));
  }

  // Model and reasoning effort, from the labels Claude's statusLine sets, and
  // the running version when it's outdated; null without them.
  model(t, labels, outdated = false) {
    const model = labels?.["agent.model"];
    if (!model) return null;
    const effort = labels?.["agent.effort"];
    return h_flex().gap(6).items_center().text_size(11).text_color(t.dim)
      .child(div().min_w(0).truncate().text_color(t.foreground).child(model))
      .when(Boolean(effort), (el) => el.child(div().flex_none().px(5).h(16).rounded(4).border(1).border_color(t.dim)
        .flex().items_center().text_size(10).child(effort)))
      .when(outdated, (el) => el.child(div().flex_none().text_color(t.ansi3).child(labels["agent.version"])));
  }

  // A card's status: a labelled pill, readable beside the extra lines. Idle
  // keeps the plain dot.
  pill(t, status) {
    const [label, color] = { working: ["Working", t.working], done: ["Done", t.done ?? t.dim], blocked: ["Needs you", t.blocked] }[status] ?? [];
    if (!label) return this.status(t, status);
    return h_flex().flex_none().gap(5).px(7).h(18).rounded(5).bg(color + "26").items_center()
      .text_size(10.5).font_semibold().text_color(color)
      .when(status === "working", (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(10).flex_none().spin(900)))
      .child(label);
  }

  // Machine, space and tab as chips. `loc`: { host, space, spaceId, tab }.
  where(t, loc) {
    const chip = () => h_flex().flex_none().h(17).px(6).gap(4).rounded(5).bg(t.hover).items_center();
    const color = (shared("space.colors") ?? {})[loc.spaceId] ?? "ansi6";
    const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    return h_flex().flex_wrap().gap(4).gap_y(3).items_center().text_size(10.5).text_color(t.muted)
      .child(chip().child(svg(`mods/workspace-chrome/${loc.host ? "server" : "monitor"}.svg`).size(10).flex_none().text_color(t.dim))
        .child(loc.host ?? "This computer"))
      .child(chip().child(div().size(12).flex_none().rounded(3).bg(fill).flex().items_center().justify_center()
        .text_size(8).font_bold().text_color("#ffffff").child([...(loc.space ?? "")][0]?.toUpperCase() ?? "?"))
        .child(div().max_w(110).truncate().child(loc.space ?? "")))
      .child(chip().text_color(t.dim).child(loc.tab ?? ""));
  }

  // An agent: name and status, then (with `loc`) where it runs, then model and
  // context and cache for one whose statusLine sets labels.
  agentRow(t, a, depth, name, subs, now, cx, loc = null, expiring = false) {
    const key = `ag-${a.address}`;
    const pic = icon(a.program, 16, t.foreground);
    const when = this.changed[a.address]?.at;
    const idle = a.status === "idle" && !a.focused;
    const labels = this.terms.get(a.address)?.labels;
    const stats = this.metrics(t, labels, now, expiring);
    const running = a.app === "claude-code" ? labels?.["agent.version"] : null;
    const machine = a.address.includes("/") ? a.address.split("/")[0] : null;
    const latest = running ? this.installed(machine, cx) : null;
    const outdated = Boolean(latest) && cmpVersion(running, latest) < 0;
    const restart = outdated && labels?.["claude.session"] ? { latest, session: labels["claude.session"] } : null;
    const model = this.model(t, labels, outdated);
    const card = Boolean(stats || model || loc);
    const head = h_flex().items_center().gap(9)
      .when(Boolean(pic), (el) => el.child(div().id(`fold-${key}`)
        .when(subs.length > 0, (el) => el.on_click((_e, cx) => { cx.stop_propagation(); this.toggle(`ag-${a.address}`, cx); }))
        .child(pic)))
      .child(div().flex_1().min_w(0).truncate().when(card, (el) => el.font_medium()).text_color(idle ? t.muted : t.foreground).child(name))
      .when(subs.length > 0 && this.folded.has(`ag-${a.address}`), (el) => el.child(div().text_size(11).text_color(t.dim).child(String(subs.length))))
      .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - when))))
      .when(outdated, (el) => el.child(div().flex_none().px(6).h(17).rounded(4).bg(t.ansi3 + "26").flex().items_center()
        .text_size(10).font_bold().text_color(t.ansi3).child("OUTDATED")))
      .child(card && !expiring ? this.pill(t, a.status) : this.status(t, expiring ? "idle" : a.status));
    return v_flex()
      .id(key)
      .pl(8 + depth * 12)
      .pr(8)
      .when(card, (el) => el.py(7).gap(4))
      .when(!card, (el) => el.h(30).justify_center())
      .flex_none()
      .rounded(8)
      .when(a.focused, (el) => el.bg(t.selected))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(a, labels?.[LABEL] ?? "", restart); })
      .tooltip("Right-click for options")
      .child(head)
      // 25: the program icon plus the head's gap, so these lines start under the name.
      .when(Boolean(loc), (el) => el.child(div().pl(pic ? 25 : 0).child(this.where(t, loc))))
      .when(Boolean(model), (el) => el.child(div().pl(pic ? 25 : 0).child(model)))
      .when(Boolean(stats), (el) => el.child(div().pl(pic ? 25 : 0).child(stats)));
  }

  render(cx) {
    const t = theme();
    if (props()?.rename) return this.renameDialog(t);
    if (props()?.menu) return this.menuPopup(t);
    const collapsed = narrow();
    const list = agents();
    const all = terminals();
    this.listed = new Map(list.map((a) => [a.address, a.status]));
    this.terms = new Map(all.map((k) => [k.address, k]));
    const shown = focused()?.agent;
    const now = Date.now();
    this.track(list, now);
    this.urgency = new Map(list.map((a) => [a.address,
      top([a.status, ...this.tree(all, a.address).map((s) => kidStatus(s.t, this.listed))])]));
    setAgentOrder(list.map((a) => a.address));

    if (collapsed) {
      const rail = list.map((a, i) => h_flex().id(`ag-${a.address}`).h(26).px(8).flex_none().items_center().gap(4)
        .hover((s) => s.bg(t.hover))
        .on_click(() => run("pane.focus", { pane: a.pane }))
        .child(div().flex_1().min_w(0).whitespace_nowrap().text_right().text_color(t.muted).child(String(i + 1)))
        .child(h_flex().w(14).flex_none().items_center().justify_center().child(this.status(t, a.status, true))));
      return this.frame(t, true, rail, list.length);
    }

    const machineOf = new Map(spaces().map((s) => [s.id, s.machine ?? null]));
    const hostOf = (a) => machineOf.get(a.space) ?? (a.address.includes("/") ? a.address.split("/")[0] : null);
    const tabName = (a) => (/^\d+$/.test(a.tab_name ?? "") ? `Tab ${a.tab_name}` : a.tab_name);
    const isExpiring = (a) => {
      if (this.urgency.get(a.address) !== "idle") return false;
      const labels = this.terms.get(a.address)?.labels;
      const pct = parseInt(labels?.["agent.ctx"], 10);
      const left = parseInt(labels?.["agent.cache_until"], 10) * 1000 - now;
      return pct >= EXPIRING_CTX && left > 0 && left < EXPIRING_MS;
    };
    // Done counts as needing you: it finished and you haven't looked yet.
    const groups = [
      { id: "need", label: "Needs you", color: t.blocked, test: (a) => ["blocked", "done"].includes(this.urgency.get(a.address)) },
      { id: "expiring", label: "Cache expiring", color: ORANGE, test: isExpiring },
      { id: "working", label: "Working", color: t.dim, test: (a) => this.urgency.get(a.address) === "working" },
      { id: "idle", label: "Idle", color: t.dim, test: () => true },
    ];
    const placed = new Map();
    for (const a of list) placed.set(a.address, groups.find((g) => g.test(a)).id);

    const rows = [];
    for (const g of groups) {
      const members = list.filter((a) => placed.get(a.address) === g.id);
      if (!members.length) continue;
      const gid = `grp-${g.id}`;
      const open = !this.folded.has(gid);
      rows.push(h_flex().id(gid).pl(8).pr(8).pt(10).pb(4).flex_none().gap(6).items_center()
        .text_size(10.5).font_semibold().text_color(g.color).cursor_pointer()
        .on_click((_e, cx) => this.toggle(gid, cx))
        .child(div().child(`${g.label.toUpperCase()} · ${members.length}`))
        .when(!open, (el) => el.child(svg("mods/workspace-chrome/chevron-right.svg").size(10).flex_none())));
      if (!open) continue;
      for (const a of members) {
        const subs = this.tree(all, a.address);
        const loc = { host: hostOf(a), space: a.space_name, spaceId: a.space, tab: tabName(a) };
        rows.push(this.agentRow(t, a, 0, agentName(a, this.terms.get(a.address)), subs, now, cx, loc, g.id === "expiring"));
        if (!this.folded.has(`ag-${a.address}`)) rows.push(...subs.map((s) => this.subRow(t, s, 0, shown)));
      }
    }
    return this.frame(t, false, rows, list.length);
  }

  frame(t, collapsed, rows, count) {
    return v_flex()
      .size_full()
      .min_h(0)
      .bg(t.chrome)
      .border_t(1)
      .border_color(t.border)
      .text_size(13)
      .when(!collapsed, (el) => el.child(h_flex().px(16).h(41).pt(14).pb(5).flex_none().items_center()
        .child(div().text_size(11.5).font_medium().text_color(t.dim).child("Agents"))))
      .when(count === 0 && !collapsed, (el) =>
        el.child(div().px(12).text_size(12).text_color(t.dim).child("No agent status yet. Agents show up here when they report their status.")))
      .child(v_flex().id("ag-list").flex_1().min_h(0).px(collapsed ? 0 : 8).overflow_y_scrollbar().mode("always").children(rows))
      .child(h_flex().h(28).px(12).items_center().justify_end()
        .when(collapsed, (el) => el.justify_center().px(0))
        .child(div().id("collapse").text_size(13).text_color(t.dim).hover((s) => s.text_color(t.foreground))
          .on_click(toggleSidebar).child(collapsed ? "»" : "")));
  }
}
