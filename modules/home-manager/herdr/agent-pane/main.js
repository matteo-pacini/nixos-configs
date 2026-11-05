// A pane's header, for layouts that frame their panes:
//   { "tab": "active", "pane": { "header": { "content": { "mod": "agent-pane" } } } }
// Shows the program's icon (the app's program table), the agent's name or
// the terminal's title, the folder, and the agent's status; buttons split, zoom and close
// this pane. Props from the app: { pane, terminal }. Click: focus the pane.
// Derived from Herdr's shipped `pane` mod: an agent (Claude Code, Codex,
// opencode) older than the one installed on its machine gets an OUTDATED badge
// and a button that restarts it on the new version, resuming the same session.

import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { panes, terminals, props, run, theme, home, exec, hc, notify } from "herdr";

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
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

export default class Pane extends View {
  init() { this.hovered = false; }

  me() {
    return panes().find((p) => p.pane === props()?.pane);
  }

  button(t, id, icon, command, args) {
    return div()
      .id(id)
      .p(3)
      .rounded(4)
      .text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run(command, args);
      })
      .child(svg(`mods/pane/${icon}.svg`).size(14));
  }

  render(cx) {
    const t = theme();
    const p = this.me();
    if (!p) return div();
    const name = ((p.program?.agent || p.program?.shell) && p.program.name) || p.title || p.program?.name || "shell";
    const pic = icon(p.program, 14, t.dim);
    const st = p.status;
    const pane = p.pane;
    // Running version: what the agent labelled its terminal with.
    const app = APPS[p.app];
    const term = p.terminal && app ? terminals().find((k) => k.address === p.terminal) : null;
    const running = term?.labels?.["agent.version"];
    const machine = p.terminal?.includes("/") ? p.terminal.split("/")[0] : null;
    const latest = running ? installedVersion(machine, app, cx) : null;
    const outdated = Boolean(latest) && cmpVersion(running, latest) < 0;
    const session = term?.labels?.[app?.session];
    const busy = st === "working" || st === "blocked";
    return h_flex()
      .id(`pane-head-${pane}`)
      .size_full()
      .px(10)
      .gap(8)
      .items_center()
      .bg(t.background)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .on_hover((hovered, cx) => { this.hovered = hovered; cx.notify(); })
      .on_click(() => run("pane.focus", { pane }))
      .when(Boolean(pic), (el) => el.child(pic))
      .child(div().flex_none().truncate().max_w(260).font_medium().text_color(t.foreground).child(name))
      .when(outdated, (el) => el
        .child(div().id(`ph-old-${pane}`).flex_none().px(6).h(17).rounded(4).bg(t.ansi3 + "26").flex().items_center()
          .text_size(10).font_bold().text_color(t.ansi3).child("OUTDATED")
          .tooltip(`${app?.name} ${running} is running; ${latest} is installed.`))
        .when(Boolean(session), (el) => el.child(div().id(`ph-restart-${pane}`).flex_none().px(8).h(20).rounded(6)
          .border_1().border_color(t.ansi3 + "66").flex().items_center().text_size(11).font_semibold()
          .text_color(busy ? t.dim : t.ansi3)
          .when(!busy, (el) => el.cursor_pointer().hover((s) => s.bg(t.ansi3 + "1a"))
            .on_click((_e, cx) => { cx.stop_propagation(); restartAgent(p.terminal, app, session); }))
          .tooltip(busy ? "Wait until it's idle" : "Exit and resume this session on the installed version")
          .child(`Restart on ${latest}`))))
      .child(div().flex_1().truncate().text_color(t.dim).child(folder(p.cwd)))
      .when(st === "working", el => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900)))
      .when(st === "blocked", el => el.child(div().flex_none().px(6).h(18).flex().items_center().rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).child("Needs you")))
      .when(st === "done", el => el.child(div().size(7).flex_none().rounded(4).bg(t.done)))
      .when(this.hovered, el => el
        .child(this.button(t, `ph-r-${pane}`, "split-right", "pane.split", { direction: "right", pane }))
        .child(this.button(t, `ph-d-${pane}`, "split-down", "pane.split", { direction: "down", pane }))
        .child(this.button(t, `ph-z-${pane}`, p.zoomed ? "unzoom" : "zoom", "pane.zoom", { pane }))
        .child(this.button(t, `ph-x-${pane}`, "close", "pane.close", { pane })));
  }
}
