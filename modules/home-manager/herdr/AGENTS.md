# Agent instructions: herdr module

How to change this module: its mods, their look, how they're tested and how they
reach the app. Architecture (files, terminal labels, Teleport, the layout) is
in [README.md](README.md); read it first. Repo-wide rules are in the root
`AGENTS.md`.

Before writing a mod, run `herdr-app --skill` and read the installed API guide,
`~/.config/herdr-app/AGENTS.md`, with `herdr.d.ts` and `gpui-kit.d.ts` beside
it. They are generated for the installed version and are the API's source of
truth.

## Design reference

The **Herdr** design canvas is the visual reference:
<https://claude.ai/artifact/T6JAEvwygm7noNLeWec451> (private to the owner).

- Its **Design system** page draws what the mods render, from their code:
  - Foundations: theme tokens with their Dracula values, type, shape, icons;
  - Spaces sidebar (`space-cards`);
  - Agents and pane headers (`agent-list`, `pane-header`);
  - Menus and dialogs.
- Its **Teleport** page holds every built state: menus, sidebar, the
  dialog, and the flow of what runs where.
- Its **Side panels** page holds an overview of `fleet` and `nixpkgs-prs`,
  then a section per `fleet` part, each in every state: Deploy, Watch, and
  its menus and dialogs.
- Its **PR and CI status** page holds the status bar (`status-bar`) with
  the focused terminal's branch, PR and checks, and the two-line sidebar
  rows, as built.
- A feature or mod with many states gets its own page or section like
  these, not a corner of a Design system artboard.

The canvas is the source of truth for design, and it changes only through an
accepted draft. It shows only the current state: no mockups, no earlier
versions, no "before" comparisons. Those stay on the draft canvas.

1. **Draft first.** For any change to what a mod draws (new mod, new state,
   new row, restyle), make a draft before writing code.
   - The draft is a *separate* Design canvas, titled `Herdr draft: <change>`.
   - It holds the new or changed artboards, drawn in the main canvas's tokens
     and patterns, showing every state the change adds.
   - Present the draft's link to the user and wait for acceptance. Revise the
     draft until it's accepted. Never edit the main canvas for an unaccepted
     change.
2. **Build to the draft.** Implement what the accepted draft shows. Once
   built, check it in the sandbox (Testing, step 6 below). Where the build
   had to differ, say so in your report.
3. **Merge what was built.** Bring the main canvas to the built state:
   - the feature's own page (create it if new), with every state as built
     ("As built ·"), from sandbox screenshots where they help;
   - every Design system artboard the change affects (Foundations for a new
     token or icon, Sidebar, Menus, and so on);
   - remove or redraw whatever the change made untrue: superseded boards,
     states and notes. Nothing on the canvas may describe how it used to be.

Rules the mods follow, and new ones should too:

- **Theme tokens, never hexes.** Use `t.chrome`, `t.popover`, `t.dim`,
  `t.ansi5` and so on, so every theme works. The only fixed hexes are the
  space-avatar palette (`MARK` in `space-cards` and `agent-list`) and the
  avatar letter `#ffffff`.
- **Fixed meanings:**
  - `ansi2` is ahead, connected or OK;
  - `ansi3` is behind or a caution;
  - `ansi5` is Teleport;
  - `blocked` is an error or "needs you";
  - `working`, `done` and `idle` are agent states only;
  - branch names are mono in `accent`.
- **Quiet by default.** A row shows a status marker only while something is
  going on (working spinner) or needs you (blocked or done dot). Idle shows
  nothing.
- **Sizes.**
  - Space row: 28 high, radius 6; 40 high with a branch line.
  - Menu item: 31 high (44 with a sub line), px 8, gap 9, radius 7, in a
    popup with p 5.
  - Dialog: p 18, title 15/600, buttons 32 high with radius 8. The primary
    button is `solid`; the secondary is `raised` with an `input` border.
  - Icons: 14 in menus, 12 in rows.
  - Fonts: UI is the settings' UI font (Geist); branches and paths are mono.
- **Known outlier:** the `teleport` dialog uses a 13 px title, 30/r7 buttons
  and a pink primary. Align it the next time it changes.
- **Copy:** plain words, sentence case, no exclamation marks. A disabled item
  says why in its hint ("needs you", "asleep").

## Making a mod

1. **Clone, don't edit, shipped mods.** Herdr owns `menu`, `spaces`,
   `worktree` and the rest, and replaces them at start. Copy what you need into
   `mods/<name>/`, as `pane-menu` and `space-menu` copy `menu`'s items.
2. **The folder.** Create `mods/<name>/main.js` (`export default class … extends
   View`) and `mod.json` (`{ "place": "none" }` for a layout block or overlay;
   add `"overlay": { width, height }` for a popup). Put assets beside them and
   reference them as `mods/<name>/<file>.svg`.
3. **Shared code goes in `lib/`.** Link it with `ln -s ../../lib mods/<name>/lib`
   and import `./lib/<file>.js`. Keep logic that isn't drawing in `lib/` or a
   sibling file with no gpui imports, so Node tests can load it.
   `lib/hosts.js` is generated per machine at build time (README › Mods), so
   it isn't in the repo.
4. **Install it.** Add it to `enabledMods` in `workbench.nix`, under the option
   that brings it. If it takes a place in the layout, add it to `layout.nix`
   and to `tests/layout.nix`. Document a new option in its `mkEnableOption`.
5. **`git add`** the new files before any `nix build`; the flake only sees
   tracked files.

## Testing

Work through these in order. A step that can't fail proves nothing, so for
each new test break the code once and watch the test fail before trusting it.

