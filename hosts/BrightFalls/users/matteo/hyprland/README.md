# BrightFalls desktop config (Hyprland session)

Nix pins the packages. The desktop's config files are ordinary writable files
under `~/.config`, so they can be edited and reloaded with no rebuild. This
directory holds the canonical copy.

## Two layers

| Directory | Installed at | How |
|-----------|--------------|-----|
| `defaults/` | `~/.local/share/desk/` | Read-only links into the store (`xdg.dataFile`). Holds what a live edit must not be able to break: `hypr/rescue.lua` (terminal, reload and exit binds) and `hypr/theme.lua` (reads the palette, with built-in fallbacks). |
| `user/` | `~/.config/` | Every file is copied, at the same relative path, as a regular 0644 file by `desk-sync activate`. This tree is the manifest: add a file here and it is installed, with no list to update in `default.nix`. |

`user/hypr/hyprland.lua` loads each user file with `require`, which Hyprland
isolates: an error in one file shows in `hyprctl configerrors` and the rest
still load. It loads `~/.local/share/desk/hypr/rescue.lua` last by absolute
path, inside `pcall`, so the user files still load if that directory is
missing. `~/.config/uwsm/env-hyprland` stays a read-only Nix-managed file.

`user/desk/theme.json` is the palette (colours and fonts), read by both
Hyprland (through `hypr/theme.lua`) and Quickshell (`quickshell/Theme.qml`).
Each falls back to built-in Dracula values for a missing file, a bad value or
a missing key.

## Quickshell

`user/quickshell/` is the desktop shell, run as the `quickshell` user service
(Hyprland session only) with `qs`, which loads `~/.config/quickshell/shell.qml`.
`shell.qml` lists the components, one line each; a new component is a new file
beside it and a line there, and a component's own parts go in a directory
named after it (`import qs.<dir>`). `Theme.qml` is the palette and fonts
they share. Every surface is drawn the same way: `Theme.background` at 0.96
alpha, a 1 px `Theme.purple` border, 10 px corners.

- `Launcher.qml` (Super+Space, `qs ipc call launcher toggle`), with
  `Apps.qml` (the applications it lists and its search). Apps launch as
  `uwsm app -- <id>.desktop`, each in its own systemd scope.
- `Bar.qml`: a floating rounded strip on every monitor, 6 px
  from the top, left and right edges and 30 px tall including its border.
  Whatever sits under it starts 44 px from the top of the monitor.
- `Notifications.qml` (parts in `notifications/`): the notification daemon,
  in place of mako. Popups sit under the bar at the top right of the
  monitor focused when the first one appears, 380 px wide, with a red
  border when critical. Notifications from one app stack into a deck that
  opens into a list while hovered. Low urgency goes after 5 s, normal after
  8 s, critical stays; a timeout from the sender counts, up to 30 s, and
  the countdown stops while the pointer is over the deck. Left click runs
  the default action, else dismisses; right or middle click dismisses.
  There is no history: a dismissed or expired notification is gone.
  Super+comma dismisses the newest, Super+Shift+comma all of them,
  Super+Ctrl+comma toggles do not disturb, under which only critical ones
  show and the rest are dropped (`qs ipc call notifications dismissNewest`,
  `dismissAll`, `toggleDnd`). Do not disturb survives a Quickshell reload,
  not a restart.
- `Osd.qml`: the on-screen display, a pill under the bar on the focused
  monitor.
- `Cheatsheet.qml` (Super+K, `qs ipc call cheatsheet toggle`): the
  keybinding cheat sheet, a modal on the focused monitor with the binds in
  groups over three columns and a filter. It lists what the running Hyprland
  has bound (`hyprctl -j binds`, read when it opens and after each config
  reload), so a live edit shows after `hyprctl reload`. A bind is on it when
  it has a description, `"<Group>: <Description>"`: in `hypr/bindings.lua`
  write it with the local `bind(group, keys, description, dispatcher, opts)`
  helper, not bare `hl.bind`. Groups appear in the order of their first
  bind, binds with the same description share a row (the digit row and the
  four arrows collapse to one keycap), and a description with no group goes
  under "Other". `rescue.lua` has its own copy of the helper.

## Activation

Home Manager runs `desk-sync activate` after linking the generation, at boot
(comin) and on `nixos-rebuild switch`. It never reloads anything. For each
file in the manifest, with the hash of the store copy it last installed kept
in `~/.local/state/desk/hashes/<path>`:

| Live file | Result |
|-----------|--------|
| absent | store copy installed, hash recorded |
| a symlink into `/nix/store` (left by an older generation) | replaced with a writable copy, hash recorded |
| identical to the new store copy | hash recorded |
| matches the recorded hash (not edited since it was installed) | replaced with the new store copy, hash recorded |
| anything else (edited live) | left untouched; a new store copy goes to `~/.local/state/desk/incoming/<path>`, hash not recorded |

A file dropped from the manifest is left in place, and activation says so
once. One file failing is reported and does not stop the others or Home
Manager's activation.

## desk-sync

- `desk-sync status [-v]`: each manifest file as `clean`, `edited`,
  `incoming-pending` (edited, and a newer store copy is waiting) or `missing`.
  `-v` adds a diff from the store copy to the live file.
- `desk-sync reset <path>|--all`: put the store copy back, record its hash,
  drop its incoming copy, and print the reload command. `<path>` is relative to
  `~/.config` (`hypr/bindings.lua`) or the live path.
- `desk-sync pull <checkout-dir>`: copy edited live files into
  `<checkout-dir>/hosts/BrightFalls/users/matteo/hyprland/user/` and print
  `git status --short` for that subtree. No commit. A file with something that
  looks like a secret (a private key block, `password=`/`token:`-style
  assignment, a bearer token, a long key-like string) is not copied; the file
  and line are named and it exits 1.

`desk-sync` knows the manifest of the generation it was built with, which is
the one activation installed.

## Editing live (agents)

1. Edit the file under `~/.config` (for example `~/.config/hypr/bindings.lua`).
2. `hyprctl reload`. Hyprland does not reload on its
   own: `disable_autoreload` is set. Quickshell does: saving a file under
   `~/.config/quickshell` reloads it, and a "reloaded" or "failed" popup says
   which. Edits to `~/.config/desk/theme.json` reach Quickshell without a
   reload. If Quickshell is stuck, `systemctl --user restart quickshell`.
3. `hyprctl configerrors` must print nothing. Quickshell's errors and
   warnings: `qs log` (or `journalctl --user -u quickshell`); the line and
   column of a QML error are in the `caused by @File.qml[line:col]` line.
4. To back out: `desk-sync reset hypr/bindings.lua`, then reload.
5. To keep it: `desk-sync pull <checkout>`, review and commit there. After the
   next deploy the live file matches the store copy again and is `clean`.

A new file has to be added under `user/` in the repo and deployed before
`desk-sync` knows it.

Tests: `nix build .#checks.x86_64-linux.desk-sync` (runs `tests/run.sh`
against a temporary HOME).
