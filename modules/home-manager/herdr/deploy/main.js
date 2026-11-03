// Deploy pipeline for matteo-pacini/nixos-configs: master → build.yml → the
// deploy branch → each host's comin; below it, the checkout's upstream tags
// (watch.js) and whether each is ready to act on. The `deploy` block of the
// agent-tree layout, shown only while the focused terminal is in a checkout
// of that repo (any machine). A manual `layout.toggle deploy` sticks until
// the focus moves to another folder.
// Hosts are read over plain SSH using the aliases in ~/.ssh/config; the
// machine this runs on is read locally.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, theme, window, run, spaces, panes, focused } from "herdr";
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
      if (ours && !this.shown) this.refresh(cx);
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
        const tags = await findTags(repo.root, repo.on);
        const results = await Promise.all(tags.map(checkTag));
        tags.forEach((tag, i) => Object.assign(tag, results[i]));
        tags.sort((a, b) => ORDER[a.state] - ORDER[b.state] || a.label.localeCompare(b.label));
        if (this.repo === repo) {
          this.tags = tags;
          this.watchError = null;
        }
      } catch (e) {
        this.watchError = String(e.message ?? e);
      } finally {
        this.watchLoading = false;
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

  pipeline(t) {
    const run = this.run;
    const ci = !run ? ["no run", "dim"]
      : run.status !== "completed" ? ["building", "working"]
      : run.conclusion === "success" ? ["passed", "ansi2"]
      : [run.conclusion || "failed", "ansi1"];
    const node = (label, value, color) => v_flex().gap(2)
      .child(div().text_size(10).text_color(t.dim).child(label))
      .child(div().text_color(t[color] ?? t.foreground).child(value));
    const arrow = () => div().text_color(t.dim).child("→");
    return h_flex().px(14).py(10).gap(12).items_center().border_b(1).border_color(t.border)
      .child(node("master", short(this.master), "foreground"))
      .child(arrow())
      .child(div().id("ci").cursor_pointer().rounded(6).px(4).hover((s) => s.bg(t.hover))
        .on_click(() => this.openRun())
        .child(node(`build.yml${run ? ` · ${short(run.headSha)}` : ""}`, ci[0], ci[1])))
      .child(arrow())
      .child(node(this.ahead ? `deploy · ${this.ahead} behind` : "deploy", short(this.deploySha), this.ahead ? "blocked" : "foreground"));
  }

  hostRow(name, t) {
    const h = this.hosts[name];
    if (!h) return h_flex().px(14).h(40).items_center().text_color(t.dim).child(name);
    const [label, color] = verdict(h, this.deploySha);
    const detail = h.offline ? h.reason
      : h.depStatus === "failed" ? h.depError
      : h.buildError && h.building === this.deploySha ? h.buildError
      : `${short(h.deployed)} · ${h.operation || "—"} · ${ago(h.depAt)}`;
    return v_flex().px(14).py(7).gap(2).border_b(1).border_color(t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).rounded(4).bg(t[color]))
        .child(h_flex().flex_1().gap(6).items_baseline()
          .child(div().font_semibold().child(name))
          .when(name.toLowerCase() === this.local, (el) => el.child(div().text_size(11).text_color(t.dim).child("this machine"))))
        .child(div().text_size(12).text_color(t[color]).child(label))
        .when(h.busy, (el) => el.child(div().text_color(t.working).frames(SPINNER, 90))))
      .child(div().pl(16).text_size(11).text_color(t.dim).truncate().child(detail ?? ""));
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

  watchRow(tag, i, t) {
    const color = { ready: "ansi2", unknown: "ansi3", closed: "ansi3" }[tag.state];
    const watch = tag.kind === "watch";
    return v_flex().id(`watch-${i}`).px(14).py(6).gap(2).border_b(1).border_color(t.border)
      .cursor_pointer().hover((s) => s.bg(t.hover))
      .when(Boolean(tag.url), (el) => el.on_click(() => this.openUrl(tag.url)))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openInEditor(tag); })
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).rounded(4).when(watch, (el) => el.border_1().border_color(t[color] ?? t.dim)).when(!watch, (el) => el.bg(t[color] ?? t.dim)))
        .child(div().flex_1().min_w(0).truncate().font_semibold().text_color(watch ? t.muted : t.foreground).child(tag.label))
        .child(div().flex_none().text_size(12).text_color(t[color] ?? t.muted).child(tag.text ?? "")))
      .child(div().pl(16).text_size(11).text_color(t.dim).truncate()
        .child(`${shortRef(tag)} · ${tag.kind} · ${tag.file}:${tag.line}`));
  }

  toggle(section, cx) {
    this.collapsed[section] = !this.collapsed[section];
    localStorage.setItem("collapsed", JSON.stringify(this.collapsed));
    cx.notify();
  }

  // A section title that collapses its section when clicked.
  title(section, label, t) {
    return h_flex().id(`toggle-${section}`).gap(6).items_center().cursor_pointer()
      .on_click((_e, cx) => this.toggle(section, cx))
      .child(div().w(12).text_size(12).text_color(t.dim).child(this.collapsed[section] ? "▸" : "▾"))
      .child(div().text_size(15).font_semibold().child(label));
  }

  // What a collapsed Deploy section still says: anything that isn't fine.
  deploySummary() {
    const counts = {};
    for (const name of HOSTS) {
      const h = this.hosts[name];
      const label = h ? verdict(h, this.deploySha)[0] : null;
      if (label && label !== "up to date") counts[label] = (counts[label] ?? 0) + 1;
    }
    const parts = Object.entries(counts).map(([label, n]) => `${n} ${label}`);
    if (this.run?.status === "completed" && this.run.conclusion !== "success") parts.unshift("build.yml failed");
    return parts.length ? parts.join(" · ") : "all up to date";
  }

  watchSection(t) {
    const tags = this.tags ?? [];
    const count = (state) => tags.filter((tag) => tag.state === state).length;
    const summary = this.watchLoading ? "checking…"
      : this.tags ? `${count("ready")} ready · ${count("waiting")} waiting` : "";
    const open = !this.collapsed.watch;
    return v_flex().when(open, (el) => el.flex_1().min_h(0))
      .child(h_flex().h(44).flex_none().px(14).gap(6).items_center().border_b(1).border_color(t.border)
        .child(this.title("watch", "Watch", t))
        .child(div().flex_1())
        .child(div().text_size(11).text_color(t.dim).child(summary)))
      .when(open && Boolean(this.watchError), (el) => el.child(div().px(14).py(6).text_size(11).text_color(t.ansi1).child(this.watchError)))
      .when(open, (el) => el.child(div().flex_none().px(14).py(5).border_b(1).border_color(t.border).text_size(11).text_color(t.dim)
        .child("Click: open upstream · Right-click: edit in nvim")))
      .when(open, (el) => el.child(v_flex().id("watch-list").flex_1().min_h(0).overflow_y_scrollbar()
        .children(tags.map((tag, i) => this.watchRow(tag, i, t)))));
  }

  render(cx) {
    this.follow(cx);
    const t = theme();
    const button = (id, label, onClick) => div().id(id).px(8).py(2).rounded(6).cursor_pointer()
      .text_size(11).text_color(t.muted).hover((s) => s.bg(t.hover))
      .on_click(onClick).child(label);
    return v_flex().size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(44).flex_none().px(14).gap(6).items_center().border_b(1).border_color(t.border)
        .child(this.title("deploy", "Deploy", t))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim)
          .child(this.loading ? "checking…"
            : this.collapsed.deploy ? this.deploySummary()
            : this.checked ? `checked ${ago(this.checked)}` : ""))
        .child(button("refresh", "Refresh", (_e, cx) => { this.refresh(cx); this.loadWatch(cx); })))
      .when(Boolean(this.ghError), (el) => el.child(div().px(14).py(6).text_size(11).text_color(t.ansi1).child(`GitHub: ${this.ghError}`)))
      .when(!this.collapsed.deploy, (el) => el
        .child(this.pipeline(t))
        .child(v_flex().flex_none().children(HOSTS.map((name) => this.hostRow(name, t)))))
      .child(this.watchSection(t));
  }
}
