// Coding agents that can be restarted on the version installed on their
// machine, resuming the same session: agent-list's "Restart on" menu item and
// pane-header's OUTDATED button. The running version and session id are
// terminal labels the agents set themselves (scripts/claude-statusline.sh,
// scripts/codex-labels.sh, scripts/opencode-labels.js).

import { exec, hc, notify } from "herdr";
import { cmpVersion } from "./version.js";

// By the app herdr reports: the command on PATH, the package name in its store
// path, the label holding the session, how to quit (text to send, or `keys:`
// to press) and resume one, and the screen text of a prompt quitting can raise
// instead, which Enter answers.
// opencode takes pasted text as a prompt, so it's quit with a key. Claude asks
// before quitting with background work running; Enter takes its default, "Exit
// and stop tasks". Its "Move to background" would keep the old version running
// in a daemon under a forked session, so the resume would only reattach to it.
export const APPS = {
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

/** The installed version of `app` (an APPS entry) on `machine` (null: this
 *  one), or null until read; reading it notifies `cx`. */
export function installedVersion(machine, app, cx) {
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

/** For the agent `appKey` (an APPS key, or anything else for a non-agent) in
 *  the terminal at `address` (`machine/t7` when remote) with terminal `labels`:
 *  { app, running, latest, outdated, session }. `latest` is null until the
 *  installed version is read (see installedVersion). */
export function agentVersion(appKey, address, labels, cx) {
  const app = APPS[appKey];
  const running = app ? labels?.["agent.version"] : null;
  const machine = address?.includes("/") ? address.split("/")[0] : null;
  const latest = running ? installedVersion(machine, app, cx) : null;
  const outdated = Boolean(latest) && cmpVersion(running, latest) < 0;
  return { app, running, latest, outdated, session: app ? labels?.[app.session] : undefined };
}

// The terminal's program has to be a shell that outlives the agent: an
// interactive one, which runs the agent in its own process group (hc's
// foreground is then another process), or a `sh -c "agent; exec sh"`, whose
// agent shares its group (the foreground is the script until it execs the
// shell). Quitting an agent that is the terminal's own program would end the
// terminal, and the resume would have no shell to type into.
// `t` is `hc get <terminal> --json`.
const SHELLS = /^-?(sh|bash|zsh|fish|dash|ksh)$/;
const isShell = (argv) => SHELLS.test((argv?.[0] ?? "").split("/").pop());
const isScript = (argv) => argv.slice(1).some((a) => /^-[a-z]*c[a-z]*$/.test(a));
/** The terminal's shell is at its prompt: nothing runs in it. */
export const atPrompt = (t) => t.foreground?.pid === t.pid && isShell(t.foreground.argv) && !isScript(t.foreground.argv);
/** What runs in the terminal was started from a shell that will outlive it. */
export const fromShell = (t) => isShell(t.argv) && Boolean(t.foreground) && (t.foreground.pid !== t.pid
  || (isShell(t.foreground.argv) && /;\s*exec\s+\S*sh\b[^;]*$/.test(t.foreground.argv.at(-1))));

// Bare words stay bare, so the typed line reads as a person would type it.
const quote = (a) => (/^[\w@%+=:,./#-]+$/.test(a) ? a : `'${a.replace(/'/g, "'\\''")}'`);

/** Types `argv` at the prompt of `address`, a terminal whose program is an
 *  interactive shell, once the shell is up. The agent then starts as if typed
 *  by hand: after the shell's startup and prompt hooks (direnv's dev shell),
 *  and it leaves the shell behind when it exits. Failures are shown as a
 *  notification. */
export async function typeAtPrompt(address, argv, name) {
  try {
    let up = false;
    for (let i = 0; i < 40 && !up; i++) {
      const r = await hc(["get", address, "--json"]);
      up = r.code === 0 && atPrompt(JSON.parse(r.stdout));
      if (!up) await exec("sleep", ["0.25"]);
    }
    if (!up) throw new Error("its shell didn't start");
    const r = await hc(["send", address, argv.map(quote).join(" ")]);
    if (r.code !== 0) throw new Error(r.stderr.trim());
  } catch (e) {
    notify({ title: `Couldn't start ${name}`, body: String(e.message ?? e), level: "error" });
  }
}

/** Quits the agent in `address`, answers the prompt quitting can raise (when
 *  its screen shows `app.asks`) with Enter, waits for its shell's prompt, then
 *  resumes `session` with the version now on PATH. Failures are shown as a
 *  notification. hc addresses remote terminals itself, so this runs here. */
export async function restartAgent(address, app, session) {
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
