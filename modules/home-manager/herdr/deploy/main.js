// Deploy pipeline for matteo-pacini/nixos-configs: master → build.yml → the
// deploy branch → each host's comin; below it, the checkout's upstream tags
// (watch.js) and whether each is ready to act on. The `deploy` block of the
// agent-tree layout, shown only while the focused terminal is in a checkout
// of that repo (any machine). A manual `layout.toggle deploy` sticks until
// the focus moves to another folder.
// Hosts are read over plain SSH using the aliases in ~/.ssh/config; the
// machine this runs on is read locally.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, theme, window, run, spaces, panes, focused, settings } from "herdr";
import { findTags, checkTag, shortRef, ORDER } from "./watch.js";

const REPO = "matteo-pacini/nixos-configs";
const HOSTS = ["BrightFalls", "Nexus", "NightSprings", "CauldronLake", "WorkLaptop"];
// comin polls every 60 s; refreshing faster shows nothing new.
const REFRESH_MS = 60000;
// Upstream moves in days; each check is ~15 API calls.
const WATCH_MS = 30 * 60000;
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const ORIGIN = /[:/]matteo-pacini\/nixos-configs(\.git)?$/;

// Where the focused terminal is, resolved the same way as the shipped `changes` mod.
function location() {
  const space = spaces().find((s) => s.active), f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  const on = f?.pane === null ? (f.terminal?.includes("/") ? f.terminal.split("/")[0] : null) : space?.machine ?? null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on };
}

// The checkout Watch reads: its tags come from the working tree, not from
// GitHub, so a stale checkout shows stale or no tags.
async function describeCheckout({ root, on }) {
  const git = async (...args) => {
    const r = await exec("git", ["-C", root, ...args], { on }).catch(() => null);
    return r?.code === 0 ? r.stdout.trim() : null;
  };
  const [branch, head, behind] = await Promise.all([
    git("rev-parse", "--abbrev-ref", "HEAD"),
    git("rev-parse", "HEAD"),
    git("rev-list", "--count", "HEAD..origin/master"),
  ]);
  return { machine: on, branch, head, behind: Number(behind) || 0 };
}

// Staged = the system comin last deployed (comin status), not the
// system-profiles/comin link, which only root can read. Only a `boot`
// deployment waits for a reboot; `switch` (Darwin) is live at once.
const PROBE = [
  "comin status --json",
  "echo '@@booted'; readlink -f /run/booted-system 2>/dev/null || true",
].join("; ");

const short = (sha) => (sha ? sha.slice(0, 7) : "—");

