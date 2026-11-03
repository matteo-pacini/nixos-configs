// Agents as a tree: host > space > tab > agent > sub-agents. Each agent is named
// by its terminal's `agent.name` label (right-click a row, or
// `hc label <t> agent.name=...`), falling back to its hc name, then its title.
// Derived from Herdr's shipped `agents` mod.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { agents, terminals, spaces, focused, run, hc, theme, shared, setShared, setAgentOrder, openOverlay, closeOverlay, notify, props, window, layout } from "herdr";

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

export default class AgentTree extends View {
  init(_props, cx) {
    if (props()?.rename) return this.initRename();
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

  // A foldable group header at `depth` (0 host, 1 space, 2 tab). Folded, it shows
  // how many agents and the most urgent state among them.
  header(t, id, depth, text, members) {
    const open = !this.folded.has(id);
    const worst = top(members.map((a) => this.urgency.get(a.address)));
    return h_flex()
      .id(id)
      .pl(8 + depth * 12)
      .pr(8)
      .pt(depth === 0 ? 8 : 4)
      .h(depth === 0 ? 30 : 26)
      .flex_none()
      .gap(6)
      .items_center()
      .text_size(depth === 0 ? 11 : 12)
      .font_medium()
      .text_color(depth === 0 ? t.dim : t.muted)
      .cursor_pointer()
      .hover((s) => s.text_color(t.foreground))
      .on_click((_e, cx) => this.toggle(id, cx))
      .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(11).flex_none().text_color(t.dim))
      .child(div().flex_1().min_w(0).truncate().child(text))
      .when(!open, (el) => el
        .child(div().text_size(11).text_color(t.dim).child(String(members.length)))
        .when(Boolean(worst) && worst !== "idle", (el) => el.child(this.status(t, worst, true))));
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
  metrics(t, labels, now) {
    const pct = parseInt(labels?.["agent.ctx"], 10);
    const until = parseInt(labels?.["agent.cache_until"], 10);
    if (Number.isNaN(pct) && Number.isNaN(until)) return null;
    // Bands match herdr-agent-report: Claude auto-compacts at 80%.
    const band = pct >= 70 ? t.ansi1 : pct >= 50 ? t.ansi3 : t.ansi2;
    const k = labels?.["agent.ctxk"];
    const left = Math.floor((until * 1000 - now) / 60000);
    const cache = left < 0 ? ["cold", t.ansi1] : left < 1 ? ["<1m", t.ansi3] : left < 5 ? [`${left}m`, t.ansi3] : [`${left}m`, t.dim];
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

  // Model and reasoning effort, from the labels Claude's statusLine sets; null
  // without them.
  model(t, labels) {
    const model = labels?.["agent.model"];
    if (!model) return null;
    const effort = labels?.["agent.effort"];
    return h_flex().gap(6).items_center().text_size(11).text_color(t.dim)
      .child(div().min_w(0).truncate().text_color(t.foreground).child(model))
      .when(Boolean(effort), (el) => el.child(div().flex_none().px(5).h(16).rounded(4).border(1).border_color(t.dim)
        .flex().items_center().text_size(10).child(effort)));
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

  // One line for a plain agent; a card (name, model, metrics) for one whose
  // statusLine sets labels.
  agentRow(t, a, depth, name, subs, now) {
    const pic = icon(a.program, 16, t.foreground);
    const when = this.changed[a.address]?.at;
    const idle = a.status === "idle" && !a.focused;
    const labels = this.terms.get(a.address)?.labels;
    const stats = this.metrics(t, labels, now);
    const model = this.model(t, labels);
    const card = Boolean(stats || model);
    const head = h_flex().items_center().gap(9)
      .when(Boolean(pic), (el) => el.child(div().id(`fold-${a.address}`)
        .when(subs.length > 0, (el) => el.on_click((_e, cx) => { cx.stop_propagation(); this.toggle(`ag-${a.address}`, cx); }))
        .child(pic)))
      .child(div().flex_1().min_w(0).truncate().when(card, (el) => el.font_medium()).text_color(idle ? t.muted : t.foreground).child(name))
      .when(subs.length > 0 && this.folded.has(`ag-${a.address}`), (el) => el.child(div().text_size(11).text_color(t.dim).child(String(subs.length))))
      .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - when))))
      .child(card ? this.pill(t, a.status) : this.status(t, a.status));
    return v_flex()
      .id(`ag-${a.address}`)
      .pl(8 + depth * 12)
      .pr(8)
      .when(card, (el) => el.py(8).gap(5))
      .when(!card, (el) => el.h(30).justify_center())
      .flex_none()
      .rounded(8)
      .when(a.focused, (el) => el.bg(t.selected))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", () => this.rename(a, labels?.[LABEL] ?? ""))
      .tooltip("Right-click to rename")
      .child(head)
      // 25: the program icon plus the head's gap, so these lines start under the name.
      .when(Boolean(model), (el) => el.child(div().pl(pic ? 25 : 0).child(model)))
      .when(Boolean(stats), (el) => el.child(div().pl(pic ? 25 : 0).child(stats)));
  }

  render(cx) {
    const t = theme();
    if (props()?.rename) return this.renameDialog(t);
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

    // host -> space -> tab -> agents, in agents() order (space, tab, pane).
    const machineOf = new Map(spaces().map((s) => [s.id, s.machine ?? null]));
    const hosts = new Map();
    for (const a of list) {
      const host = machineOf.get(a.space) ?? (a.address.includes("/") ? a.address.split("/")[0] : null);
      if (!hosts.has(host)) hosts.set(host, new Map());
      const sps = hosts.get(host);
      if (!sps.has(a.space)) sps.set(a.space, { name: a.space_name, tabs: new Map() });
      const tabs = sps.get(a.space).tabs;
      if (!tabs.has(a.tab)) tabs.set(a.tab, { name: a.tab_name, members: [] });
      tabs.get(a.tab).members.push(a);
    }
    const showHosts = hosts.size > 1;
    const membersOf = (sps) => [...sps.values()].flatMap((sp) => [...sp.tabs.values()].flatMap((tb) => tb.members));

    const rows = [];
    for (const [host, sps] of hosts) {
      const hostId = `host-${host ?? "local"}`;
      const d0 = showHosts ? 1 : 0;
      if (showHosts) {
        rows.push(this.header(t, hostId, 0, host ?? "This computer", membersOf(sps)));
        if (this.folded.has(hostId)) continue;
      }
      for (const [spaceId, sp] of sps) {
        const spId = `sp-${spaceId}`;
        rows.push(this.header(t, spId, d0, sp.name || "", membersOf(new Map([[spaceId, sp]]))));
        if (this.folded.has(spId)) continue;
        for (const [tabId, tb] of sp.tabs) {
          const tbId = `tb-${tabId}`;
          rows.push(this.header(t, tbId, d0 + 1, /^\d+$/.test(tb.name ?? "") ? `Tab ${tb.name}` : tb.name, tb.members));
          if (this.folded.has(tbId)) continue;
          for (const a of tb.members) {
            const subs = this.tree(all, a.address);
            rows.push(this.agentRow(t, a, d0 + 2, agentName(a, this.terms.get(a.address)), subs, now));
            if (!this.folded.has(`ag-${a.address}`)) rows.push(...subs.map((s) => this.subRow(t, s, d0 + 2, shown)));
          }
        }
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
