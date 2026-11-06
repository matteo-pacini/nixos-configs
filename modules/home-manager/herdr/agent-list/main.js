// Agents by where they run: anyone who needs you pinned at the top with what
// they ask, then machine (when there's more than one) and space, one line per
// agent; a space where everyone is idle folds to one line. Each agent is named
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
// An idle agent whose prompt cache goes cold soon, by its statusLine labels.
function cacheExpiring(a, labels, now) {
  if (a.status !== "idle") return false;
  const pct = parseInt(labels?.["agent.ctx"], 10);
  const left = parseInt(labels?.["agent.cache_until"], 10) * 1000 - now;
  return pct >= EXPIRING_CTX && left > 0 && left < EXPIRING_MS;
}
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

// The agents that label their version and session id (claude-statusline.sh,
// codex-labels.sh, opencode-labels.js), by the app herdr reports: the command
// on PATH, the package name in its store path, the label holding the session,
// how to quit (text to send, or `keys:` to press) and resume one, and the
// screen text of a prompt quitting can raise instead, which Enter answers.
// opencode takes pasted text as a prompt, so it's quit with a key. Claude asks
// before quitting with background work running; Enter takes its default, "Exit
// and stop tasks". Its "Move to background" would keep the old version running
// in a daemon under a forked session, so the resume would only reattach to it.
const APPS = {
  "claude-code": { name: "Claude Code", bin: "claude", pkg: "claude-code", session: "claude.session", quit: "/exit", resume: "claude --resume", asks: "Background work is running" },
  codex: { name: "Codex", bin: "codex", pkg: "codex", session: "codex.session", quit: "/quit", resume: "codex resume" },
  opencode: { name: "opencode", bin: "opencode", pkg: "opencode", session: "opencode.session", quit: "keys:ctrl+c", resume: "opencode -s" },
};

// Installed versions, `${machine}:${app}` -> { version, at }, re-read at most
// once a minute.
const installed = new Map();
const INSTALLED_MS = 60000;
// The command's store path, or for a wrapper script (opencode's launcher)
// the package path it execs.
const INSTALLED = `p=$(readlink -f /etc/profiles/per-user/"$USER"/bin/"$1" 2>/dev/null || readlink -f "$(command -v "$1")")
case "$p" in *-"$2"-[0-9]*) echo "$p" ;; *) grep -a -o -m1 -E "/nix/store/[a-z0-9]+-$2-[0-9][0-9.]*/" "$p" ;; esac`;

function cmpVersion(a, b) {
  const x = a.split(".").map(Number), y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

// The installed version of `app` on `machine` (null: this one), or null until
// read; reading it notifies `cx`.
function installedVersion(machine, app, cx) {
  const key = `${machine ?? ""}:${app.pkg}`;
  const known = installed.get(key);
  if (!known || Date.now() - known.at > INSTALLED_MS) {
    installed.set(key, { version: known?.version ?? null, at: Date.now() });
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", INSTALLED, "installed", app.bin, app.pkg], { on: machine }).catch(() => null);
      const version = new RegExp(`-${app.pkg}-(\\d[\\d.]*)/`).exec(r?.stdout ?? "")?.[1] ?? null;
      installed.set(key, { version, at: Date.now() });
      cx.notify();
    });
  }
  return known?.version ?? null;
}

// Quits the agent in `address`, answers the prompt quitting can raise (when
// its screen shows `app.asks`) with Enter, waits for its shell's prompt, then resumes
// `session` with the version now on PATH. The terminal's program has to be a
// shell that outlives the agent: an interactive one, which runs the agent in
// its own process group (hc's foreground is then another process), or a
// `sh -c "agent; exec sh"`, whose agent shares its group (the foreground is
// the script until it execs the shell). Quitting an agent that is the
// terminal's own program would end the terminal, and the resume would have
// no shell to type into. hc addresses remote terminals itself, so this runs here.
const SHELLS = /^-?(sh|bash|zsh|fish|dash|ksh)$/;
const isShell = (argv) => SHELLS.test((argv?.[0] ?? "").split("/").pop());
const isScript = (argv) => argv.slice(1).some((a) => /^-[a-z]*c[a-z]*$/.test(a));
const atPrompt = (t) => t.foreground?.pid === t.pid && isShell(t.foreground.argv) && !isScript(t.foreground.argv);
const fromShell = (t) => isShell(t.argv) && Boolean(t.foreground) && (t.foreground.pid !== t.pid
  || (isShell(t.foreground.argv) && /;\s*exec\s+\S*sh\b[^;]*$/.test(t.foreground.argv.at(-1))));