function ago(iso) {
  const ms = Date.now() - Date.parse(iso);
  if (!iso || !(ms >= 0)) return "";
  const m = Math.floor(ms / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return h < 48 ? `${h}h ago` : `${Math.floor(h / 24)}d ago`;
}

function parseProbe(stdout) {
  const [json, rest = ""] = stdout.split("@@booted");
  const booted = rest.trim();
  const s = JSON.parse(json);
  const dep = s.deployer?.deployment ?? {};
  const gen = s.builder?.generation ?? {};
  return {
    deployed: dep.generation?.selected_commit_id ?? "",
    depStatus: dep.status ?? "",
    depError: dep.error_msg ?? "",
    depAt: dep.ended_at ?? "",
    operation: dep.operation ?? "",
    building: gen.selected_commit_id ?? "",
    // comin skips deploying a commit whose system is unchanged.
    unchanged: gen.build_status === "built" && Boolean(gen.out_path) && gen.out_path === dep.generation?.out_path,
    buildError: gen.eval_err || gen.build_err || "",
    busy: Boolean(s.builder?.is_evaluating || s.builder?.is_building || s.deployer?.is_deploying),
    suspended: Boolean(s.is_suspended),
    rebootPending: Boolean(booted && dep.operation === "boot" && dep.status === "done" && dep.generation?.out_path && booted !== dep.generation.out_path),
  };
}

// The most urgent thing about a host, as [label, theme color name].
function verdict(h, deploySha) {
  if (h.offline) return ["offline", "dim"];
  if (h.depStatus === "failed") return ["deploy failed", "ansi1"];
  if (h.buildError && h.building === deploySha) return ["build failed", "ansi1"];
  if (h.suspended) return ["suspended", "blocked"];
  if (h.busy) return ["deploying", "working"];
  if (deploySha && h.deployed !== deploySha && !(h.building === deploySha && h.unchanged)) return ["behind", "blocked"];
  if (h.rebootPending) return ["reboot pending", "blocked"];
  return ["up to date", "ansi2"];
}

export default class Deploy extends View {
  init(_props, cx) {
    this.hosts = {};
    this.collapsed = JSON.parse(localStorage.getItem("collapsed") ?? "{}");
    this.follow(cx);
    // A hidden block is not rendered, so render() alone could never show it
    // again. follow() only runs git when the focused folder has changed.
    cx.timer.every(1000, (cx) => this.follow(cx));
    // Skipped while hidden: no SSH round-trips for a panel nobody sees.
    cx.timer.every(REFRESH_MS, (cx) => { if (this.shown) this.refresh(cx); });
    cx.timer.every(WATCH_MS, (cx) => { if (this.shown) this.loadWatch(cx); });
  }

  // Shows the block in a nixos-configs checkout and hides it elsewhere. Acts
  // only when the location changes, so a manual toggle sticks until then.
  follow(cx) {
    const loc = location(), where = JSON.stringify(loc);
    if (where === this.where) return;
    this.where = where;
    cx.spawn(async (cx) => {
      let ours = false, root = null;
      if (loc.cwd) {
        try {
          const r = await exec("git", ["-C", loc.cwd, "remote", "get-url", "origin"], { on: loc.on });
          ours = r.code === 0 && ORIGIN.test(r.stdout.trim());
          if (ours) root = (await exec("git", ["-C", loc.cwd, "rev-parse", "--show-toplevel"], { on: loc.on })).stdout.trim();
        } catch {}
      }
      if (this.where !== where) return;
      run(ours ? "layout.show" : "layout.hide", { id: "deploy" });
      // Refreshes when it appears, and when the focus moves to a checkout on
      // another machine; switching between spaces on one machine does not.
      const otherMachine = Boolean(this.repo) && loc.on !== this.repo.on;
      if (ours && (!this.shown || otherMachine)) this.refresh(cx);
      this.shown = ours;
      // Another checkout (a worktree, or the same repo on another machine)
      // can carry different tags.
      if (root && (root !== this.repo?.root || loc.on !== this.repo?.on)) {
        this.repo = { root, on: loc.on };
        this.loadWatch(cx);
      }
    });
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const local = (await exec("hostname", ["-s"])).stdout.trim().toLowerCase();
        this.local = local;
        await Promise.all([this.loadGitHub(), ...HOSTS.map((name) => this.loadHost(name, local))]);
        this.checked = new Date().toISOString();
      } finally {
        this.loading = false;
        cx.notify();
      }
    });
  }

  async loadGitHub() {
    try {
      const [refs, runs] = await Promise.all([
        exec("gh", ["api", `repos/${REPO}/git/matching-refs/heads/`]),
        exec("gh", ["run", "list", "-R", REPO, "-w", "build.yml", "-b", "master", "-L", "1",
          "--json", "status,conclusion,headSha,displayTitle,url,createdAt"]),
      ]);
      if (refs.code !== 0) throw new Error(refs.stderr.trim());
      const sha = (name) => JSON.parse(refs.stdout).find((r) => r.ref === `refs/heads/${name}`)?.object.sha ?? "";
      this.master = sha("master");
      this.deploySha = sha("deploy");
      this.run = runs.code === 0 ? JSON.parse(runs.stdout)[0] ?? null : null;
      this.ahead = 0;
      if (this.master && this.deploySha && this.master !== this.deploySha) {
        const cmp = await exec("gh", ["api", `repos/${REPO}/compare/${this.deploySha}...${this.master}`, "--jq", ".ahead_by"]);
        this.ahead = Number(cmp.stdout.trim()) || 0;
      }
      this.ghError = null;
    } catch (e) {
      this.ghError = String(e.message ?? e);
    }
  }

  async loadHost(name, local) {
    const alias = name.toLowerCase();
    try {
      const r = alias === local
        ? await exec("sh", ["-c", PROBE])
        : await exec("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", alias, PROBE]);
      if (r.code !== 0 && !r.stdout.includes("@@booted")) throw new Error(r.stderr.trim());
      this.hosts[name] = parseProbe(r.stdout);
    } catch (e) {
      this.hosts[name] = { offline: true, reason: String(e.message ?? e).split("\n").pop() };
    }
  }

  loadWatch(cx) {
    if (this.watchLoading || !this.repo) return;
    const repo = this.repo;
    this.watchLoading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const [tags, checkout] = await Promise.all([findTags(repo.root, repo.on), describeCheckout(repo)]);
        const results = await Promise.all(tags.map(checkTag));
        tags.forEach((tag, i) => Object.assign(tag, results[i]));
        tags.sort((a, b) => ORDER[a.state] - ORDER[b.state] || a.label.localeCompare(b.label));
        if (this.repo === repo) {
          this.tags = tags;
          this.checkout = checkout;
          this.watchError = null;
        }
      } catch (e) {
        if (this.repo === repo) this.watchError = String(e.message ?? e);
      } finally {
        this.watchLoading = false;
        // The focus moved to another checkout while this one loaded, and
        // that load was turned away above.
        if (this.repo !== repo) this.loadWatch(cx);
        cx.notify();
      }
    });
  }

  openUrl(url) {
    if (url) exec(window()?.platform === "macos" ? "open" : "xdg-open", [url]);
  }

  openRun() {
    this.openUrl(this.run?.url);
  }

  // A new tab in the current space, at the checkout's root: nvim on the tag's
  // line, with neo-tree open on the file. The repo's space is the one shown,
  // so a remote checkout opens on its own machine.
  openInEditor(tag) {
    if (!this.repo) return;
    run("tab.new", {
      name: tag.label,
      space: spaces().find((s) => s.active)?.id,
      folder: this.repo.root,
      argv: ["nvim", `+${tag.line}`, tag.file, "-c", "Neotree show reveal"],
    });
  }

  toggle(section, cx) {
    this.collapsed[section] = !this.collapsed[section];
    localStorage.setItem("collapsed", JSON.stringify(this.collapsed));
    cx.notify();
  }

  // Whether the checkout is behind master: by its own origin/master, which is
  // only as fresh as its last fetch, or, on master, by GitHub's master.
  checkoutBehind() {
    const c = this.checkout;
    if (!c) return null;
    if (c.behind > 0) return `${c.behind} behind origin/master`;
    if (c.branch === "master" && this.master && c.head && c.head !== this.master) return "behind GitHub master";
    return null;
  }

  // ---- Drawing: two cards, Deploy above Watch, in the agent tree's idiom ----

  // A status pill tinted with a theme colour (by name).
  chip(text, color, t) {
    const c = t[color] ?? t.dim;
    return div().flex_none().h(18).px(7).rounded(5).bg(c + "26").text_color(c)
      .text_size(10.5).font_semibold().flex().items_center().child(text);
  }

  marker(color, hollow, t) {
    const c = t[color] ?? t.dim;
    return div().size(8).flex_none().rounded(4).when(hollow, (el) => el.border(1.5).border_color(c)).when(!hollow, (el) => el.bg(c));
  }

  // One row of a card: marker, name over a dim detail line, a chip.
  item(id, marker, name, sub, right, t) {
    return h_flex().id(id).gap(9).px(8).py(7).rounded(8).items_center().hover((s) => s.bg(t.hover))
      .child(marker)
      .child(v_flex().flex_1().min_w(0).gap(1)
        .child(name)
        .when(Boolean(sub), (el) => el.child(div().text_size(11).text_color(t.dim).truncate().child(sub))))
      .child(right);
  }

  card(t, grow) {
    return v_flex().bg(t.background).border_1().border_color(t.border).rounded(10).overflow_hidden()
      .when(grow, (el) => el.flex_1().min_h(0)).when(!grow, (el) => el.flex_none());
  }

  // The card's header bar; the chevron, icon and title collapse the card.
  cardHeader(section, label, icon, tint, right, t) {
    const c = t[tint] ?? t.accent;
    return h_flex().h(46).flex_none().pl(12).pr(10).gap(9).items_center().bg(t.raised)
      .child(h_flex().id(`toggle-${section}`).gap(9).items_center().cursor_pointer()
        .on_click((_e, cx) => this.toggle(section, cx))
        .child(svg(`mods/workspace-chrome/chevron-${this.collapsed[section] ? "right" : "down"}.svg`).size(11).flex_none().text_color(t.dim))
        .child(div().size(22).flex_none().rounded(6).bg(c + "26").flex().items_center().justify_center()
          .child(svg(`mods/workspace-chrome/${icon}.svg`).size(13).text_color(c)))
        .child(div().text_size(15).font_semibold().child(label)))
      .child(div().flex_1())
      .child(right);
  }

  // Header chips: whatever needs attention, else one "up to date".
  deployChips(t) {
    if (this.loading && !this.checked) return [div().text_size(11).text_color(t.dim).child("checking…")];
    const counts = {};
    for (const name of HOSTS) {
      const h = this.hosts[name];
      if (!h) continue;
      const [label, color] = verdict(h, this.deploySha);
      if (label === "up to date") continue;
      counts[label] ??= { n: 0, color };
      counts[label].n++;
    }
    const chips = Object.entries(counts).map(([label, { n, color }]) =>
      this.chip(`${n} ${label === "reboot pending" ? "reboot" : label}`, color, t));
    if (this.run?.status === "completed" && this.run.conclusion !== "success") chips.unshift(this.chip("build failed", "ansi1", t));
    return chips.length ? chips : [this.chip("up to date", "ansi2", t)];
  }

  steps(t) {
    const run = this.run;
    const ci = !run ? ["no run", "dim"]
      : run.status !== "completed" ? ["building", "working"]
      : run.conclusion === "success" ? ["passed", "ansi2"]
      : [run.conclusion || "failed", "ansi1"];
    const mono = settings().font_family ?? "JetBrains Mono";
    const sha = (s, color) => div().font_family(mono).text_size(11.5).text_color(color ?? t.foreground).child(short(s));
    const step = (id, label, value, onClick) => v_flex().id(id).flex_1().min_w(0).gap(4).px(8).py(7).rounded(8).bg(t.hover)
      .when(Boolean(onClick), (el) => el.cursor_pointer().hover((s) => s.bg(t.selected)).on_click(onClick))
      .child(div().text_size(10).text_color(t.dim).truncate().child(label))
      .child(value);
    return h_flex().gap(6).px(12).pt(12).pb(6)
      .child(step("step-master", "MASTER", sha(this.master)))
      .child(step("step-ci", "BUILD.YML", h_flex().child(this.chip(ci[0], ci[1], t)), () => this.openRun()))
      .child(step("step-deploy", this.ahead ? `DEPLOY · ${this.ahead} BEHIND` : "DEPLOY", sha(this.deploySha, this.ahead ? t.blocked : null)));
  }

  hostItem(name, t) {
    const h = this.hosts[name];
    const [label, color] = verdict(h, this.deploySha);
    const detail = h.depStatus === "failed" ? h.depError
      : h.buildError && h.building === this.deploySha ? h.buildError
      : `${short(h.deployed)} · ${h.operation || "—"} · ${ago(h.depAt)}`;
    const title = h_flex().gap(6).items_center().min_w(0)
      .child(div().font_medium().truncate().child(name))
      .when(name.toLowerCase() === this.local, (el) => el.child(div().flex_none().px(5).h(16).rounded(4).border(1).border_color(t.dim)
        .flex().items_center().text_size(10).text_color(t.muted).child("this machine")));
    const right = h_flex().gap(6).items_center()
      .when(h.busy, (el) => el.child(div().text_color(t.working).frames(SPINNER, 90)))
      .child(this.chip(label === "reboot pending" ? "reboot" : label, color, t));
    return this.item(`host-${name}`, this.marker(color, false, t), title, detail, right, t);
  }

  deployCard(t) {
    const open = !this.collapsed.deploy;
    const known = HOSTS.filter((name) => this.hosts[name]);
    const online = known.filter((name) => !this.hosts[name].offline);
    const offline = known.filter((name) => this.hosts[name].offline);
    const header = h_flex().gap(5).items_center()
      .children(this.deployChips(t))
      .child(div().id("refresh").ml(4).px(6).py(2).rounded(6).cursor_pointer().text_size(11).text_color(t.muted)
        .hover((s) => s.bg(t.hover)).on_click((_e, cx) => { this.refresh(cx); this.loadWatch(cx); })
        .child(this.loading ? "…" : "Refresh"));
    return this.card(t, false)
      .child(this.cardHeader("deploy", "Deploy", "server", "accent", header, t))
      .when(Boolean(this.ghError), (el) => el.child(div().px(14).pt(8).text_size(11).text_color(t.ansi1).child(`GitHub: ${this.ghError}`)))
      .when(open, (el) => el
        .child(this.steps(t))
        .child(v_flex().p(6).gap(2)
          .children(online.map((name) => this.hostItem(name, t)))
          .when(offline.length > 0, (el) => el.child(this.item("host-offline", this.marker("dim", true, t),
            div().font_medium().text_color(t.muted).truncate().child(offline.join(" · ")), null, this.chip("offline", "dim", t), t)))
          .when(!known.length, (el) => el.child(div().px(8).py(7).text_size(12).text_color(t.dim).child("Checking hosts…")))));
  }

  // A Watch row's chip, its colour, and what the detail line adds beyond the
  // chip (null when the chip already says it all).
  static tagChip(tag) {
    const ready = tag.state === "ready", text = tag.text ?? "";
    if (tag.state === "unknown") return ["check by hand", "ansi3", text.replace(/^not checked: /, "")];
    if (tag.kind === "watch") return [tag.state, tag.state === "closed" ? "ansi3" : "dim", null];
    if (tag.kind === "manual") return ["manual", "dim", /· (.+)$/.test(text) ? `checked ${/· (.+)$/.exec(text)[1]}` : null];
    switch (tag.kind) {
      case "unstable":
        if (ready) return ["in unstable", "ansi2", null];
        return /not merged|unmerged/.test(text) ? ["not merged", "dim", null] : ["not in unstable", "dim", "PR merged"];
      case "merged": return ready ? ["merged", "ansi2", null] : ["not merged", "dim", null];
      case "closed": return ready ? ["closed", "ansi2", /not planned/.test(text) ? "not planned" : null] : ["open", "dim", null];
      case "green": return ready ? ["green", "ansi2", text] : ["Hydra red", "dim", text];
      case "version": return ready ? ["available", "ansi2", text] : [text, "dim", null];
    }
    return [text, "dim", null];
  }

  watchItem(tag, i, t) {
    const [chipText, chipColor, detail] = Deploy.tagChip(tag);
    const watch = tag.kind === "watch";
    const dot = { ready: "ansi2", unknown: "ansi3", closed: "ansi3" }[tag.state] ?? "dim";
    const ref = tag.kind === "version" ? "nixos-unstable" : shortRef(tag);
    const sub = [ref, detail].filter(Boolean).join(" · ");
    return this.item(`watch-${i}`, this.marker(dot, watch, t),
      div().font_medium().truncate().text_color(watch ? t.muted : t.foreground).child(tag.label), sub, this.chip(chipText, chipColor, t), t)
      .cursor_pointer()
      .when(Boolean(tag.url), (el) => el.on_click(() => this.openUrl(tag.url)))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openInEditor(tag); });
  }

  watchCard(t) {
    const open = !this.collapsed.watch;
    const tags = this.tags ?? [];
    const count = (state) => tags.filter((tag) => tag.state === state).length;
    const header = h_flex().gap(5).items_center()
      .when(this.watchLoading, (el) => el.child(div().text_size(11).text_color(t.dim).child("checking…")))
      .when(!this.watchLoading && Boolean(this.tags), (el) => el
        .when(count("ready") > 0, (el) => el.child(this.chip(`${count("ready")} ready`, "ansi2", t)))
        .child(this.chip(`${count("waiting")} waiting`, "dim", t)));
    const groups = [
      ["READY", (tag) => tag.state === "ready"],
      ["NOT CHECKED", (tag) => tag.state === "unknown"],
      ["WAITING", (tag) => tag.state === "waiting"],
      ["MANUAL", (tag) => tag.state === "manual"],
      ["WATCHING", (tag) => tag.kind === "watch"],
    ];
    const rows = [];
    for (const [label, test] of groups) {
      const members = tags.filter(test);
      if (!members.length) continue;
      rows.push(div().px(8).pt(10).pb(4).text_size(10).text_color(t.dim).child(label));
      for (const tag of members) rows.push(this.watchItem(tag, tags.indexOf(tag), t));
    }
    const behind = this.checkoutBehind();
    const c = this.checkout;
    return this.card(t, open)
      .child(this.cardHeader("watch", "Watch", "clock", "ansi2", header, t))
      .when(open && Boolean(c), (el) => el.child(h_flex().flex_none().px(14).pt(8).gap(4).text_size(11).text_color(t.dim).min_w(0)
        .child(div().truncate().child(`${c.machine ?? this.local ?? "this machine"} · ${c.branch ?? "?"} @ ${c.head?.slice(0, 7) ?? "?"}`))
        .when(Boolean(behind), (el) => el.child(div().flex_none().text_color(t.blocked).child(`· ${behind}`)))))
      .when(open, (el) => el.child(div().flex_none().px(14).pt(2).text_size(11).text_color(t.dim).child("Click opens upstream · right-click edits in nvim")))
      .when(open && Boolean(this.watchError), (el) => el.child(div().px(14).pt(6).text_size(11).text_color(t.ansi1).child(this.watchError)))
      .when(open && Boolean(this.tags) && !tags.length && !this.watchLoading, (el) => el.child(
        div().px(14).py(10).text_size(12).text_color(t.muted).child(behind
          ? "No WAIT-FOR / WATCH tags in this checkout. Pull master to see them."
          : "No WAIT-FOR / WATCH tags in this checkout.")))
      .when(open, (el) => el.child(v_flex().id("watch-list").flex_1().min_h(0).overflow_y_scrollbar().px(6).pb(6).gap(2).children(rows)));
  }

  render(cx) {
    this.follow(cx);
    const t = theme();
    return v_flex().size_full().min_h(0).gap(8).text_color(t.foreground).text_size(13)
      .child(this.deployCard(t))
      .child(this.watchCard(t));
  }
}
