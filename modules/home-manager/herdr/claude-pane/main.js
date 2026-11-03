// A pane's header, for layouts that frame their panes:
//   { "tab": "active", "pane": { "header": { "content": { "mod": "claude-pane" } } } }
// Shows the program's icon (the app's program table), the agent's name or
// the terminal's title, the folder, and the agent's status; buttons split, zoom and close
// this pane. Props from the app: { pane, terminal }. Click: focus the pane.
// Derived from Herdr's shipped `pane` mod: a Claude Code older than the one
// installed on its machine gets an OUTDATED badge and a button that restarts
// it on the new version, resuming the same session.

import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { panes, terminals, props, run, theme, home, exec, notify } from "herdr";

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

// The claude-code version on PATH per machine (null: this one), re-read at
// most once a minute: { version, at }.
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

export default class Pane extends View {
  init() { this.hovered = false; }

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
    // Running version: what Claude's statusLine reported (claude-statusline.sh).
    const term = p.terminal && p.app === "claude-code" ? terminals().find((k) => k.address === p.terminal) : null;
    const running = term?.labels?.["agent.version"];
    const machine = p.terminal?.includes("/") ? p.terminal.split("/")[0] : null;
    const latest = running ? this.installed(machine, cx) : null;
    const outdated = Boolean(latest) && cmpVersion(running, latest) < 0;
    const session = term?.labels?.["claude.session"];
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
          .tooltip(`Claude Code ${running} is running; ${latest} is installed.`))
        .when(Boolean(session), (el) => el.child(div().id(`ph-restart-${pane}`).flex_none().px(8).h(20).rounded(6)
          .border_1().border_color(t.ansi3 + "66").flex().items_center().text_size(11).font_semibold()
          .text_color(busy ? t.dim : t.ansi3)
          .when(!busy, (el) => el.cursor_pointer().hover((s) => s.bg(t.ansi3 + "1a"))
            .on_click((_e, cx) => { cx.stop_propagation(); restartClaude(p.terminal, session); }))
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
