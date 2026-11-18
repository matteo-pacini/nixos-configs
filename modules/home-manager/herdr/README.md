# herdr module

Home Manager module for [Herdr](https://github.com/herdrdev): `herdr-core`
(`hc`, the server that runs terminals and agents) and the `herdr-app` desktop
app with the `workbench` layout and its mods. Options are under
`custom.herdr`; see `default.nix` and `workbench.nix` for each one's
description.

| Path | What |
|------|------|
| `default.nix` | Imports the rest; `enable`, `desktop` |
| `core.nix` | herdr-core, the app, its theme, Claude sessions resumed after a reboot, the keep-cache-warm service, and the hook that hands a rename to Claude Code. Holds every Claude Code hook (see below) |
| `agent-labels.nix` | The terminal labels the mods draw, set from inside each agent (Claude statusLine, Codex hooks, opencode plugin) |
| `workbench.nix` | `workbench.*` options, the mod build and install, `lib/hosts.js`, the layout file and the first switch to it |
| `layout.nix` | Pure: which optional mods are on → the layout tree |
| `layouts/workbench.json` | Snapshot of herdr-app's shipped `main` layout |
| `mods/<name>/` | One herdr-app mod each: `main.js`, `mod.json`, assets |
| `lib/` | JS shared by the mods (linked in as `mods/<name>/lib`) |
| `scripts/` | Hook scripts and the opencode plugin |
| `tests/` | Flake checks; see [Tests](#tests) |

## How the pieces talk: terminal labels

Mods can't see inside an agent, so each agent writes what the mods draw onto its
own terminal as `hc label` key/values. Mods read them from `terminals()`. An
empty value removes a label.

| Label | Set by | Read by |
|-------|--------|---------|
| `agent.model`, `agent.effort`, `agent.ctx`, `agent.ctxk`, `agent.version` | `claude-statusline.sh` (Claude's statusLine), `codex-labels.sh` (Codex hooks), `opencode-labels.js` | `agent-list` |
| `agent.cache_until`, `agent.cache_ttl` | `claude-statusline.sh` only | `agent-list` (cache-expiring flag); `lib/warm.js` and `claude-keep-warm.sh` (see below) |
| `agent.keep_warm` | the person, from `pane-header`'s switch | `lib/warm.js` (`pane-header`, `agent-list`); `claude-keep-warm.sh` |
| `agent.warm_state`, `agent.warm_failed` | `claude-keep-warm.sh` | `lib/warm.js`: `pane-header` ("Refreshing"), `agent-list` (the failure notification) |
| `agent.ask` | `agent-ask.sh` (Claude and Codex hooks), `opencode-labels.js` | `agent-list` |
| `agent.ask_detail` | `agent-ask.sh` | no mod reads it yet |
| `claude.session`, `codex.session`, `opencode.session` | `claude-session.sh`, `codex-labels.sh`, `opencode-labels.js` | `lib/agents.js` (restart on a newer version); `claude-resume.sh` (resume after reboot) |
| `agent.name`, `agent.name_base` | the person, from `agent-list`'s or `pane-menu`'s Rename (`lib/name.js`); removed by `claude-title.sh` once Claude Code has the name | `lib/name.js` (`agent-list`, `pane-header`, `pane-menu`); `claude-title.sh` |
| `claude.title` | `claude-title.sh` (Claude hooks) | `claude-title.sh` |

Codex's hooks call `herdr-codex-labels` and `herdr-agent-ask`, and Claude
Code's call `herdr-agent-ask`, by their path in the Home Manager profile,
`home.profileDirectory` + `/bin/<name>` (`/etc/profiles/per-user/<user>/bin/…`
on NixOS). Not a bare name: an older copy left earlier on the agent's `PATH`
would shadow the installed one, silently.
Not a store path: Codex trusts a hook by its definition, so a path that
changed on every rebuild would need trusting again each time. The
`herdrCodexHooks` activation merges them into Codex's own
`~/.codex/hooks.json` (`scripts/codex-hooks.jq`), replacing an earlier entry
of ours under any directory or none, and marks them trusted
(`scripts/codex-trust-hooks.py`).

### Names and renaming

An agent has one name, drawn by `agent-list`'s rows and by `pane-header`
beside the terminal's address (`lib/name.js`): the `agent.name` label, else
the terminal's hc name, else its title, else its program.

Rename (in `agent-list`'s and `pane-menu`'s menus) sets `agent.name`. For
Codex and opencode that is all, and the label stays. Claude Code sets its
terminal's title to its session's name, so there the label is only a rename
Claude Code hasn't taken yet:

- **Workbench to Claude Code.** `herdr-claude-title`
  (`scripts/claude-title.sh`), a hook on UserPromptSubmit and SessionStart,
  hands the label over as the hook's `sessionTitle`, which names the session
  as `/rename` does, and removes the label. So the session takes the name at
  the person's next message, or when it starts or resumes. Nothing is typed
  into the terminal, so a rename works while the agent is working, blocked or
  being kept warm.
- **Claude Code to the workbench.** A `/rename` changes the title, which the
  mods show at once when no label is in the way.
- **Both, before the next message.** The later one wins, at that message.
  Until then the mods show the workbench's name. The hook tells the order
  from `claude.title` (the session's name at the hook's last run, as JSON)
  and `agent.name_base` (the terminal's title when Rename was saved): the
  session was renamed after when its name is neither.
- A session never renamed shows the title Claude Code makes up for it. An
  empty Rename removes the label and leaves the session's name alone: a hook
  can't take a name away.
- The hook goes by its terminal, not its session: a second Claude Code
  started inside an agent's terminal (`claude -p` from a tool call) would
  take a waiting rename.

### Keep cache warm

A Claude Code pane's header has a switch, "Keep cache warm" (`lib/warm.js`
decides what it shows). It sets `agent.keep_warm` on the terminal, so the
switch is seen from every window and ends with the terminal.
`herdr-claude-keep-warm` (`scripts/claude-keep-warm.sh`, a user service on
Linux and a launchd agent on macOS, installed with the workbench) does the
work on the terminal's own machine, with the app open or closed. Every 30 s
it looks at this machine's switched-on terminals. When an agent is idle or
done and its cache has 10 minutes or less left, it types `/btw reply with: ok`
and closes the answer with Esc. The side question reads the conversation's
cache, which renews it for another hour; nothing joins the conversation and
the agent's status doesn't change. Each refresh re-reads the whole context
at the cached rate and counts toward the plan's usage, about every 50
minutes for as long as the switch is on. Nothing turns it off but the person.

- **1 h caches only.** A session billed by API key or on usage credits has a
  5-minute cache (`agent.cache_ttl=5m`): the switch can't be turned on there.
- **It types into a terminal a person may be using.** It acts only when the
  screen ends in Claude Code's prompt box. Text in the box that changed since
  the last pass is left alone. A placeholder or suggested prompt reads like a
  typed draft in `hc read`, so it types `.` and Backspace to tell them apart.
  A real draft is set aside with Claude Code's stash (Ctrl+S), which gives it
  back once the question is submitted; a draft is never stashed over another.
- **After two refreshes in a row that didn't move `agent.cache_until`** it
  sets `agent.warm_failed`, which `agent-list` shows once as a notification,
  and leaves the terminal alone until the expiry changes (the agent's next
  turn) or the switch is turned off and on.
- The screen texts it matches (the rules around the prompt box, `❯`,
  `› stashed`, `Answering…`, `Esc to close`) are Claude Code 2.1.322's, and
  `tests/scripts/run.sh` holds the screens it was written against. A version
  that draws the prompt box differently gets nothing typed. One that draws
  the answer panel differently gets the question, but the answer is left
  open and counts as a failed refresh.

### The plan-limit file

`custom.herdr.workbench.claudeLimitsFile.enable` (off by default; on only on
BrightFalls) also records Claude Code's plan-limit reading, the `rate_limits`
its status line receives, for a desktop shell to show. The statusLine command
becomes `claude-statusline-limits` (`scripts/claude-limits.sh`), which writes
`$XDG_RUNTIME_DIR/desk/claude-limits.json` and then hands the same input to the
unchanged `claude-statusline`. The file is one JSON line holding `written_at`
and the `seven_day` and `five_hour` windows (`null` when absent), each with
`used_percentage`, `resets_at`, `evidence_at`, its own `written_at` and `kind`,
and nothing else. Every session on the machine writes it, each with the
reading its own session last received, and an idle session keeps reporting
the figure from its last API answer (status lines re-run every 10 s), so each
window is merged with the file's by **newest evidence**. A reading's evidence
time is the modification time of the session's transcript
(`transcript_path` in the status line's input), written at about that
answer; the script takes the mtime and never opens the file. A time in the
future counts as now; no transcript, or one that cannot be stat'ed, is no
evidence, older than any. `kind` is `fresh` when the evidence was at most
60 s old at the write, else `stale`. A window missing from the input keeps
the file's. Two `resets_at` at most 60 s apart are the same window (a
reading can give one window's a few seconds apart; the shortest window is
300 minutes): only one more than 60 s later wins, as a new window,
and only one more than 60 s earlier is ignored. The same window goes to the
newer evidence even when its value is lower, since a limit can be reset
within a window, and the winner is written with its own `resets_at`.
Evidence times at most 60 s apart, or both absent, are a tie, and a tie
keeps the higher value: two live sessions answering seconds apart report
slightly different figures, and 60 s is far above that gap and far below the
hours between an idle session's answer and a live one's. A file from before
`evidence_at` is read as having no evidence and rewritten in the new form at
the next call. One weakness: a session writes the user's next prompt to its
transcript before the API answers, so for that moment it reports its old
figure with a new mtime and can win; its own status line corrects it once
the answer arrives. The file is replaced atomically when the merged windows
differ from it, and otherwise only every 900 s while a session reports the
current window (a `resets_at` within 60 s of the merged one's), so
`written_at` is the last time a running session reported it. An input with no usable
window never writes, and the file is never deleted. Read-merge-write is not
locked: two sessions writing at once can lose one update, until the loser's
next status line. It is written inside and outside herdr terminals;
every failure is silent. BrightFalls's Quickshell token panel and bar item read
it (`hosts/BrightFalls/users/matteo/hyprland/`). With the option off, the
statusLine command is `claude-statusline` as before.

All Claude Code hooks are in one definition in `core.nix`:
`custom.claude-code.extraSettings` is `types.attrs`, which merges shallowly,
so a `hooks` set anywhere else would replace them.

## Mods

`workbench.nix` builds every folder in `mods/` into one derivation, following
symlinks, and activation copies each enabled mod into
`~/.config/herdr-app/mods/<name>`, replacing the folder whole.

- **Shared code** lives in `lib/`. A mod that uses it has a committed symlink
  `mods/<name>/lib -> ../../lib` and imports `./lib/agents.js`. The installed
  copy holds a real `lib/` folder.
- **`lib/hosts.js` isn't in the repo.** It is generated per machine from
  `lib/ssh-mesh.nix` (repo root) and added to each installed `lib/`. It
  exports `SELF` (this machine's mesh principal), `HOSTS` (every mesh host
  by principal: label, device, OS). `space-cards` draws `HOSTS`. A new mesh host needs an entry in
  `hostKinds` in `workbench.nix`, which an assertion enforces.
- **Back to the default branch** (`lib/back.js`, `mods/back-to-master`):
  `space-menu`'s item opens the dialog. Its probes and the run are each one
  `sh -c`, so a remote space costs one round trip per step. The run (save,
  switch, fast-forward, delete) must stay one exec: Esc closes the dialog
  even while it runs, and that ends the dialog's tasks but not an exec
  already started.
- **Trying a change live:** edit the installed copy under
  `~/.config/herdr-app/mods/`. The app reloads a mod on save, and a broken
  save keeps the old version running and shows up in `herdr-app status`'s
  `errors`. `herdr-app check <mod folder>` loads a mod once and reports
  what's wrong. Copy the change back into the repo: the next activation
  replaces the installed folder.
- **Adding a mod:** create `mods/<name>/` with `main.js` and `mod.json`,
  plus `ln -s ../../lib mods/<name>/lib` if it uses `lib/`. Add it to
  `enabledMods` in `workbench.nix`, and to `layout.nix` if it takes a place in
  the layout. New files must be `git add`ed before a build sees them.

## The layout

`layouts/workbench.json` is a snapshot of herdr-app's shipped `main` layout.
Shipped layouts live in the app binary, so they can't be referenced. One
edit is made in the snapshot itself: the `agents` block draws `agent-list`.
`layout.nix` makes the rest at build time:

- `pane-header` as `main`'s pane header and `pane-menu` as `terminal_menu`;
- `nixpkgs-prs` appended to `work-body`, when enabled;
- `space-cards` in place of the `spaces` block's mod, when enabled;
- `status-bar` in place of the `status` block's `workspace-status`.

Activation installs the result as `layouts/workbench.json`, first saving a
hand-edited copy to `~/.local/state/herdr-app/`. Once per machine it also
switches to the layout (`herdrWorkbenchLayout`).

**Re-snapshotting** after upstream changes `main`:

1. `herdr-app do layout.clone --name main --as main-snapshot` writes
   `~/.config/herdr-app/layouts/main-snapshot.json`. It also switches the
   window to the copy; switch back afterwards.
2. Copy it over `layouts/workbench.json`, set the `agents` block's
   `content.mod` back to `agent-list`, and delete the clone.
3. `nix build .#checks.x86_64-linux.herdr-layout` fails by name if a node
   `layout.nix` or the mods rely on (`main`, `work-body`, `spaces`, `agents`,
   `sidebar`, `status`) was renamed.

## Tests

```bash
nix build .#checks.x86_64-linux.herdr-layout   # layout.nix, every option combination
nix build .#checks.x86_64-linux.herdr-js       # lib/ and the mods' pure logic; each mod parses
nix build .#checks.x86_64-linux.herdr-scripts  # hook scripts and the hooks.json merge
```

CI runs all three on pull requests (the `herdr-tests` job in
`.github/workflows/pr-build.yml`). They also exist for `aarch64-darwin`.

- **JS** (`tests/js/*.test.mjs`, `node --test`). `tests/js/hooks.mjs`
  resolves `herdr`, `gpui-kit` and `gpui-base`, which only the app provides,
  to stubs in `tests/js/stubs/`. A test installs handlers with
  `mock({ exec, hc, ... })` and inspects `calls`. A herdr function with no
  handler throws, so a test can't depend on one by accident. To run them
  locally: `cd tests/js && node --import ./hooks.mjs --test`.
  `back.test.mjs` is the exception: its `exec` runs real `sh` and `git` in
  throwaway repos, so `lib/back.js`'s scripts are tested against git itself
  (the check has `git` on its PATH).
  The gpui stub builds a tree of the elements a view draws, with their ids and
  `on_*` handlers, and `find(root, id)` from `gpui-kit` looks one up, so a test
  can render a view and click it. `lib/hosts.js` resolves to
  `stubs/hosts.mjs`. `space-cards.test.mjs` does this for every "+" that makes
  a space.
- **Scripts** (`tests/scripts/run.sh <scripts dir>`) run each hook with a fake
  `hc` that logs its arguments. `claude-limits.sh` runs with a fake `date` (the
  clock), a fake `npx` (the renderer) and a temporary `XDG_RUNTIME_DIR`.
  `claude-keep-warm.sh` runs against an `hc` that plays one Claude Code
  terminal: its screen changes with the keys and text sent to it.
  `claude-title.sh` runs against an `hc` that answers `hc get` with the
  labels a case gives it.
- **Not covered:** how anything looks (there's no headless gpui), and the
  parts of `status-bar/main.js` that need the live app. For those, use
  `herdr-app check` and `herdr-app shot`.
