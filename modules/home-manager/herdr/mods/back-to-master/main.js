// The dialog the space menu's "Back to <default branch>" opens: fetches, says
// what going back does to this checkout, then saves the work, switches,
// fast-forwards and deletes the branch in one exec (lib/back.js RUN).
// Props: { space, overlay }.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, closeOverlay, theme, spaces, panes, settings } from "herdr";
import { MENU_PROBE, DIALOG_PROBE, FETCH, RUN, sh, fields, parseStatus, plan, runArgs, failure, lastLine, working, needsYou } from "./lib/back.js";
import { lookup, onGitHub } from "./lib/pr.js";
import { origin } from "./lib/git.js";

// exec's own limit; a call that rejects after this long timed out.
const LIMIT = 29_000;

// Where a space is now: its first terminal's live folder, else where it was made.
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

// Whether HEAD is in the merged PR (covers) or the PR is in HEAD with commits
// after it (newer); the PR's head may not be fetched, which says neither.
const PR_CHECK = `if git merge-base --is-ancestor HEAD "$1" 2>/dev/null; then echo covers=1
elif git cat-file -e "$1^{commit}" 2>/dev/null && git merge-base --is-ancestor "$1" HEAD; then echo "newer=$(git rev-list --count "$1..HEAD")"; fi`;

const SNAPSHOT = `git rev-parse HEAD; echo --status--; git --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --untracked-files=all`;

export default class BackToMaster extends View {
  init(_props, cx) {
    this.space = spaces().find((s) => s.id === props()?.space);
    this.on = this.space?.machine ?? null;
    this.cwd = this.space ? place(this.space) : null;
    this.phase = "fetching"; // fetching, reading, ready, running, changed, stopped
    this.lines = [];
    this.plan = null;
    this.mode = "stash";
    this.del = false;
    this.keep = true;
    this.input = InputState.new({ value: "", placeholder: `herdr: ${this.space?.branch ?? "HEAD"}` });
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.spawn(async (cx) => this.load(cx, true));
  }

  stop(cx, lines) {
    this.phase = "stopped";
    this.lines = lines;
    cx.notify();
  }

  // Why an exec rejected: the machine went away, or it ran into exec's limit.
  lost(started, during) {
    if (Date.now() - started >= LIMIT) return [{ text: `git took over 30 s ${during}.`, tone: "blocked" }, { text: "Run git status before going on.", tone: "muted" }];
    if (this.on) return [{ text: `${this.on} went away ${during}.`, tone: "blocked" }, { text: "Run git status there before going on.", tone: "muted" }];
    return [{ text: `git couldn’t run ${during}.`, tone: "blocked" }];
  }

  async load(cx, fetch) {
    this.phase = fetch ? "fetching" : "reading";
    this.lines = [];
    cx.notify();
    if (!this.cwd) return this.stop(cx, [{ text: "This space is gone.", tone: "blocked" }]);
    let started = Date.now();
    try {
      // Before the fetch, so a failed one still names the branch and the target.
      this.f = fields((await sh(MENU_PROBE, this.cwd, this.on)).stdout);
      cx.notify();
      const url = await origin(this.cwd, this.on);
      if (fetch && url) {
        const r = await sh(FETCH, this.cwd, this.on);
        const code = Number(fields(r.stdout).exit);
        const nothing = { text: "Nothing changed.", tone: "muted" };
        if (code === 124) return this.stop(cx, [{ text: `Fetch${this.on ? ` on ${this.on}` : ""} took over 25 s.`, tone: "blocked" }, nothing]);
        if (code !== 0) return this.stop(cx, [{ text: `Couldn’t fetch origin: ${lastLine(r.stderr) || `exit ${code}`}`, tone: "blocked" }, nothing]);
      }
      started = Date.now();
      const r = await sh(DIALOG_PROBE, this.cwd, this.on);
      const [head, rest = ""] = r.stdout.split("--status--\n");
      const f = fields(head);
      if (f.git !== "yes") return this.stop(cx, [{ text: "This folder is not in a git repository.", tone: "blocked" }]);
      if (!f.default) return this.stop(cx, [{ text: "No default branch: no origin/HEAD, master or main.", tone: "blocked" }]);
      const pr = f.branch && f.ahead !== "0" && onGitHub(url) ? await this.prCheck() : null;
      this.f = f;
      this.snapshot = `${f.head}\n${rest}`;
      this.plan = plan(f, parseStatus(rest), pr);
      this.del = this.plan.del?.on ?? false;
      if (!this.input.value()) this.input.set_value(`herdr: ${this.plan.branch ?? this.plan.short}`);
      this.phase = "ready";
      cx.notify();
    } catch {
      this.stop(cx, this.lost(started, fetch ? "fetching" : "reading the checkout"));
    }
  }