1. **Unit tests** (`tests/js/*.test.mjs`, `node --test`).
   - Run them with `cd tests/js && node --import ./hooks.mjs --test`.
   - `herdr`, `gpui-kit` and `gpui-base` resolve to stubs.
   - `mock({ exec, hc, … })` installs handlers, and `calls` records every call.
     A herdr function with no handler throws.
   - Test command sequences and their order. `tests/js/teleport.test.mjs`
     asserts nothing changes on the source before the target succeeds.
   - Use real input shapes: capture `hc get --json` or a Codex rollout line
     rather than inventing one.
2. **Script tests** (`tests/scripts/run.sh`). They run the hook scripts as
   `writeShellApplication` would (`set -euo pipefail`), with a fake `hc` on
   PATH.
3. **Flake checks.** Build `herdr-layout`, `herdr-js` and `herdr-scripts`:
   `nix build .#checks.x86_64-linux.<name>`. CI runs them on PRs
   (`herdr-tests` in `pr-build.yml`).
4. **Load check.** `herdr-app check <mod folder>` loads a mod and renders it
   once; a non-zero exit gives the error. Run it on the *built* folder
   (`herdr-mods` in the home-manager generation), which has `lib/` filled in,
   not on the repo folder.
5. **Refactors: diff against a baseline.** Before a change that should alter
   nothing visible, snapshot what the module produces. Do the same after, then
   diff modulo store paths:
   - `nix eval --json` of the herdr parts of each host's `home-manager.users.<u>`
     (activation scripts, Claude settings, packages, units);
   - the files a simulated activation installs into a fake home (run the
     `herdrWorkbenchMods` / `herdrWorkbenchLayoutFile` script text with `run()`
     defined and paths rebased). Compare contents and modes.
6. **Live, in the sandbox.** `tests/e2e/sandbox.sh up <mods> <layout> [machine…]`
   starts a separate herdr-core session (here and on each machine named), a
   separate app home, and herdr-app on an Xvfb display. Your own window,
   terminals and spaces are never touched.
   - Run `. /run/user/$UID/herdr-e2e/env` to point the session at it.
   - Drive it with `herdr-app do <command>`, `click X Y [3]` (window
     coordinates, as `herdr-app shot` shows them; 3 is right-click) and
     `$XDO key Escape`.
   - Check `herdr-app status` (`errors` must be `[]`), and look at every
     `herdr-app shot <png>`.
   - Assert end results from outside the app: `git` on both machines, `hc ls`.
   - Use throwaway repos for features that write, never real ones. For
     machine-to-machine features, give the far clone the same path relative to
     home and the same `origin`.
   - Run `sandbox.sh down [machine…]` when done. Afterwards check
     `pgrep -af herdr-e2e` is empty and your real cores still list their
     terminals.
7. **Live, in your own window** (only after the above). Copy the built mod into
   `~/.config/herdr-app/mods/<name>` (back up the old folder first). The app
   reloads it on save; a broken save keeps the old version and shows in
   `status`. To prove a file is really loaded, break it once and watch
   `status` report it, then restore it.

Gotchas from doing this:

- **Socket paths are capped at 107 bytes.** Both `hc`'s
  (`$XDG_RUNTIME_DIR`) and the app's (`$HERDR_APP_HOME/herdr-app.sock`) go
  over the limit in a long scratch path. That's why the sandbox lives under
  `/run/user/$UID`.
- **Bare `nix fmt` hangs.** With no arguments it runs `nixfmt`, which waits on
  stdin. Always name files: `nix fmt -- <files>`.
- **Claude hooks live in one definition.** `custom.claude-code.extraSettings`
  is `types.attrs`, which merges shallowly: a second `hooks` set would replace
  the first. Every Claude hook is in `core.nix` (README).
- **Store machine names, not null, in data another machine reads.** "null =
  this computer" means something different on each machine.
- **`space.new` from a mod: name the machine.** Left out, `machine` is the
  focused space's machine, not this computer. Pass `""` for this computer, as
  `mods/teleport` does.
- **Closing an overlay ends its tasks.** A `cx.spawn` started by a dialog
  stops when the dialog closes, so a dialog that runs a job closes itself only
  once the job is done (`mods/teleport`).
- **`exec` limits.** It has a 30 s limit and no stdin. Wrap anything that
  needs a pipe, an env var or a temp index in `sh -c`, as the
  `lib/teleport.js` scripts do.

## Activation

Mods reach the app through Home Manager, never by hand-installing them.

1. **Build and verify.** Build the host's system
   (`nix build .#nixosConfigurations.<Host>.config.system.build.toplevel`) and
   eval the others, as the root `AGENTS.md` describes. Darwin hosts install
   the mods too.
2. **Switch.** On NixOS, `sudo nixos-rebuild switch --flake .#<Host>`; on
   macOS, `nix run nix-darwin -- switch --flake .#<Host>`. The activation
   scripts in `workbench.nix` then:
   - `herdrWorkbenchMods` replaces each enabled mod's folder in
     `~/.config/herdr-app/mods` with a copy, discarding hand edits. A mod that
     was turned off is left in place.
   - `herdrWorkbenchLayoutFile` writes `layouts/workbench.json`. A copy that
     was edited by hand is saved first to `~/.local/state/herdr-app/`.
   - `herdrWorkbenchLayout` switches to the workbench layout once per machine.
   - `herdrCodexHooks` merges and trusts the Codex hooks.
3. **Check.** `herdr-app status` must show `"errors": []`. Then look at a
   `herdr-app shot`. The running window reloads changed mods, so no restart is
   needed.
