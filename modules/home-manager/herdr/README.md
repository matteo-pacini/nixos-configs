# herdr module

Home Manager module for [Herdr](https://github.com/herdrdev): `herdr-core`
(`hc`, the server that runs terminals and agents) and the `herdr-app` desktop
app with the `workbench` layout and its mods. Options are under
`custom.herdr`; see `default.nix` and `workbench.nix` for each one's
description.

| Path | What |
|------|------|
| `default.nix` | Imports the rest; `enable`, `desktop` |
| `core.nix` | herdr-core, the app, its theme, Claude sessions resumed after a reboot, the keep-cache-warm mod for Claude Code, and the hook that hands a rename to Claude Code. Holds every Claude Code hook (see below) |
| `agent-labels.nix` | The terminal labels the mods draw, set from inside each agent (Claude statusLine, Codex hooks, opencode plugin) |
| `workbench.nix` | `workbench.*` options, the mod build and install, `lib/hosts.js`, the layout file and the first switch to it |
| `layout.nix` | Pure: which optional mods are on → the layout tree |
| `layouts/workbench.json` | Snapshot of herdr-app's shipped `main` layout |
| `mods/<name>/` | One herdr-app mod each: `main.js`, `mod.json`, assets |
| `claude-mods/keep-warm/` | A mod for Claude Code, not herdr-app: see [Keep cache warm](#keep-cache-warm) |
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
| `agent.cache_until`, `agent.cache_ttl`, `agent.cache_session` (the session they describe: a resumed one keeps them until its first request) | `claude-statusline.sh` only | `agent-list` (cache-expiring flag); `lib/warm.js` and the `herdr-keep-warm` mod (see below) |
| `agent.keep_warm` | the person, from `pane-header`'s switch; cleared by `claude-session.sh` when the session is quit, set again by `lib/agents.js` after a restart | `lib/warm.js` (`pane-header`, `agent-list`); the `herdr-keep-warm` mod |
| `agent.warm_state`, `agent.warm_failed` | the `herdr-keep-warm` mod; cleared by `claude-session.sh` when the session is quit | `lib/warm.js`: `pane-header` ("Refreshing", "Cache cold"), `agent-list` (the failure notification) |
| `agent.ask` | `agent-ask.sh` (Claude and Codex hooks), `opencode-labels.js` | `agent-list` |
| `agent.ask_detail` | `agent-ask.sh` | no mod reads it yet |
| `claude.session`, `codex.session`, `opencode.session` | `claude-session.sh`, `codex-labels.sh`, `opencode-labels.js` | `lib/agents.js` (restart on a newer version); `claude-resume.sh` (resume after reboot) |
| `agent.name`, `agent.name_base`, `agent.name_session` | the person, from `agent-list`'s or `pane-menu`'s Rename (`lib/name.js`); removed by `claude-title.sh` once Claude Code has the name, or when another session runs there | `lib/name.js` (`agent-list`, `pane-header`, `pane-menu`); `claude-title.sh` |
| `claude.name` (the session's name; absent until it has one) | `claude-statusline.sh` | `lib/name.js` |
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

Claude Code is the exception to "else its title". It makes a title up for a
session nobody named, and the mods never show that one: after the label and
the hc name comes the session's own name (`claude.name`, which Claude Code's
status line reports once the session has one), else "Claude Code".

Rename (in `agent-list`'s and `pane-menu`'s menus) sets `agent.name`. For
Codex and opencode that is all, and the label stays. For Claude Code the
label is only a rename the session hasn't taken yet:

- **Workbench to Claude Code.** `herdr-claude-title`
  (`scripts/claude-title.sh`), a hook on UserPromptSubmit and SessionStart,
  hands the label over as the hook's `sessionTitle`, which names the session
  as `/rename` does, and removes the label. So the session takes the name at
  the person's next message, or when it resumes. Nothing is typed into the
  terminal, so a rename works while the agent is working, blocked or being
  kept warm.
- **A rename is for one session.** Rename records the session running in the
  terminal (`agent.name_session`, from `claude.session`), and the hook gives
  the name to that session only. Any other session there, a new chat after
  quitting or `/clear`, or a different one resumed, removes the label and is
  not named. A rename with no session recorded goes to whichever runs next.
- **Claude Code to the workbench.** A `/rename` shows in the mods at the
  status line's next run, within about 10 s, when no label is in the way.
- **Both, before the next message.** The later one wins, at that message.
  Until then the mods show the workbench's name. The hook tells the order
  from `claude.title` (the session's name at the hook's last run, as JSON)
  and `agent.name_base` (the terminal's title when Rename was saved): the
  session was renamed after when its name is neither.
- The Rename dialog starts from the session's name, empty for a session never
  named. An empty Rename removes the label and leaves the session's name
  alone: a hook can't take a name away.
- **`/clear` keeps the name.** Claude Code itself carries a session's name
  into the chat a `/clear` starts. Nothing here can remove it; `/rename` in
  the new chat replaces it.
- The hook goes by its terminal: a second Claude Code started inside an
  agent's terminal (`claude -p` from a tool call) is another session there,
  so it removes a waiting rename.
- A machine whose status line predates `claude.name` shows its named
  sessions as "Claude Code" until it is rebuilt.

### Keep cache warm

A Claude Code pane's header has a switch, "Keep cache warm" (`lib/warm.js`
decides what it shows). It sets `agent.keep_warm` on the terminal, so the
switch is seen from every window. It ends with the session: quitting Claude
Code (`/exit`, Ctrl+C twice, `/logout`) turns it off, in the same hook that
forgets the session (`scripts/claude-session.sh`), so a session started in
that terminal later begins with it off. It stays on where the session
carries on: across `/clear`, across a kill or shutdown (the session is
resumed, switch and all), and across a restart on a new version, which sets
it again after resuming (`lib/agents.js`).

The work is done inside the Claude Code session, by a Claude Code mod,
`herdr-keep-warm` (`claude-mods/keep-warm`). `core.nix` copies it to
`~/.claude/herdr-mods/keep-warm` and names that folder in
`CLAUDE_CODE_PLUGIN_DIRS`, in the `env` of Claude Code's settings, so every
session loads it, however it was started. Outside a herdr-core terminal, and
in one whose switch is off, it does nothing.

While the switch is on and the session has sat idle for 25 minutes since its
last turn or the last refresh, the mod asks a one-word question with
`$.model.fork`. A fork repeats the conversation's last request, so it reads
the conversation's prompt cache, which renews it; nothing joins the
conversation, nothing is typed into the terminal and the agent's status
doesn't change. Each refresh re-reads the whole context at the cached rate
and counts toward the plan's usage, for as long as the switch is on. Only
the person turns it off, by the switch or by quitting the session.

- **1 h caches only.** A session billed by API key or on usage credits has a
  5-minute cache (`agent.cache_ttl=5m`): the switch can't be turned on there.
- **25 minutes, not "shortly before the expiry".** After a refresh Claude
  Code counts its expiry an hour on whether or not the refresh reached the
  cache, so `agent.cache_until` can't time the next one.
- **It checks what each refresh did.** A fork reports how much of the
  conversation the cache served. One that wrote the conversation again found
  the cache gone: the mod sets `agent.warm_failed`, which shows the switch
  as "Cache cold" and `agent-list` shows once as a notification, and stops
  until the agent's next turn. Two refreshes with no answer do the same.
  It doesn't refresh a cache whose expiry has passed either.
- **A session started before the mod was installed doesn't have it.** Its
  switch counts down and goes cold. Restarting the agent (the OUTDATED
  button, or `/exit` and `claude --resume`) loads it.
- Mods need Claude Code 2.1.287 or later. The mod's decisions are in
  `hooks/logic.js`, which `tests/js/keep-warm.test.mjs` covers, along with
  `register.ts`'s handling of the failure label, against a stand-in engine.
  The rest of `register.ts` only runs in Claude Code
  (`claude --plugin-dir claude-mods/keep-warm` loads it from the repo, and
  `claude plugin validate` checks it).

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
  `claude-title.sh` runs against an `hc` that answers `hc get` with the
  labels a case gives it.
- **Not covered:** how anything looks (there's no headless gpui), and the
  parts of `status-bar/main.js` that need the live app. For those, use
  `herdr-app check` and `herdr-app shot`.
