// Deploy pipeline for matteo-pacini/nixos-configs: master → build.yml → the
// deploy branch → each host's comin; below it, the checkout's upstream tags
// (watch.js) and whether each is ready to act on. The `fleet` block of the
// workbench layout, shown only while the focused terminal is in a checkout
// of that repo (any machine). A manual `layout.toggle fleet` sticks until
// the focus moves to another folder.
// Hosts are read over plain SSH using the aliases in ~/.ssh/config; the
// machine this runs on is read locally.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, Textarea, TextareaState } from "gpui-base";
import { exec, hc, theme, run, spaces, focused, settings, openOverlay, closeOverlay, props, shared, setShared } from "herdr";
import { location, openUrl } from "./lib/ui.js";
import { SELF, FLEET, HOSTS as MESH } from "./lib/hosts.js";
import { findTags, checkTag, shortRef, ORDER } from "./watch.js";
import { claudeAction, fixAll } from "./prompts.js";

const REPO = "matteo-pacini/nixos-configs";
// The hosts this machine can reach over the SSH mesh, itself first.
const HOSTS = FLEET;
// nix-darwin has no boot: these hosts only switch.
const DARWIN = new Set(Object.values(MESH).filter((h) => h.darwin).map((h) => h.label));
// comin-deploy modes (modules/shared/comin-deploy.nix), as the host menu names them.
const MODES = { manual: "Manual", boot: "Automatic (boot)", switch: "Automatic (switch)" };
// comin polls every 60 s; refreshing faster shows nothing new.
const REFRESH_MS = 60000;
// Upstream moves in days; each check is ~15 API calls.
const WATCH_MS = 30 * 60000;
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const ORIGIN = /[:/]matteo-pacini\/nixos-configs(\.git)?$/;

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
// The mode is empty on a host without custom.autoDeploy.confirm (no comin-deploy).
const PROBE = [
  "comin status --json",
  "echo '@@booted'; readlink -f /run/booted-system 2>/dev/null || true",
  "echo '@@current'; readlink -f /run/current-system 2>/dev/null || true",
  "echo '@@mode'; comin-deploy mode 2>/dev/null || true",
].join("; ");

// argv running `cmd` on the host: through sh here, through ssh elsewhere.
// `tty` keeps a terminal for a tab.
function onHost(p, cmd, tty) {
  return p.local ? ["sh", "-c", cmd] : ["ssh", ...(tty ? ["-t"] : ["-o", "BatchMode=yes"]), p.alias, cmd];
}

// A tab named `name` running `cmd` on the host, left open until Enter so the
// outcome can be read.
const hostTab = (p, name, cmd) =>
  run("tab.new", { name, argv: onHost(p, `${cmd}; printf '\\nPress Enter to close. '; read _`, true) });

// Asks the panel, another view, to probe `host` again. `extra`: { mode } shows
// a mode the menu is writing at once; { watch: true } follows a deploy until
// it settles.
const askRefresh = (host, extra = {}) => setShared("fleet.refresh", { host, at: Date.now(), ...extra });

// A host row's right-click menu; `p` is the popup's props (see Deploy.hostTarget).
// Deploy actions go through comin-deploy (a mode means it is installed) and
// wait while comin is busy or suspended.
function hostMenuItems(p) {
  const items = [];
  const free = Boolean(p.mode) && !p.busy && !p.suspended;
  if (free && p.pending) {
    items.push({ label: "Switch now", icon: "terminal", id: "switch" });
    if (!p.darwin) items.push({ label: "Schedule for next boot", icon: "clock", id: "boot" });
  } else if (free && (p.rebootPending || p.failed)) {
    items.push({ label: "Switch now", icon: "terminal", id: "switch" });
  }
  if (p.diffTo) items.push({ label: "Check diff", icon: "git-compare", id: "diff" });
  // Not while comin is busy: a reboot would cut a build or activation short.
  if (!p.darwin && !p.busy) items.push({ label: "Reboot", icon: "monitor", id: "reboot" });
  // Modes need comin-deploy, which reports one.
  if (p.mode) for (const [mode, label] of Object.entries(MODES)) {
    if (p.darwin && mode === "boot") continue;
    items.push({ label, icon: mode === p.mode ? "check" : "square", id: `mode-${mode}` });
  }
  return items;
}

// A Watch row's right-click menu; `p` is the popup's props ({ tag, root, space }).
function menuItems(p) {
  if (p.host) return hostMenuItems(p);
  const claude = claudeAction(p.tag);
  return [
    { label: "Open in nvim", icon: "file-text", id: "nvim" },
    ...(claude ? [{ label: claude.label, icon: "terminal", id: "claude" }] : []),
    ...(p.tag.url ? [{ label: "Open upstream", icon: "search", id: "upstream" }] : []),
  ];
}

// The review dialog for a Claude Code prompt. `review`: { root, space, title,
// text, name (the new tab's), about (a dim line under the title) }.
function openReviewDialog(review) {
  openOverlay({ mod: "fleet", kind: "dialog", modal: true, width: 640, height: 520, props: { review } });
}