async function restartAgent(address, app, session) {
  const get = async () => {
    const r = await hc(["get", address, "--json"]);
    if (r.code !== 0) throw new Error(r.stderr.trim());
    return JSON.parse(r.stdout);
  };
  try {
    const t = await get();
    if (atPrompt(t)) throw new Error("it isn't running");
    if (!fromShell(t)) throw new Error("it isn't running from a shell");
    const quit = app.quit.startsWith("keys:") ? ["keys", address, app.quit.slice(5)] : ["send", address, app.quit];
    if ((await hc(quit)).code !== 0) throw new Error("couldn't tell it to quit");
    let quitted = false, asked = false;
    for (let i = 0; i < 60 && !quitted; i++) {
      await exec("sleep", ["0.5"]);
      quitted = atPrompt(await get());
      if (!quitted && app.asks && !asked && (await hc(["read", "--lines", "40", address])).stdout?.includes(app.asks)) {
        asked = (await hc(["keys", address, "enter"])).code === 0;
      }
    }
    if (!quitted) throw new Error("it didn't quit");
    await hc(["send", address, `${app.resume} ${session}`]);
  } catch (e) {
    notify({ title: `Couldn't restart ${app.name}`, body: String(e.message ?? e), level: "error" });
  }
}

// Types `text` and Enter into an agent's terminal (`machine/t7` for a remote one).
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
    openOverlay({ mod: "agent-list", kind: "dialog", width: 380, height: 220, props: { rename: a.address, value: current } });
  }

  // Right-click menu, a popup at the pointer drawn like the shipped `menu` mod.
  // `restart`: { app, latest, session } when this agent is older than the installed one.
  openMenu(a, current, restart = null) {
    const p = { menu: a.address, value: current, claude: a.app === "claude-code", blocked: a.status === "blocked",
      restart, busy: a.status === "blocked" || a.status === "working" };
    openOverlay({ mod: "agent-list", kind: "popup", width: 220, height: menuItems(p).length * 31 + 10, props: p });
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
    if (it.action === "restart") restartAgent(p.menu, APPS[p.restart.app], p.restart.session);
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
      .pl(26 + depth * 12 + 22)
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

  // What a row's tooltip says beyond its line: model and effort, context and
  // prompt cache from the labels the agents' statusLines set, and the running
  // version when it's outdated.
  details(labels, now, outdated, latest) {
    const parts = [];
    const model = labels?.["agent.model"];
    if (model) parts.push([model, labels["agent.effort"]].filter(Boolean).join(" "));
    const pct = parseInt(labels?.["agent.ctx"], 10);
    const k = labels?.["agent.ctxk"];
    if (!Number.isNaN(pct)) parts.push(`context ${pct}%${k ? ` (${k}k)` : ""}`);
    const until = parseInt(labels?.["agent.cache_until"], 10);
    if (!Number.isNaN(until)) {
      const left = Math.floor((until * 1000 - now) / 60000);
      parts.push(left < 0 ? "cache cold" : `cache ${left < 1 ? "<1" : left}m left`);
    }
    if (outdated) parts.push(`${labels["agent.version"]}, ${latest} installed`);
    return [parts.join(" · "), "Right-click for options"].filter(Boolean).join("\n");
  }

  // Version, outdated flag and restart offer for `a`, for its row and menu.
  versionOf(a, labels, cx) {
    const app = APPS[a.app];
    const running = app ? labels?.["agent.version"] : null;
    const machine = a.address.includes("/") ? a.address.split("/")[0] : null;
    const latest = running ? installedVersion(machine, app, cx) : null;
    const outdated = Boolean(latest) && cmpVersion(running, latest) < 0;
    const restart = outdated && labels?.[app.session] ? { app: a.app, latest, session: labels[app.session] } : null;
    return { latest, outdated, restart };
  }

  // A space's avatar: its colour, with its initial.
  mark(t, space) {
    const color = (shared("space.colors") ?? {})[space.id] ?? "ansi6";
    const fill = color.startsWith("#") ? color : (MARK[color] ?? t[color]);
    return div().size(13).flex_none().rounded(3).bg(fill).flex().items_center().justify_center()
      .text_size(8.5).font_bold().text_color("#ffffff").child([...(space.name ?? "")][0]?.toUpperCase() ?? "?");
  }

  // A pinned agent at the top: one that needs you, with what it asks (or that
  // it's done) under its name.
  pinRow(t, a, name, now, cx) {
    const labels = this.terms.get(a.address)?.labels;
    const urgency = this.urgency.get(a.address);
    const blocked = urgency === "blocked";
    const color = blocked ? t.blocked : (t.done ?? t.dim);
    // A sub-agent waiting on you asks through its parent's pin.
    const kid = blocked && a.status !== "blocked"
      ? this.tree([...this.terms.values()], a.address).map((s) => s.t).find((k) => kidStatus(k, this.listed) === "blocked")
      : null;
    const ask = (kid?.labels ?? labels)?.["agent.ask"];
    const when = this.changed[a.address]?.at;
    const { restart } = this.versionOf(a, labels, cx);
    const tab = /^\d+$/.test(a.tab_name ?? "") ? `Tab ${a.tab_name}` : a.tab_name;
    return v_flex().id(`pin-${a.address}`).flex_none().px(8).py(5).gap(2).rounded(8)
      .bg(color + "14").border_1().border_color(color + "40").cursor_pointer()
      .hover((s) => s.bg(color + "24"))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(a, labels?.[LABEL] ?? "", restart); })
      .child(h_flex().gap(7).items_center()
        .child(this.status(t, urgency, true))
        .child(div().flex_1().min_w(0).truncate().text_size(12.5).font_medium().text_color(t.foreground).child(name))
        .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - when)))))
      .child(div().pl(21).truncate().text_size(11).text_color(blocked ? t.blocked : t.dim)
        .child(blocked ? (ask ? (kid ? `${kid.labels?.[LABEL] || kid.name || "Sub-agent"}: ${ask}` : ask) : `Needs you · ${a.space_name} · ${tab}`)
          : `Done · ${a.space_name} · ${tab}`));
  }

  // An agent on one line under its space: app, name, tab, age (or the cache
  // time left when that's running out) and state. The rest is in its tooltip.
  agentLine(t, a, name, subs, now, cx) {
    const key = `ag-${a.address}`;
    const pic = icon(a.program, 14, t.foreground);
    const labels = this.terms.get(a.address)?.labels;
    const urgency = this.urgency.get(a.address);
    const when = this.changed[a.address]?.at;
    const expiring = cacheExpiring({ status: urgency }, labels, now);
    const left = Math.floor((parseInt(labels?.["agent.cache_until"], 10) * 1000 - now) / 60000);
    const { latest, outdated, restart } = this.versionOf(a, labels, cx);
    const tab = /^\d+$/.test(a.tab_name ?? "") ? `T${a.tab_name}` : a.tab_name;
    return h_flex().id(key).h(26).pl(26).pr(8).gap(8).flex_none().items_center().rounded(8).text_size(12.5)
      .when(a.focused, (el) => el.bg(t.selected))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(a, labels?.[LABEL] ?? "", restart); })
      .tooltip(this.details(labels, now, outdated, latest))
      .when(Boolean(pic), (el) => el.child(div().id(`fold-${key}`)
        .when(subs.length > 0, (el) => el.on_click((_e, cx) => { cx.stop_propagation(); this.toggle(key, cx); }))
        .child(pic)))
      .child(div().flex_1().min_w(0).truncate().text_color(urgency === "idle" && !a.focused ? t.muted : t.foreground).child(name))
      .when(subs.length > 0 && this.folded.has(key), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(String(subs.length))))
      .when(outdated, (el) => el.child(div().size(5).flex_none().rounded(3).bg(ORANGE)))
      .child(div().flex_none().max_w(44).truncate().text_size(11).text_color(t.dim).child(tab ?? ""))
      .child(expiring
        ? h_flex().flex_none().gap(3).items_center().text_size(11).text_color(ORANGE)
          .child(svg("mods/workspace-chrome/clock.svg").size(10).flex_none())
          .child(div().child(left < 1 ? "<1m" : `${left}m`))
        : div().flex_none().w(26).text_right().text_size(11).text_color(t.dim).child(when ? duration(now - when) : ""))
      .child(h_flex().w(14).flex_none().items_center().justify_center().child(this.status(t, urgency, true)));
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

    // A live sub-agent of a listed agent is drawn under its parent only, and
    // its status already reaches the parent through urgency.
    const tops = list.filter((a) => !(this.terms.get(a.address)?.state === "live" && this.listed.has(this.terms.get(a.address)?.parent)));

    // Pinned: everyone who needs you (done counts: it finished and you haven't
    // looked yet). They stay in their space below as well.
    const rows = tops.filter((a) => ["blocked", "done"].includes(this.urgency.get(a.address)))
      .map((a) => this.pinRow(t, a, agentName(a, this.terms.get(a.address)), now, cx));
    if (rows.length) rows.unshift(div().h(2).flex_none());

    // Then by machine (this computer first) and space, in the Spaces list's order.
    const spaceList = spaces();
    const machines = [...new Set([null, ...spaceList.map((s) => s.machine ?? null)])];
    const multi = new Set(spaceList.filter((s) => tops.some((a) => a.space === s.id)).map((s) => s.machine ?? null)).size > 1;
    for (const machine of machines) {
      const here = spaceList.filter((s) => (s.machine ?? null) === machine && tops.some((a) => a.space === s.id));
      if (!here.length) continue;
      if (multi) rows.push(h_flex().pl(8).pt(12).pb(2).flex_none().gap(6).items_center()
        .text_size(10.5).font_semibold().text_color(t.dim)
        .child(svg(`mods/workspace-chrome/${machine ? "server" : "monitor"}.svg`).size(10).flex_none())
        .child(div().child((machine ?? "This computer").toUpperCase())));
      for (const sp of here) {
        // Most urgent first; the list's own order otherwise.
        const members = tops.filter((a) => a.space === sp.id)
          .map((a, i) => [a, i]).sort(([x, i], [y, j]) => (RANK[this.urgency.get(y.address)] ?? 0) - (RANK[this.urgency.get(x.address)] ?? 0) || i - j)
          .map(([a]) => a);
        // A space where everyone is idle folds to one line unless opened; any
        // other space shows its agents unless folded.
        const idle = members.every((a) => this.urgency.get(a.address) === "idle");
        const sid = idle ? `spopen-${sp.id}` : `sp-${sp.id}`;
        const open = idle ? this.folded.has(sid) : !this.folded.has(sid);
        rows.push(h_flex().id(sid).pl(8).pr(8).pt(8).pb(2).flex_none().gap(7).items_center().cursor_pointer()
          .on_click((_e, cx) => this.toggle(sid, cx))
          .child(this.mark(t, sp))
          .child(div().min_w(0).truncate().text_size(12).font_semibold().text_color(t.foreground).child(sp.name))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(idle && !open ? `${members.length} idle` : String(members.length)))
          .when(!open, (el) => el.child(svg("mods/workspace-chrome/chevron-right.svg").size(10).flex_none().text_color(t.dim))));
        if (!open) continue;
        for (const a of members) {
          const subs = this.tree(all, a.address);
          rows.push(this.agentLine(t, a, agentName(a, this.terms.get(a.address)), subs, now, cx));
          if (!this.folded.has(`ag-${a.address}`)) rows.push(...subs.map((s) => this.subRow(t, s, 0, shown)));
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