  async prCheck() {
    const found = await lookup(this.cwd, this.on);
    const pr = found.pr;
    if (!pr || pr.state !== "merged" || !pr.head) return null;
    const g = fields((await sh(PR_CHECK, this.cwd, this.on, [pr.head])).stdout);
    return g.covers ? { number: pr.number, covers: true } : g.newer ? { number: pr.number, newer: Number(g.newer) } : null;
  }

  async go(cx) {
    if (this.phase !== "ready") return;
    this.phase = "running";
    cx.notify();
    const started = Date.now();
    try {
      // What the person agreed to must still be what's there.
      const now = await sh(SNAPSHOT, this.cwd, this.on);
      const [sha, rest = ""] = now.stdout.split("--status--\n");
      const s = spaces().find((x) => x.id === this.space?.id);
      if (`${sha.trim()}\n${rest}` !== this.snapshot || (s && (working(s) || needsYou(s)))) {
        this.phase = "changed";
        this.lines = [{ text: "It changed since this opened. Check again.", tone: "caution" }];
        return cx.notify();
      }
      const args = runArgs(this.plan, { mode: this.mode, message: this.input.value(), del: this.del, keep: this.keep });
      const r = await sh(RUN, this.cwd, this.on, args);
      if (r.code === 0) return closeOverlay(props().overlay);
      const where = await sh("git symbolic-ref -q --short HEAD || git rev-parse --short HEAD", this.cwd, this.on).then((x) => x.stdout.trim()).catch(() => "");
      this.stop(cx, failure(r.code, r.stderr, { p: this.plan, mode: args[0], message: args[1], stashed: fields(r.stdout).stashed === "1", del: Boolean(args[6]), where }));
    } catch {
      this.stop(cx, this.lost(started, "during the switch"));
    }
  }

  primary(cx) {
    if (this.phase === "ready") cx.spawn(async (cx) => this.go(cx));
    else if (this.phase === "changed") cx.spawn(async (cx) => this.load(cx, false));
    else if (this.phase === "stopped") closeOverlay(props().overlay);
  }

  // What the running line says the exec is doing.
  doing() {
    const p = this.plan;
    const steps = [p.save && (this.mode === "wip" ? "committing" : "stashing"), "switching", p.args.ff === "1" && "fast-forwarding", this.del && p.del && this.mode !== "wip" && "deleting the branch"].filter(Boolean);
    const text = steps.join(", ");
    return `${text[0].toUpperCase()}${text.slice(1)}…`;
  }