// The review dialog for `p.tag`'s Claude Code prompt; `p` is { tag, root, space }.
function openReview(p) {
  const a = claudeAction(p.tag);
  openReviewDialog({ root: p.root, space: p.space, title: a.label, text: a.text, name: p.tag.label,
    about: `${p.tag.label} · ${p.tag.sites.map((s) => `${s.file}:${s.line}`).join(", ")}` });
}

// A new tab in `space`, at the checkout's root, running `argv`.
const openTab = (name, root, space, argv) => run("tab.new", { name, space, folder: root, argv });

const short = (sha) => (sha ? sha.slice(0, 7) : "—");
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

// The Spaces badge fills; a tag's label picks one, so it keeps its colour
// across refreshes.
const BADGES = ["#22a99a", "#e3814f", "#5b8def", "#8b7cf6", "#3fae6a", "#d9649a"];
const badgeColor = (label) => BADGES[[...label].reduce((n, ch) => n + ch.codePointAt(0), 0) % BADGES.length];

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
  const [bootedOut, afterBooted = ""] = rest.split("@@current");
  const [currentOut, modeOut = ""] = afterBooted.split("@@mode");
  const booted = bootedOut.trim(), current = currentOut.trim();
  const s = JSON.parse(json);
  const dep = s.deployer?.deployment ?? {};
  const gen = s.builder?.generation ?? {};
  // The held generation, from the store: the builder may have moved on to a
  // newer commit since.
  const held = (s.store?.generations ?? []).find((g) => g.uuid && g.uuid === s.deploy_confirmer?.submitted);
  // What boots next: the last successful deployment.
  const done = (s.store?.deployments ?? []).filter((d) => d.status === "done")
    .sort((a, b) => String(b.ended_at).localeCompare(String(a.ended_at)))[0];
  const staged = done?.generation?.out_path ?? "";
  // comin holds systems equal to the staged one too; comin-deploy auto
  // releases those within a minute, so they are not shown as pending.
  const noop = Boolean(held?.out_path) && held.out_path === staged;
  const pendingOut = held && !noop ? held.out_path ?? "" : "";
  // The newest system comin has for this host: held, built, or staged.
  const newest = pendingOut || (gen.build_status === "built" ? gen.out_path : "") || staged || "";
  return {
    deployed: dep.generation?.selected_commit_id ?? "",
    depStatus: dep.status ?? "",
    // A failed deployment of a system that is not running: Switch now retries
    // it (comin-deploy redeploys a failed latest deployment).
    failed: dep.status === "failed" && Boolean(dep.generation?.out_path) && dep.generation.out_path !== current,
    depError: dep.error_msg ?? "",
    depAt: dep.ended_at ?? "",
    operation: dep.operation ?? "",
    building: gen.selected_commit_id ?? "",
    // comin skips deploying a commit whose system is unchanged.
    unchanged: gen.build_status === "built" && Boolean(gen.out_path) && gen.out_path === dep.generation?.out_path,
    buildError: gen.eval_err || gen.build_err || "",
    building_: Boolean(s.builder?.is_evaluating || s.builder?.is_building),
    deploying: Boolean(s.deployer?.is_deploying || s.deployer?.generation_to_deploy),
    busy: Boolean(s.builder?.is_evaluating || s.builder?.is_building || s.deployer?.is_deploying || s.deployer?.generation_to_deploy),
    suspended: Boolean(s.is_suspended || s.deployer?.is_suspended),
    // A generation comin built and holds for confirmation (custom.autoDeploy.confirm).
    pending: held && !noop ? held.uuid : "",
    pendingOut,
    pendingCommit: held?.selected_commit_id ?? "",
    stagedCommit: done?.generation?.selected_commit_id ?? "",
    // What Check diff compares the running system with, when they differ.
    diffTo: current && newest && newest !== current ? newest : "",
    mode: modeOut.trim(),
    // A boot deployment not yet running. Darwin has no booted-system to
    // compare with in comin's sense: its operation is always switch.
    rebootPending: Boolean(booted && dep.operation === "boot" && dep.status === "done" && dep.generation?.out_path
      && booted !== dep.generation.out_path && current !== dep.generation.out_path),
    // Switched live, but the kernel changed: comin's own check.
    kernelReboot: Boolean(s.need_to_reboot) && dep.operation !== "boot",
  };
}

// The most urgent thing about a host, as [label, theme color name].
function verdict(h, deploySha) {
  if (h.offline) return ["offline", "dim"];
  if (h.depStatus === "failed") return ["deploy failed", "ansi1"];
  if (h.buildError && h.building === deploySha) return ["build failed", "ansi1"];
  if (h.suspended) return ["suspended", "blocked"];
  if (h.deploying) return ["deploying", "working"];
  if (h.building_) return ["building", "working"];
  if (h.pending) return ["pending", "ansi4"];
  if (deploySha && h.deployed !== deploySha && !(h.building === deploySha && h.unchanged)) return ["behind", "blocked"];
  if (h.rebootPending) return ["reboot pending", "blocked"];
  if (h.kernelReboot) return ["reboot (kernel)", "blocked"];
  return ["up to date", "ansi2"];
}

