# herdr module

Home Manager module for [Herdr](https://github.com/herdrdev): `herdr-core`
(`hc`, the server that runs terminals and agents) and the `herdr-app` desktop
app with the `workbench` layout and its mods. Options are under
`custom.herdr`; see `default.nix` and `workbench.nix` for each one's
description.

| Path | What |
|------|------|
| `default.nix` | Imports the rest; `enable`, `desktop` |
| `core.nix` | herdr-core, the app, its theme, and Claude sessions resumed after a reboot. Holds every Claude Code hook (see below) |
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
| `agent.cache_until` | `claude-statusline.sh` only | `agent-list` (cache-expiring flag) |
| `agent.ask` | `agent-ask.sh` (Claude and Codex hooks), `opencode-labels.js` | `agent-list` |
| `agent.ask_detail` | `agent-ask.sh` | no mod reads it yet |
| `claude.session`, `codex.session`, `opencode.session` | `claude-session.sh`, `codex-labels.sh`, `opencode-labels.js` | `lib/agents.js` (restart on a newer version); `claude-resume.sh` (resume after reboot) |
| `agent.name` | the person, from `agent-list`'s or `pane-menu`'s Rename | `agent-list`, `pane-menu` |

Codex hooks and `herdr-agent-ask` are on `PATH` under fixed names, not store
paths: Codex trusts a hook by its definition, so a path that changed on every
rebuild would need trusting again each time. The `herdrCodexHooks` activation
merges them into Codex's own `~/.codex/hooks.json` (`scripts/codex-hooks.jq`)
and marks them trusted (`scripts/codex-trust-hooks.py`).

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
  by principal: label, device, OS, nix-darwin or not) and `FLEET` (this
  machine, then the hosts it may log into). `fleet` lists `FLEET`;
  `space-cards` draws `HOSTS`. A new mesh host needs an entry in
  `hostKinds` in `workbench.nix`, which an assertion enforces.
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
- `fleet` and `nixpkgs-prs` appended to `work-body`, each when enabled;
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
nix build .#checks.x86_64-linux.herdr-js       # lib/ and the mods' pure logic
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
- **Scripts** (`tests/scripts/run.sh <scripts dir>`) run each hook with a fake
  `hc` that logs its arguments.
- **Not covered:** drawing (there's no headless gpui), and the parts of
  `fleet/main.js`, `space-cards/main.js` and `status-bar/main.js` that need `lib/hosts.js` or the
  live app. For those, use `herdr-app check` and `herdr-app shot`.