  render(cx) {
    const t = theme();
    const p = this.plan;
    const tone = { ok: t.ansi2, caution: t.ansi3, blocked: t.blocked, muted: t.muted, plain: t.foreground };
    const target = p?.target ?? (this.f?.default || "default branch");
    const lines =
      this.phase === "fetching" ? [{ text: "Fetching origin…", tone: "muted" }]
      : this.phase === "reading" ? [{ text: "Reading the checkout…", tone: "muted" }]
      : this.phase === "running" ? [{ text: this.doing(), tone: "muted" }]
      : this.phase === "ready" ? p.lines
      : this.lines;
    const ready = this.phase === "ready";
    const wip = this.mode === "wip";

    const mark = (id, on, round, off, label, hint, act) => h_flex().id(id).gap(9).items_center()
      .when(!off, (el) => el.cursor_pointer().on_click(act))
      .text_color(off ? t.dim : t.foreground)
      .child(div().size(14).flex_none().rounded(round ? 7 : 4).border_1()
        .border_color(on && !off ? t.accent : t.input).bg(on && !off ? t.accent : t.background)
        .flex().items_center().justify_center()
        .when(on && !round, (el) => el.child(svg("mods/workspace-chrome/check.svg").size(10).text_color(t.background)))
        .when(on && round, (el) => el.child(div().size(6).rounded(3).bg(t.background))))
      .child(div().child(label))
      .when(Boolean(hint), (el) => el.child(div().text_size(11.5).text_color(t.dim).child(hint)));

    const button = (id, text, primary, off, act) => h_flex().id(id).h(32).px(14).items_center().rounded(8)
      .border_1().border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised)
      .text_color(off ? t.dim : primary ? t.solid_foreground : t.foreground).text_size(12.5).font_medium()
      .when(!off, (el) => el.cursor_pointer().hover((s) => s.opacity(0.88)).on_click(act))
      .child(text);

    const primaryText = ready ? `Back to ${target}` : this.phase === "changed" ? "Check again" : null;
    const close = () => closeOverlay(props().overlay);

    return v_flex()
      .id("back-to-master")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        if (e.key === "escape") { if (this.phase !== "running") close(); cx.stop_propagation(); }
        else if (e.key === "enter") this.primary(cx);
      })
      .size_full()
      .min_h(0)
      .p(18)
      .gap(14)
      .bg(t.popover)
      .text_size(13)
      .text_color(t.foreground)
      .child(v_flex().gap(6)
        .child(div().text_size(15).font_semibold().child(`Back to ${target}?`))
        .child(h_flex().gap(6).flex_wrap().items_center().text_size(12).text_color(t.muted)
          .when(Boolean(this.f?.repo), (el) => el.child(div().child(`${this.f.repo} ·`)))
          .child(div().font_family(settings().font_family ?? "JetBrains Mono").text_color(t.accent).child(p?.branch ?? p?.short ?? (this.f ? this.f.branch || this.f.short : this.space?.branch ?? "")))
          .child(div().child("to"))
          .child(div().font_family(settings().font_family ?? "JetBrains Mono").text_color(t.accent).child(target))
          .child(div().child(`· ${this.on ?? "this computer"}`))))
      .children(lines.map((l, i) => div().id(`line-${i}`).text_color(tone[l.tone]).child(l.text)))
      .when(ready && p.save, (el) => el.child(v_flex().gap(8)
        .child(mark("stash", !wip, true, false, "Stash", "untracked files included", (_, cx) => { this.mode = "stash"; cx.notify(); }))
        .when(!wip, (el) => el.child(div().ml(23).child(Input.new(this.input).h(30).px(9).items_center().rounded(7).border(1)
          .border_color(t.input).bg(t.background).text_color(t.foreground).text_size(12))))
        .child(mark("wip", wip, true, p.wipOff, "WIP commit on the branch", p.wipOff ? "no branch" : "message: WIP", (_, cx) => { this.mode = "wip"; cx.notify(); }))))
      .when(ready && Boolean(p.del), (el) => {
        const off = p.del.off || wip;
        return el.child(mark("delete", this.del && !off, false, off, "Delete branch", wip && !p.del.off ? "has the WIP commit" : p.del.hint, (_, cx) => { this.del = !this.del; cx.notify(); }));
      })
      .when(ready && Boolean(p.keep), (el) => el.child(mark("keep", this.keep, false, false, `Keep them on a new branch ${p.keep}`, "", (_, cx) => { this.keep = !this.keep; cx.notify(); })))
      .child(div().flex_1())
      .child(h_flex().gap(8).items_center().justify_end()
        .child(div().flex_1().text_size(11.5).text_color(t.dim).child(this.phase === "running" ? "can’t cancel now" : ""))
        .child(button("cancel", this.phase === "stopped" ? "Close" : "Cancel", false, this.phase === "running", close))
        .when(Boolean(primaryText), (el) => el.child(button("go", primaryText, true, false, (_, cx) => this.primary(cx)))));
  }
}