export default class Deploy extends View {
  init(_props, cx) {
    if (props()?.menu) return this.initMenu(cx);
    if (props()?.review) return this.initReview();
    if (props()?.confirmSwitch || props()?.confirmReboot) return;
    if (props()?.diffView) return this.initDiff(cx);
    this.hosts = {};
    // Hosts whose deploy, started from the menu, is being followed.
    this.deploying = new Set();
    // Requests from menus and dialogs, answered by the 1 s timer.
    this.asks = [];
    // Shared values persist (shared.json): the last request, however old,
    // would otherwise be answered again each time the panel starts.
    this.refreshAsked = shared("fleet.refresh")?.at;
    this.collapsed = JSON.parse(localStorage.getItem("collapsed") ?? "{}");
    this.follow(cx);
    // A hidden block is not rendered, so render() alone could never show it
    // again. follow() only runs git when the focused folder has changed.
    cx.timer.every(1000, (cx) => { this.follow(cx); this.answerAsks(cx); });
    // Skipped while hidden: no SSH round-trips for a panel nobody sees.
    cx.timer.every(REFRESH_MS, (cx) => { if (this.shown) this.refresh(cx); });
    cx.timer.every(WATCH_MS, (cx) => { if (this.shown) this.loadWatch(cx); });
  }

  // Shows the block in a nixos-configs checkout and hides it elsewhere. Acts
  // only when the location changes, so a manual toggle sticks until then.
  follow(cx) {
    // Not keyed on the space: a manual toggle sticks across spaces in one folder.
    const { cwd, on } = location(), loc = { cwd, on }, where = JSON.stringify(loc);
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
      run(ours ? "layout.show" : "layout.hide", { id: "fleet" });
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

  // A menu or dialog asked for a host to be probed again (askRefresh).
  // A menu or dialog asked for something (askRefresh). Render only takes the
  // request: work spawned from render never runs, so the 1 s timer does it.
  takeAsk() {
    const ask = shared("fleet.refresh");
    if (!ask || ask.at === this.refreshAsked) return;
    this.refreshAsked = ask.at;
    // Shown at once; the probe corrects it if the write failed.
    if (ask.mode && this.hosts[ask.host]) this.hosts[ask.host].mode = ask.mode;
    this.asks.push(ask);
  }

  answerAsks(cx) {
    if (!this.local) return;
    for (const ask of this.asks.splice(0)) {
      cx.spawn(async (cx) => {
        if (ask.watch) return this.followDeploy(ask.host, cx);
        if (ask.reboot) return this.reboot(ask.host);
        // Give the mode write, which the menu runs, a moment.
        if (ask.mode) await exec("sleep", ["2"]);
        await this.loadHost(ask.host, this.local);
        cx.notify();
      });
    }
  }

  // The Check diff dialog runs dix itself, so it shows progress while open.
  initDiff(cx) {
    const p = props().diffView;
    this.diff = null;
    cx.spawn(async (cx) => {
      const [cmd, ...args] = onHost(p, `nix run nixpkgs#dix -- --color=never diff /run/current-system ${p.diffTo}`);
      const r = await exec(cmd, args).catch((e) => ({ code: 1, stdout: "", stderr: String(e.message ?? e) }));
      this.diff = r.code === 0 ? { text: r.stdout.trim() } : { error: (r.stderr || r.stdout).trim().split("\n").slice(-6).join("\n") };
      cx.notify();
    });
  }

  diffDialog(t) {
    const o = props(), p = o.diffView, d = this.diff;
    const mono = settings().font_family ?? "JetBrains Mono";
    const close = () => closeOverlay(o.overlay);
    const body = !d
      ? h_flex().flex_1().gap(8).items_center().justify_center().text_color(t.muted)
        .child(svg("mods/workspace-chrome/spinner.svg").size(14).text_color(t.working).spin(900))
        .child(`Running dix on ${p.host}… the first run fetches it.`)
      : v_flex().id("diff-out").flex_1().min_h(0).p(10).rounded(9).border_1().border_color(t.border).bg(t.background)
        .overflow_y_scrollbar().font_family(mono).text_size(11.5)
        .text_color(d.error ? t.ansi1 : t.foreground)
        .children((d.error ?? (d.text || "No differences.")).split("\n").map((line) => div().flex_none().whitespace_nowrap().child(line || " ")));
    return v_flex().size_full().min_h(0).p(18).gap(10).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { close(); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child(`${p.host}: running system → ${short(p.commit)}`))
      .child(div().mt(-6).text_size(11.5).text_color(t.dim).truncate().child(p.diffTo))
      .child(body)
      .child(h_flex().justify_end()
        .child(h_flex().id("diff-close").h(32).px(14).items_center().rounded(8).border_1().border_color(t.input).bg(t.raised)
          .text_size(12.5).font_medium().cursor_pointer().hover((s) => s.opacity(0.88)).on_click(close).child("Close")));
  }

  // Probes a host every 5 s while a deploy started from its menu runs, until
  // comin is idle with nothing held (at most 30 minutes). comin takes a few
  // seconds to pick the confirmation up, hence the first three probes.
  async followDeploy(host, cx) {
    this.deploying.add(host);
    let idle = 0;
    try {
      for (let i = 0; i < 360; i++) {
        await this.loadHost(host, this.local);
        cx.notify();
        const h = this.hosts[host];
        // Idle for 20 s: a Switch now on a boot host has a few idle seconds
        // between its boot and its switch.
        idle = !h.offline && !h.busy && !h.pending ? idle + 1 : 0;
        if (h.offline || (i >= 3 && idle >= 4)) break;
        await exec("sleep", ["5"]);
      }
    } finally {
      this.deploying.delete(host);
      cx.notify();
    }
  }

  // Reboots without asking when sudo needs no password. Otherwise the reboot
  // runs in a terminal peeked over the tab, where the password is typed; it
  // waits for Enter only if sudo fails, since a reboot ends the session.
  async reboot(host) {
    const p = this.hostTarget(host);
    const [cmd, ...args] = onHost(p, "sudo -n systemctl reboot");
    const r = await exec(cmd, args).catch((e) => ({ code: 1, stderr: String(e.message ?? e) }));
    if (r.code === 0 || !/password is required/.test(r.stderr)) return;
    const argv = onHost(p, "sudo systemctl reboot || { printf '\\nPress Enter to close. '; read _; }", true);
    const t = await hc(["run", "--bg", "--json", "--no-parent", "--rm", "--name", `reboot-${p.alias}`, ...argv]);
    if (t.code === 0) run("terminal.peek", { terminal: JSON.parse(t.stdout).address });
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const local = SELF;
        this.local = local;
        // Each probe repaints as it lands: an offline host holds its SSH
        // ConnectTimeout, and the rest shouldn't wait for it.
        const draw = () => cx.notify();
        await Promise.all([this.loadGitHub().then(draw), ...HOSTS.map((name) => this.loadHost(name, local).then(draw))]);
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

  openRun() {
    openUrl(this.run?.url);
  }

  // Right-click on a Watch row: a popup at the pointer, drawn like agent-list's.
  // The repo's space is the one shown, so a remote checkout's tabs open on its
  // own machine.
  target(tag) {
    return { tag, root: this.repo.root, space: spaces().find((s) => s.active)?.id };
  }

  openMenu(tag) {
    if (!this.repo) return;
    const p = this.target(tag);
    openOverlay({ mod: "fleet", kind: "popup", width: 220, height: menuItems(p).length * 31 + 10, props: { menu: p } });
  }

  initMenu(cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  // nvim opens on the tag's line with neo-tree revealing the file; Claude Code
  // goes through the review dialog first, so the prompt can be edited.
  chooseMenu(i) {
    const o = props(), p = o.menu, it = menuItems(p)[i];
    if (!it) return;
    // Act before closing: what a closed popup asks for (shared values, new
    // overlays) is dropped.
    if (p.host) Deploy.chooseHost(p, it.id);
    else if (it.id === "nvim") openTab(p.tag.label, p.root, p.space, ["nvim", `+${p.tag.line}`, p.tag.file, "-c", "Neotree show reveal"]);
    else if (it.id === "upstream") openUrl(p.tag.url);
    else if (it.id === "claude") openReview(p);
    closeOverlay(o.overlay);
  }

  // Switch now asks first: it restarts services on a running machine. The
  // generation id makes comin-deploy refuse if a newer one arrived meanwhile.
  static chooseHost(p, id) {
    if (id === "switch") {
      openOverlay({ mod: "fleet", kind: "dialog", modal: true, width: 440, height: 190, props: { confirmSwitch: p } });
    } else if (id === "boot") {
      hostTab(p, `boot: ${p.host}`, `comin-deploy boot ${p.pending}`);
      askRefresh(p.host, { watch: true });
    } else if (id === "reboot") {
      openOverlay({ mod: "fleet", kind: "dialog", modal: true, width: 440, height: 170, props: { confirmReboot: p } });
    } else if (id === "diff") {
      openOverlay({ mod: "fleet", kind: "dialog", modal: true, width: 760, height: 560, props: { diffView: p } });
    } else if (id.startsWith("mode-")) {
      // The write runs here (it outlives the popup); the panel shows the new
      // mode at once and probes again.
      const [cmd, ...args] = onHost(p, `comin-deploy mode ${id.slice(5)}`);
      exec(cmd, args);
      askRefresh(p.host, { mode: id.slice(5) });
    }
  }

  confirmSwitchDialog(t) {
    const o = props(), p = o.confirmSwitch;
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    const go = () => {
      hostTab(p, `switch: ${p.host}`, `comin-deploy switch${p.pending ? ` ${p.pending}` : ""}`);
      askRefresh(p.host, { watch: true });
      closeOverlay(o.overlay);
    };
    return v_flex().size_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(o.overlay); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child(`Switch ${p.host} now?`))
      .child(div().pt(8).flex_1().text_size(12.5).text_color(t.muted).child(p.darwin
        ? `Activates ${short(p.commit)} on ${p.host} now. Progress shows in a new tab.`
        : `Activates ${short(p.commit)} on ${p.host} now: changed services restart, and it becomes the next boot. If it changes a switch-inhibitor, comin stages it for boot instead. Progress shows in a new tab.`))
      .child(h_flex().pt(14).gap(8).justify_end()
        .child(button("sw-cancel", "Cancel", false, () => closeOverlay(o.overlay)))
        .child(button("sw-go", "Switch now", true, go)));
  }

  // The reboot itself runs in the panel (askRefresh), which outlives this
  // dialog and can open the sudo peek after it closes.
  confirmRebootDialog(t) {
    const o = props(), p = o.confirmReboot;
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    const go = () => {
      askRefresh(p.host, { reboot: true });
      closeOverlay(o.overlay);
    };
    return v_flex().size_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(o.overlay); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child(`Reboot ${p.host}?`))
      .child(div().pt(8).flex_1().text_size(12.5).text_color(t.muted)
        .child(`Reboots ${p.host} now. If sudo asks for a password, a terminal opens for it.`))
      .child(h_flex().pt(14).gap(8).justify_end()
        .child(button("rb-cancel", "Cancel", false, () => closeOverlay(o.overlay)))
        .child(button("rb-go", "Reboot", true, go)));
  }

  // The props a host row's menu and its actions need.
  hostTarget(name) {
    const h = this.hosts[name];
    return { host: name, alias: name.toLowerCase(), local: name.toLowerCase() === this.local, darwin: DARWIN.has(name),
      pending: h.pending, pendingOut: h.pendingOut, diffTo: h.diffTo, mode: h.mode, busy: h.busy, suspended: h.suspended,
      rebootPending: h.rebootPending, failed: h.failed,
      commit: h.pending ? h.pendingCommit : h.rebootPending ? h.stagedCommit : h.failed ? h.deployed : h.building };
  }

  openHostMenu(name) {
    const h = this.hosts[name];
    if (!h || h.offline) return;
    const p = this.hostTarget(name);
    if (!hostMenuItems(p).length) return;
    openOverlay({ mod: "fleet", kind: "popup", width: 230, height: hostMenuItems(p).length * 31 + 10, props: { menu: p } });
  }

  menuPopup(t) {
    const p = props(), list = menuItems(p.menu);
    return v_flex().id("w-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") this.chooseMenu(this.at);
        else if (e.key === "escape") closeOverlay(p.overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => h_flex().id(`wm-${i}`).h(31).px(8).gap(9).rounded(7).items_center()
        .text_color(t.foreground)
        .when(i === this.at, (el) => el.bg(t.selected))
        .hover((s) => s.bg(t.hover)).on_click(() => this.chooseMenu(i))
        .child(svg(`mods/workspace-chrome/${it.icon}.svg`).size(14).flex_none().text_color(t.muted))
        .child(div().flex_1().child(it.label))));
  }

  initReview() {
    this.prompt = TextareaState.new({ value: props().review.text });
    this.prompt.focus();
  }

  startClaude() {
    const p = props(), r = p.review;
    closeOverlay(p.overlay);
    openTab(`claude: ${r.name}`, r.root, r.space, ["claude", this.prompt.value()]);
  }

  reviewDialog(t) {
    const p = props(), r = p.review;
    const button = (id, text, primary, action) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium().cursor_pointer()
      .hover((s) => s.opacity(0.88)).on_click(action).child(text);
    return v_flex().size_full().min_h(0).p(18).bg(t.popover).text_color(t.foreground)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(p.overlay); cx.stop_propagation(); } })
      .child(div().text_size(15).font_semibold().child(r.title))
      .child(div().pt(4).pb(10).text_size(11.5).text_color(t.dim)
        .child(`${r.about} · runs in a new tab at the checkout. Edit the prompt if you like.`))
      .child(Textarea.new(this.prompt).flex_1().min_h(0).p(10).rounded(9).border_1().border_color(t.accent)
        .bg(t.background).text_size(12.5).text_color(t.foreground))
      .child(h_flex().pt(14).gap(8).justify_end()
        .child(button("rv-cancel", "Cancel", false, () => closeOverlay(p.overlay)))
        .child(button("rv-start", "Start in Claude Code", true, () => this.startClaude())));
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


  // ---- Drawing: flat sections, Deploy above Watch, in the idiom of the
  // Agents and Spaces sidebars ----

  // A status pill tinted with a theme colour (by name).
  chip(text, color, t) {
    const c = t[color] ?? t.dim;
    return div().flex_none().h(18).px(7).rounded(5).bg(c + "26").text_color(c)
      .text_size(10.5).font_semibold().flex().items_center().child(text);
  }

  marker(color, hollow, t) {
    const c = t[color] ?? t.dim;
    return div().size(7).flex_none().rounded(4).when(hollow, (el) => el.border(1.5).border_color(c)).when(!hollow, (el) => el.bg(c));
  }

  // A section title like the Agents sidebar's; clicking it folds the section.
  section(id, label, right, t) {
    const folded = Boolean(this.collapsed[id]);
    return h_flex().h(41).px(16).pt(14).pb(5).flex_none().gap(6).items_center()
      .child(h_flex().id(`toggle-${id}`).flex_1().gap(6).items_center().cursor_pointer()
        .on_click((_e, cx) => this.toggle(id, cx))
        .child(div().text_size(11.5).font_medium().text_color(t.dim).child(label))
        .when(folded, (el) => el.child(svg("mods/workspace-chrome/chevron-right.svg").size(10).flex_none().text_color(t.dim))))
      .child(right);
  }

  // An uppercase group label like the Agents sidebar's, with an optional
  // control on the right.
  groupLabel(id, text, color, right, onClick) {
    return h_flex().id(id).pl(8).pr(8).pt(10).pb(4).flex_none().gap(6).items_center()
      .text_size(10.5).font_semibold().text_color(color)
      .when(Boolean(onClick), (el) => el.cursor_pointer().on_click(onClick))
      .child(div().flex_1().child(text))
      .child(right ?? div());
  }

  // Header chips: whatever needs attention, else one "Up to date".
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
    return chips.length ? chips : [this.chip("Up to date", "ansi2", t)];
  }

  // master › build › deploy on one line; the build opens its run.
  pipeline(t) {
    const run = this.run;
    const [ci, color] = !run ? ["no run", t.dim]
      : run.status !== "completed" ? ["building", t.working]
      : run.conclusion === "success" ? ["passed", t.ansi2]
      : [run.conclusion || "failed", t.ansi1];
    const mono = settings().font_family ?? "JetBrains Mono";
    const name = (text) => div().flex_none().font_medium().text_color(t.muted).child(text);
    const sha = (s, c) => div().flex_none().font_family(mono).text_size(10.5).text_color(c ?? t.dim).child(short(s));
    const sep = () => div().flex_none().text_color(t.input).child("›");
    return h_flex().h(28).mx(8).px(8).gap(6).flex_none().items_center().text_size(11).text_color(t.dim)
      .child(name("master")).child(sha(this.master))
      .child(sep())
      .child(h_flex().id("pipe-build").gap(6).items_center().rounded(5).cursor_pointer()
        .hover((s) => s.bg(t.hover)).on_click(() => this.openRun())
        .child(name("build")).child(div().flex_none().text_color(color).child(ci)))
      .child(sep())
      .child(name("deploy")).child(sha(this.deploySha, this.ahead ? t.blocked : null))
      .when(this.ahead > 0, (el) => el.child(div().min_w(0).truncate().text_color(t.blocked).child(`${this.ahead} behind`)));
  }

  // A host row like a Spaces machine header: icon tile, name over detail, pill.
  host(id, icon, name, sub, right, t) {
    return h_flex().id(id).h(34).flex_none().pl(2).pr(6).gap(9).items_center().rounded(8).hover((s) => s.bg(t.hover))
      .child(div().size(26).flex_none().rounded(7).bg(t.selected).flex().items_center().justify_center()
        .child(svg(`mods/workspace-chrome/${icon}.svg`).size(14).text_color(t.muted)))
      .child(v_flex().flex_1().min_w(0).child(name).child(sub))
      .child(right);
  }

  // How the host takes new commits, outlined like the Agents effort pill:
  // manual in dim, an automatic mode in the accent. A host without
  // comin-deploy deploys every commit with its comin operation.
  modePill(name, h, t) {
    const mode = h.mode || (DARWIN.has(name) ? "switch" : "boot");
    const auto = mode !== "manual";
    return div().flex_none().px(5).h(16).rounded(4).border(1).border_color(auto ? t.accent : t.dim)
      .flex().items_center().text_size(10).text_color(auto ? t.accent : t.dim)
      .child(auto ? `auto ${mode}` : "manual");
  }

  hostItem(name, t) {
    const h = this.hosts[name];
    const following = this.deploying.has(name);
    const [label, color] = following && h.depStatus !== "failed" ? ["deploying", "working"] : verdict(h, this.deploySha);
    // A newer commit whose system is the deployed one: comin skipped it, but
    // the host already has (or boots into) what it builds.
    const same = h.unchanged && Boolean(h.building) && h.building !== h.deployed;
    const detail = h.offline ? h.reason || "no SSH answer"
      : h.pending && !h.busy ? `${short(h.pendingCommit)} held · right-click to deploy`
      : h.depStatus === "failed" ? h.depError
      : h.buildError && h.building === this.deploySha ? h.buildError
      : `${short(same ? h.building : h.deployed)} · ${h.operation || "—"} · ${ago(h.depAt)}`;
    const title = h_flex().gap(6).items_center().min_w(0).text_size(12.5)
      .child(div().truncate().when(Boolean(h.offline), (el) => el.text_color(t.muted)).child(name))
      .when(name.toLowerCase() === this.local, (el) => el.child(div().flex_none().text_size(10).text_color(t.dim).child("this computer")))
      .when(!h.offline, (el) => el.child(this.modePill(name, h, t)));
    const sub = h_flex().gap(5).items_center().min_w(0).text_size(10.5).text_color(t.dim)
      .child(this.marker(color, Boolean(h.offline), t))
      .child(div().truncate().child(detail))
      .when(same, (el) => el.id(`host-same-${name}`).tooltip(`Same system as ${short(h.deployed)}, deployed ${ago(h.depAt)}`));
    const right = h_flex().gap(6).items_center()
      .when(h.busy || following, (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)))
      .child(this.chip(cap(label === "reboot pending" ? "reboot" : label), color, t));
    return this.host(`host-${name}`, name === "Nexus" ? "server" : "monitor", title, sub, right, t)
      .when(Boolean(h.mode || h.diffTo), (el) => el.cursor_pointer().tooltip("Right-click for options")
        .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openHostMenu(name); }));
  }

  deploySection(t) {
    const open = !this.collapsed.deploy;
    const known = HOSTS.filter((name) => this.hosts[name]);
    const online = known.filter((name) => !this.hosts[name].offline);
    const offline = known.filter((name) => this.hosts[name].offline);
    const pending = HOSTS.filter((name) => !this.hosts[name]);
    const right = h_flex().gap(5).items_center()
      .children(this.deployChips(t))
      .child(div().id("refresh").px(6).py(2).rounded(6).cursor_pointer().text_size(11).text_color(t.dim)
        .hover((s) => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => { this.refresh(cx); this.loadWatch(cx); })
        .child(this.loading ? "…" : "Refresh"));
    return v_flex().flex_none()
      .child(this.section("deploy", "Deploy", right, t))
      .when(Boolean(this.ghError), (el) => el.child(div().px(16).pb(4).text_size(11).text_color(t.ansi1).child(`GitHub: ${this.ghError}`)))
      .when(open, (el) => el
        .child(this.pipeline(t))
        .child(v_flex().px(8).gap(1)
          .children(online.map((name) => this.hostItem(name, t)))
          .children(offline.map((name) => this.hostItem(name, t)))
          .when(pending.length > 0, (el) => el.child(div().px(8).py(7).text_size(12).text_color(t.dim).truncate()
            .child(`Checking ${pending.join(" · ")}…`)))));
  }

  // A Watch row's chip, its colour, and what the detail line adds beyond the
  // chip (null when the chip already says it all).
  static tagChip(tag) {
    const ready = tag.state === "ready", text = tag.text ?? "";
    if (tag.state === "unknown") return ["Check by hand", "ansi3", text.replace(/^not checked: /, "")];
    if (tag.kind === "watch") return [cap(tag.state), tag.state === "closed" ? "ansi3" : "dim", null];
    if (tag.kind === "manual") return ["Manual", "dim", /· (.+)$/.test(text) ? `checked ${/· (.+)$/.exec(text)[1]}` : null];
    switch (tag.kind) {
      case "unstable":
        if (ready) return ["In unstable", "ansi2", null];
        return /not merged|unmerged/.test(text) ? ["Not merged", "dim", null] : ["Not in unstable", "dim", "PR merged"];
      case "merged": return ready ? ["Merged", "ansi2", null] : ["Not merged", "dim", null];
      case "closed": return ready ? ["Closed", "ansi2", /not planned/.test(text) ? "not planned" : null] : ["Open", "dim", null];
      case "green": return ready ? ["Green", "ansi2", text] : ["Hydra red", "dim", text];
      case "version": return ready ? ["Available", "ansi2", text] : [text, "dim", null];
    }
    return [text, "dim", null];
  }

  // A tag: a lettered badge, its label and chip, then the ref and every site
  // it sits at. Click opens upstream; the right-click menu holds the actions.
  watchItem(tag, i, t) {
    const [chipText, chipColor, detail] = Deploy.tagChip(tag);
    const watch = tag.kind === "watch";
    const ref = tag.kind === "version" ? "nixos-unstable" : shortRef(tag);
    const mono = settings().font_family ?? "JetBrains Mono";
    const site = (s) => div().flex_none().h(17).px(6).rounded(5).bg(t.hover).flex().items_center()
      .font_family(mono).text_size(10).text_color(t.muted).child(`${s.file.split("/").pop()}:${s.line}`);
    return v_flex().id(`watch-${i}`).flex_none().px(8).py(5).gap(3).rounded(8).cursor_pointer().hover((s) => s.bg(t.hover))
      .when(Boolean(tag.url), (el) => el.on_click(() => openUrl(tag.url)))
      .on_mouse_down("right", (_e, cx) => { cx.stop_propagation(); this.openMenu(tag); })
      .tooltip(tag.url ? "Click opens upstream · right-click for more" : "Right-click for more")
      .child(h_flex().gap(8).items_center()
        .child(div().size(16).flex_none().rounded(4).bg(badgeColor(tag.label)).flex().items_center().justify_center()
          .text_size(9.5).font_bold().text_color("#ffffff").child([...tag.label][0]?.toUpperCase() ?? "?"))
        .child(div().flex_1().min_w(0).truncate().text_size(12.5).text_color(watch ? t.muted : t.foreground).child(tag.label))
        .child(this.chip(chipText, chipColor, t)))
      .child(h_flex().pl(24).flex_wrap().gap(4).gap_y(3).items_center().text_size(10.5).text_color(t.dim)
        .child(div().child([ref, detail].filter(Boolean).join(" · ")))
        .children(tag.sites.map(site)));
  }

  // Fix all: one review dialog, one session, for every ready tag.
  openFixAll(ready) {
    if (!this.repo) return;
    const { root, space } = this.target(ready[0]);
    const names = ready.map((tag) => tag.label).join(", ");
    openReviewDialog({ root, space, name: ready.length === 1 ? ready[0].label : "ready tags", about: names,
      title: `Fix ${ready.length} ready tag${ready.length === 1 ? "" : "s"} in Claude Code`, text: fixAll(ready) });
  }

  watchSection(t) {
    const open = !this.collapsed.watch;
    const tags = this.tags ?? [];
    const right = this.watchLoading ? div().text_size(11).text_color(t.dim).child("checking…") : div();
    // Ready tags are always open, with Fix all; every other group folds to
    // its label, folded until opened.
    const ready = tags.filter((tag) => tag.state === "ready");
    const groups = [
      ["check", "Check by hand", t.ansi3, (tag) => tag.state === "unknown"],
      ["waiting", "Waiting", t.dim, (tag) => tag.state === "waiting"],
      ["manual", "Manual", t.dim, (tag) => tag.state === "manual"],
      ["watching", "Watching", t.dim, (tag) => tag.kind === "watch"],
    ];
    const rows = [];
    if (ready.length) {
      const fix = h_flex().id("fix-all").flex_none().h(20).px(8).rounded(6).items_center().bg(t.ansi2).text_color(t.background)
        .text_size(11).font_semibold().cursor_pointer().hover((s) => s.opacity(0.88))
        .on_click((_e, cx) => { cx.stop_propagation(); this.openFixAll(ready); })
        .tooltip("One Claude Code session for every ready tag")
        .child("Fix all");
      rows.push(this.groupLabel("grp-ready", `READY · ${ready.length}`, t.ansi2, fix));
      rows.push(...ready.map((tag) => this.watchItem(tag, tags.indexOf(tag), t)));
    }
    for (const [id, label, color, test] of groups) {
      const members = tags.filter(test);
      if (!members.length) continue;
      const key = `open-${id}`, shown = Boolean(this.collapsed[key]);
      rows.push(this.groupLabel(`grp-${id}`, `${label.toUpperCase()} · ${members.length}`, color,
        shown ? null : svg("mods/workspace-chrome/chevron-right.svg").size(10).flex_none(),
        (_e, cx) => this.toggle(key, cx)));
      if (shown) rows.push(...members.map((tag) => this.watchItem(tag, tags.indexOf(tag), t)));
    }
    const behind = this.checkoutBehind();
    const c = this.checkout;
    return v_flex().flex_none()
      .child(this.section("watch", "Watch", right, t))
      .when(open && Boolean(c), (el) => el.child(h_flex().flex_none().px(16).pb(2).gap(4).text_size(10.5).text_color(t.dim).min_w(0)
        .child(div().truncate().child(`${c.machine ?? this.local ?? "this computer"} · ${c.branch ?? "?"} @ ${c.head?.slice(0, 7) ?? "?"}`))
        .when(Boolean(behind), (el) => el.child(div().flex_none().text_color(t.blocked).child(`· ${behind}`)))))
      .when(open && Boolean(this.watchError), (el) => el.child(div().px(16).pt(4).text_size(11).text_color(t.ansi1).child(this.watchError)))
      .when(open && Boolean(this.tags) && !tags.length && !this.watchLoading, (el) => el.child(
        div().px(16).py(8).text_size(12).text_color(t.dim).child(behind
          ? "No WAIT-FOR / WATCH tags in this checkout. Pull master to see them."
          : "No WAIT-FOR / WATCH tags in this checkout.")))
      .when(open, (el) => el.child(v_flex().px(8).gap(1).children(rows)));
  }

  render(cx) {
    const t = theme();
    if (props()?.menu) return this.menuPopup(t);
    if (props()?.review) return this.reviewDialog(t);
    if (props()?.confirmSwitch) return this.confirmSwitchDialog(t);
    if (props()?.confirmReboot) return this.confirmRebootDialog(t);
    if (props()?.diffView) return this.diffDialog(t);
    this.follow(cx);
    this.takeAsk();
    return v_flex().id("deploy-panel").size_full().min_h(0).pb(8).overflow_y_scrollbar().bg(t.chrome).text_color(t.foreground).text_size(13)
      .child(this.deploySection(t))
      .child(this.watchSection(t));
  }
}
