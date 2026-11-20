# BrightFalls desktop config (Hyprland session)

Nix pins the packages. The desktop's config files are ordinary writable files
under `~/.config`, so they can be edited and reloaded with no rebuild. This
directory holds the canonical copy. This file says what each piece is and how
it works; how to work on it (process, testing, safety rules, code map, open
work) is in [AGENTS.md](AGENTS.md).

## Contents

- [The session](#the-session)
- [Two layers](#two-layers)
- [Activation](#activation)
- [desk-sync](#desk-sync)
- [Editing live](#editing-live)
- [Quickshell](#quickshell): [Launcher](#launcher), [Bar](#bar),
  [Notifications](#notifications), [OSD](#osd), [Cheat sheet](#cheat-sheet),
  [Session menu](#session-menu), [Polkit dialog](#polkit-dialog),
  [Network panel](#network-panel), [Audio panel](#audio-panel),
  [Calendar panel](#calendar-panel), [Calendar big view](#calendar-big-view),
  [Calendar reminders](#calendar-reminders),
  [System panel](#system-panel), [Bluetooth panel](#bluetooth-panel),
  [Office panel](#office-panel), [Fleet panel](#fleet-panel),
  [Tailscale panel](#tailscale-panel), [Token panel](#token-panel),
  [Tray menu](#tray-menu)
- [Wallpaper](#wallpaper)
- [Lock screen](#lock-screen)
- [single-monitor](#single-monitor)
- [Calendar events](#calendar-events) (the sync behind the calendar)
- [Office: desk-mqtt](#office-desk-mqtt) (the helper behind the office panel)
- [Fleet: desk-fleet](#fleet-desk-fleet) (the helper behind the fleet panel)
- [Tokens: desk-tokens](#tokens-desk-tokens) (the helper behind the token
  panel)
- [Tailscale: status and mesh hosts](#tailscale-status-and-mesh-hosts) (the
  decisions behind the Tailscale panel)
- [Tests](#tests)

## The session

greetd starts the session on VT 1 with `uwsm start -e -D Hyprland
hyprland.desktop`, the command of `hyprland-uwsm.desktop` (`desktop.nix`).
The first login of each boot is automatic, with no password. After a
logout, or if the
session ends, tuigreet asks for the password on VT 1 and starts the same
session. The plain `hyprland.desktop` stays installed for `uwsm start`,
with `NoDisplay` so no session chooser offers it
(`desktop-hyprland.nix`). `~/.config/uwsm/env-hyprland` is a read-only Nix-managed
file that points `AQ_DRM_DEVICES` at the udev links `/dev/dri/dgpu` and
`/dev/dri/igpu`, and sets `XCURSOR_THEME` and `XCURSOR_SIZE` from
`home.pointerCursor` (`users/matteo/desktop.nix`): UWSM sources only
`/etc/profile` and `~/.profile`, so Home Manager's session variables never
reach the session.

There is no other desktop. The services the session's apps rely on are
declared in `hosts/BrightFalls/desktop.nix`: gnome-keyring (secret service)
and gcr-ssh-agent (`SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh`), gvfs, udisks2,
upower, dconf, the portals (`hyprland` first, `gtk` for the file chooser
and settings, `gnome-keyring` for secrets), and the apps that stay:
Nautilus, Loupe, Papers, File Roller, Seahorse. GTK and Qt look, the
cursor (Dracula, XCursor only, 24 px), the dark
colour scheme and the default apps (`mimeapps.list`, a read-only link) are
in `users/matteo/desktop.nix`.

- Workspaces 1 to 5 belong to DP-1 and 6 to 10 to DP-2 (`hypr/monitors.lua`,
  matched by `workspaceMonitors` in `quickshell/Bar.qml`); Super+1 … Super+0
  focus them, Super+Shift+1 … 0 move a window there. A config reload does not
  move existing workspaces; a login or a monitor reconnect does.
- Game mode, Super+Ctrl+G: DP-2 off, no animations or blur; again to undo
  (that reloads the config). Workspaces 6 to 10 sit on DP-1 meanwhile.
- Games (`steam_app_<id>` or `*.exe` classes, `hypr/rules.lua`) go real
  fullscreen on DP-1 with tearing allowed, the game content type (direct
  scanout) and the pointer confined.
- `defaults/hypr/rescue.lua` keeps Super+Return (terminal), Super+Shift+R
  (reload), Super+Shift+Escape (exit, `uwsm stop`) and Super+Shift+D
  (restore the monitors, see [single-monitor](#single-monitor)) bound even
  when `bindings.lua` is broken.
- logind ignores the sleep key and a short press of the power key, which
  opens the session menu instead; a long press still powers off.

## Two layers

| Directory | Installed at | How |
|-----------|--------------|-----|
| `defaults/` | `~/.local/share/desk/` | Read-only links into the store (`xdg.dataFile`). Holds what a live edit must not be able to break: `hypr/rescue.lua` (terminal, reload, exit and restore-monitors binds) and `hypr/theme.lua` (reads the palette, with built-in fallbacks). |
| `user/` | `~/.config/` | Every file is copied, at the same relative path, as a regular 0644 file by `desk-sync activate`. This tree is the manifest: add a file here and it is installed, with no list to update in `default.nix`. |

`user/hypr/hyprland.lua` loads each user file with `require`, which Hyprland
isolates: an error in one file shows in `hyprctl configerrors` and the rest
still load. It loads `~/.local/share/desk/hypr/rescue.lua` last by absolute
path, inside `pcall`, so the user files still load if that directory is
missing.

`user/desk/theme.json` is the palette (colours and fonts), read by both
Hyprland (through `hypr/theme.lua`) and Quickshell (`quickshell/Theme.qml`).
Each falls back to built-in Dracula values for a missing file, a bad value or
a missing key. A colour must be `#` plus exactly six hex digits (QML and
Hyprland read an alpha digit pair differently); a font must not be blank.

Nix also generates read-only data the shell shows, under
`~/.local/share/desk/` (`desktop-hyprland.nix`, `calendar.nix` and
`default.nix`): `network/`, `audio/`, `system/` and `bluetooth/locked.json`
(values set in Nix, shown greyed with a `nix` tag), `calendar/source.json`
and `tailscale/hosts.json` (see [Tailscale: status and mesh
hosts](#tailscale-status-and-mesh-hosts)).

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
| anything else (edited live, including a symlink out of the store or a directory at the file's path) | left untouched; a new store copy goes to `~/.local/state/desk/incoming/<path>`, hash not recorded |

A file dropped from the manifest is left in place, and activation says so
once. One file failing is reported and does not stop the others or Home
Manager's activation.

## desk-sync

- `desk-sync status [-v]`: each manifest file as `clean`, `edited`,
  `incoming-pending` (edited, and a newer store copy is waiting) or `missing`.
  `-v` adds a diff from the store copy to the live file.
- `desk-sync reset <path>|--all`: put the store copy back, record its hash,
  drop its incoming copy, and print what applies it (`hyprctl reload` for
  `hypr/`; nothing for `quickshell/`, which reloads itself). `<path>` is
  relative to `~/.config` (`hypr/bindings.lua`) or the live path.
- `desk-sync pull <checkout-dir>`: copy edited live files into
  `<checkout-dir>/hosts/BrightFalls/users/matteo/hyprland/user/` and print
  `git status --short` for that subtree. No commit. Two kinds of file are
  not copied, each named on stderr, and pull exits 1 after copying the rest:
  - one whose newer store copy is waiting in `incoming/` (`incoming-pending`):
    it was edited on an older version, and the checkout may already hold the
    newer one. Merge by hand and `desk-sync reset` it, or reset it and edit
    again, then pull.
  - one where a line the edit added or changed (against the store copy, by
    `diff`'s alignment) looks like a secret: a private key block, a
    `password=`/`token:`-style assignment, a bearer token, or a run of 40 or
    more letters, digits, `_`, `+` or `=` holding at least one letter and
    one digit. Lines shipped in the store copy are not scanned. The message
    gives the live file's line numbers.

`desk-sync` knows the manifest of the generation it was built with, which is
the one activation installed. Files created live are not in it, so `status`
and `pull` do not see them until they are added under `user/` and deployed.

## Editing live

1. Edit the file under `~/.config` (for example `~/.config/hypr/bindings.lua`).
2. Hyprland does not reload on its own (`disable_autoreload` in
   `looknfeel.lua`): run `hyprctl reload`. Quickshell does: saving a file under
   `~/.config/quickshell` reloads it, a failed reload keeps the previous
   version running, and a "reloaded" or "failed" popup says which. Edits to
   `~/.config/desk/theme.json` reach Quickshell without a reload. `shell.qml`'s
   `//@ pragma` lines are read at startup only: after changing one,
   `systemctl --user restart quickshell`.
3. `hyprctl configerrors` must print nothing. Quickshell's errors and
   warnings: `qs log` (or `journalctl --user -u quickshell`); the line and
   column of a QML error are in the `caused by @File.qml[line:col]` line.
4. To back out: `desk-sync reset hypr/bindings.lua`, then reload.
5. To keep it: `desk-sync pull <checkout>`, review and commit there. After the
   next deploy the live file matches the store copy again and is `clean`.

## Quickshell

`user/quickshell/` is the desktop shell, one process run as the `quickshell`
user service (Hyprland session only, `Restart=on-failure`) with `qs`, which
loads `~/.config/quickshell/shell.qml`. `shell.qml` lists the components,
one line each; a new component is a new file beside it and a line there, and
a component's own parts go in a directory named after it (`import
qs.<dir>`). Its one pragma sets the icon theme (Adwaita); pragmas are read
at startup only, so changing one needs `systemctl --user restart quickshell`.
The service sets no PATH of its own: the commands the shell runs by name
come from the user's profile (`home.packages` in `default.nix`) or the
system's, `gdbus` from `glib.bin` among them.

`Theme.qml` is the palette and fonts every surface shares. Every surface is
drawn the same way: `Theme.background` at 0.96 alpha, a 1 px `Theme.purple`
border, 10 px corners. Layer-shell namespaces are `desk-<name>`. Pieces the
panels share (the measures in `Style.qml`, the panel registry, the card, key
hints, the "Set in Nix" loader and tag) are in `common/`; AGENTS.md has the
code map.

The nine drop-down panels (network, audio, calendar, system, Bluetooth,
office, fleet, tailscale, tokens) behave alike: each opens under its bar item on that bar's monitor (or the
focused monitor from a key or IPC), centred on the item and kept 6 px inside
the screen, with the item marked (purple, underlined) while open. Each takes
the keyboard, closes on Esc or a click outside, and opening one closes the
others (`common/Dropdowns.qml`); opening the launcher, the cheat sheet or the
session menu closes them too. Each has an IPC `toggle` (`qs ipc call
<target> toggle`). In the drop-downs and the centred modals a held key acts
once, except typing and the keys that move a selection, a slider or a page,
which repeat (the lock screen is not guarded).

| Component | Open | IPC target |
|-----------|------|------------|
| Launcher | Super+Space, the bar's menu button | `launcher` |
| Cheat sheet | Super+K | `cheatsheet` |
| Session menu | Super+Escape, power key | `session` |
| Network | Super+N, bar network icon | `network` |
| Audio | Super+A, middle click on bar audio item | `audio` |
| Calendar | Super+C, bar clock | `calendar` |
| Calendar, big view | Super+Shift+C, F in the calendar panel | `calendarfull` |
| System | Super+Y, bar temperature chip | `system` |
| Bluetooth | Super+B, bar Bluetooth glyph | `bluetooth` |
| Office | Super+O, bar light bulb and watts | `office` |
| Fleet | Super+G, bar server glyph and count | `fleet` |
| Tailscale | Super+V, bar Tailscale glyph | `tailscale` |
| Tokens | Super+U, bar item (pie and weekly percentage) | `tokens` |
| Notifications | Super+comma, Super+Shift+comma, Super+Ctrl+comma | `notifications` |
| Polkit dialog | opens on a request | `polkit` |
| Lock screen | Super+L, session menu | `lockscreen` |

### Launcher

`Launcher.qml` with `Apps.qml` (the applications it lists and its search);
parts in `launcher/`. A centred box near the top of the focused monitor.

- Apps: name matches rank prefix, then substring, then subsequence; the
  category on the right is the entry's first main category as written in the
  desktop file (`Network`, `AudioVideo`). Entries that `OnlyShowIn` /
  `NotShowIn` keep out of the current desktop (`XDG_CURRENT_DESKTOP`) are
  left out. Apps launch as
  `uwsm app -- <id>.desktop`, each in its own systemd scope.
- A query starting with `=` is a calculator (arithmetic, `^`, `%`, `sqrt abs
  round floor ceil`, `pi e`; its own parser in `launcher/Calc.qml`, no
  interpreter). One starting with `:` searches emoji by name
  (`launcher/Emoji.qml`). The prefix shows as a chip; Backspace on an empty
  query goes back to apps; Enter copies the result or emoji with `wl-copy`.
- `launcher/emoji.txt`, the emoji list, is read on first use. It is
  generated from the pinned `unicode-emoji` package by `gen-emoji.py`
  (beside this README, not installed), whose header has the command.
- Keys: type to filter, Up/Down or Ctrl+P/Ctrl+N, Enter, Esc; a click on a
  row launches it, a click outside closes.

### Bar

`Bar.qml`: a floating rounded strip on every monitor, 6 px from the top,
left and right edges and 34 px tall. Windows start 48 px from the top
(Hyprland's 8 px outer gap under it). Hidden on a monitor while it shows a
fullscreen window.

From left to right: a menu button (opens the launcher); the monitor's
workspaces (its five, plus any other that exists there; click or scroll to
switch); the focused window's title on that monitor; the clock (see
[Calendar panel](#calendar-panel)); then a gamepad while game mode is on
(read from Hyprland's `animations:enabled`), the tray (left click activates,
right click opens the item's menu, see [Tray menu](#tray-menu)), the token
item (a pie and the weekly plan-limit percentage, see [Token
panel](#token-panel)), the fleet item (a server glyph and the number of hosts that want attention, see
[Fleet panel](#fleet-panel)), the office item (a bulb and the sockets' total, see [Office panel](#office-panel)), the system chip (two temperatures, see
[System panel](#system-panel)), Bluetooth, the Tailscale item (see
[Tailscale panel](#tailscale-panel)), network (a small Wi-Fi mark beside
it while the radio is on and Wi-Fi is not what it shows, see [Network panel](#network-panel)), and audio. The audio item
shows the default output's name; left click cycles the output
(`audio-output-cycle`), right click mutes, the wheel sets the volume in 5 %
steps, middle click opens the audio panel; a red dot on it means an input
sends no signal.

### Notifications

`Notifications.qml` (parts in `notifications/`) is the session's
notification daemon.

- Cards sit under the bar at the top right of the monitor focused when the
  first one appears, 380 px wide, with a red border when critical. Cards from
  one app stack into a deck that opens into a list while hovered.
- Timeouts: low urgency 5 s, normal 8 s, critical never. A timeout from the
  sender counts, up to 30 s; 0 from the sender means never. The countdown
  stops while the pointer is over the deck.
- A body with line breaks shows up to eight lines, wrapped ones included;
  a body with none shows two.
- Left click runs the default action, else dismisses; right or middle click
  dismisses. Up to three other actions show as buttons.
- There is no history: a dismissed or expired notification is gone.
- Super+comma dismisses the newest, Super+Shift+comma all of them,
  Super+Ctrl+comma toggles do not disturb, under which only critical ones show
  and the rest are dropped (`qs ipc call notifications dismissNewest`,
  `dismissAll`, `toggleDnd`). Do not disturb survives a Quickshell reload, not
  a restart.
- While the screen is locked every card is held (see [Lock screen](#lock-screen)).

**Critical notifications.** Cards with critical urgency (hint `urgency` 2,
from any application) are drawn on their own surface on the Overlay layer
(`desk-notifications-critical`), which Hyprland draws above fullscreen
windows. It takes no keyboard and no input outside the cards, exists only
while a critical card is up, and has no fade (`no_anim` in `hypr/rules.lua`):
any Overlay surface on a game's monitor costs the game direct scanout and
tearing for as long as it exists. Critical cards never time out, so dismiss
them (Super+comma) to give that back. All other cards stay on the Top layer,
hidden under fullscreen.

### OSD

`Osd.qml`: a pill under the bar, centred on the focused monitor, for about a
second after a change: output volume and mute, microphone mute, the default
output changing (its name), Bluetooth turned on or off (or a failure to turn
it on or off, or no adapter). It takes no input and
does not show for the values present at startup. No IPC.

### Cheat sheet

`Cheatsheet.qml` (Super+K, `qs ipc call cheatsheet toggle`): a modal on the
focused monitor with the binds in groups over three columns and a filter.

- It lists what the running Hyprland has bound (`hyprctl -j binds`, read
  when it opens and after each config reload), so a live edit shows after
  `hyprctl reload`.
- A bind is on it when it has a description, `"<Group>: <Description>"`: in
  `hypr/bindings.lua` write it with the local `bind(group, keys, description,
  dispatcher, opts)` helper, not bare `hl.bind`. `rescue.lua` has its own
  copy of the helper.
- Groups appear in the order of their first bind; binds with the same
  description share a row (the digit row and the four arrows collapse to one
  keycap); a description with no group goes under "Other".
- Typing filters; Esc clears the filter, then closes.

### Session menu

`SessionMenu.qml` (Super+Escape or the power key, `qs ipc call session
toggle`): a modal on the focused monitor with Lock (the lock screen), Log out
(`uwsm stop`, back to tuigreet), Reboot and Shut down. Up/Down and Enter, or the row's letter; Reboot and
Shut down act on a second press (a held key is one press). There is no suspend: the eGPU does not come
back from it.

### Polkit dialog

`Polkit.qml`: the session's polkit authentication agent. Each request is a
modal on the focused monitor with the message, the identity, a password field
and the action id; Enter authenticates, Esc cancels, a wrong password clears
the field and says so, and the field is emptied whenever the dialog hides. Requests queue and show one at a time. `qs ipc call
polkit cancel` cancels the one showing. Quickshell tries to register the
agent once per process, when `Polkit.qml` first loads, and reloads keep that
registration; if another agent held the session then, it takes a Quickshell
restart.

### Network panel

`Network.qml` (parts in `network/`), a 420 px panel under the bar's network
icon: WIRED, then WI-FI, then SET IN NIX.

- Wired devices first: a connected one shows link speed, IPv4 address and
  its last speed test; Enter opens its details (address, gateway, DNS, MAC,
  link speed and duplex, the last run of each provider). Enter never
  disconnects. Addresses come from `nmcli`, the default route from `ip`,
  duplex from sysfs, all read when the panel opens; the rest from
  `Quickshell.Networking`.
- "Set in Nix": greyed rows from `~/.local/share/desk/network/locked.json`
  (Tailscale on, IPv6 off, Wake-on-LAN interfaces, hostname, firewall on,
  Wi-Fi off at every boot; a row only while the setting has that value),
  each naming the repo file that sets it, which Enter shows in the footer.
- Keys: Up/Down move (selection follows the row, not its position, so
  networks coming and going during a scan do not move it), Enter, Esc closes
  details, then the panel; S opens the speed test chooser. The Wi-Fi keys
  are below.

**Wi-Fi.** The section header says `off`, `scanning` or `on` on the right.
With no Wi-Fi device the section is one line, `No Wi-Fi device.`; with the
radio blocked by a hardware switch, `Blocked by a hardware switch.`; with
the radio off, `Radio off. W turns it on.` With the radio on it reads
`Looking for networks…` until a scan answers, then `No networks found.` or
the list. Each row has a signal glyph in four steps, the name (the only
thing cut short), and a line with the security in words (`WPA2 password`,
`open`, `open, encrypted` for OWE, `enterprise: not supported`) and
`· saved` for a network NetworkManager has a profile for; `connected` in
green or `joining…` in cyan on the right. Connected first, then saved, then
by signal; the order holds still while the password modal is up or a join
runs. Enter on the connected row opens its details (address, gateway, DNS,
MAC, security, signal, whether the wired link carries the traffic). A
failed join leaves a red line on its row ending `Enter retries`; a sign-in
page the network wants shows as an orange line on the connected row, only
while Wi-Fi carries the default route.

- **Keys**: W turns the radio on or off; F5 scans again; Enter joins (a
  saved, open or OWE network at once, an unsaved password network through
  the modal) or opens the connected row's details; C disconnects the
  connected network, or joins a saved one; F on a saved network asks
  (`press F again to forget · Esc keeps it`), and a second F forgets it. Esc
  first cancels a join in progress (and forgets the profile of a network
  that was not saved before), then keeps an armed forget, then closes
  Wi-Fi details (which also close on their own when that network stops
  being connected), then does what it does elsewhere in the panel. While a join
  runs every other key says `joining · Esc cancels`. S is unchanged. A join
  that neither connects nor fails within 30 s is reported as `no answer
  after 30 s` and not cancelled: NetworkManager may still finish it.
- **The password** (`network/PasswordModal.qml`): a centred modal on the
  panel's monitor, with the panel hidden behind it, naming the network and
  its security. The field is masked, Tab shows or hides it, Enter joins
  once the text can be a password (8 to 63 bytes, as NetworkManager counts,
  or 64 hex digits for WPA/WPA2; at least one character for WPA3). The field is empty and masked every time
  the modal opens or closes. If NetworkManager answers that it lacks the
  secret or authentication timed out, the modal comes back, empty, with one
  line: `Not joined. The password was wrong, or the network refused it.` It
  cannot say which: NetworkManager reports a wrong password and a refusal
  the same way. Esc closes the modal; after a failed attempt on a network
  that was not saved before, it also forgets the profile NetworkManager made
  for that attempt, so nothing with a wrong password is left behind. A
  network saved before is never forgotten by Esc.
- **Where it goes**: the networks come from `Quickshell.Networking`, turned
  into plain rows (names, signal, security, state) while the panel is open;
  every decision is in `network/wifi.js`, plain JavaScript node runs too
  (the `wifi-panel` check). The password goes from the field straight to
  NetworkManager over D-Bus (`connectWithPsk`), which stores it in its
  connection profile, as for any network it saves. The shell does not keep
  it, log it or write it anywhere, and nothing in this repository holds one.
- **Scanning** runs only while the panel is open with the radio on (also
  while the modal hides the panel), and stops when the panel closes or the
  radio goes off. Nothing Wi-Fi runs while the panel is closed except the
  bar's reading of module properties.
- **Off at every boot**: the `wifi-radio-off-at-boot` unit
  (`hosts/BrightFalls/networking.nix`) writes `WirelessEnabled=false` into
  NetworkManager's state file before NetworkManager starts, once per boot.
  W turns the radio on for the session; the next boot has it off again. The
  "Wi-Fi off at every boot" row under Set in Nix says so.
- **Bar**: the network item shows the ethernet glyph while wired, the Wi-Fi
  glyph in its four signal steps while only Wi-Fi is connected, or the
  no-network glyph; while the radio is on and Wi-Fi is not the glyph shown,
  a small Wi-Fi mark sits beside it, so a radio left on is visible. Red when
  offline, purple while the panel is open, as before.
- **Not offered**: hidden networks (the module drops access points with no
  name); setting up enterprise (802.1X) networks (the module cannot pass an
  identity, method or certificate; a saved one still joins from its
  profile), WEP (the join call refuses it) and LEAP; opening a sign-in page
  (only the line); hotspot and sharing (not in the module); forgetting a
  saved network that is out of range (the module does not list it, so the
  panel cannot reach it); the link rate (the module gives none; the details
  say so).

**Speed test.** S opens a chooser in place of the list: 1 Cloudflare
(`cfspeedtest`, speed.cloudflare.com), 2 Speedtest.net (the Ookla CLI,
`speedtest`, nearest server; unfree, its licence and GDPR notice accepted on
its command line), 3 All in turn. Each provider row shows its own last
result. The provider used last is preselected (Cloudflare with no history),
so S then Enter repeats the previous test; Up/Down and Enter, or the number,
run a row; Esc returns to the list. Providers (tool, command line, how live
figures and the result are read) are described only in
`network/SpeedTest.qml`.

- A test runs over the connection carrying the default route: latency, then
  download, then upload on two gauges with one shared scale: the interface's
  negotiated link speed, or, when that is unknown, the smallest of 100 Mb/s
  to 10 Gb/s that holds that connection's best stored result; a reading
  above it grows the scale to the next of those that holds it. The line
  under the gauges names the provider.
- Esc during a run kills it, stores nothing and returns to the list; a
  failure shows under empty gauges, Enter retries.
- All in turn adds provider chips above the gauges (current lit, finished
  green) and a table under them (down, up, ping per provider; a failed one
  says "failed" and the next still runs); when all are done the gauges show
  the fastest result and the screen stays until Esc. Esc during it stops the
  current run and keeps the finished ones.
- Latencies differ by provider: Cloudflare's is an HTTP round trip, Ookla's
  an idle ping.
- Each completed run is appended as one JSON line (`at`, `connection`,
  `interface`, `download_mbps`, `upload_mbps`, `ping_ms`, `provider`
  (`cloudflare` or `speedtest`; older lines without it count as Cloudflare),
  `tool`) to `~/.local/state/desk/speedtests.jsonl`, never trimmed. The row
  shows the newest run per NetworkManager connection and its provider.
- Not used: fast.com's `fast-cli`, which rounds rates of 1 Gb/s and over to
  whole Gb/s.

### Audio panel

`Audio.qml` (parts in `audio/`), a 400 px panel under the bar's audio item.
The output switcher stays on the bar (left click cycles, right click mutes,
wheel sets the volume). Nothing runs while it is closed, except the no-signal
check.

- **The stack** (`audio/Stack.qml`): Magni 2 on Modi 2. The Magni is analog
  and never has a state. The Modi's light is cyan while its ALSA device is
  open, white while closed (idle), and the Modi is dashed and dim with no
  Modi sink in PipeWire ("missing"). Beside it the format it is open with
  and chips of what it can take, the current ones lit. Capabilities come
  from `/proc/asound/card<N>/stream0`, the open format from
  `pcm0p/sub0/hw_params` ("closed" when idle); N is the Modi sink's
  `alsa.card` property (`audio/Modi.qml`).
- **The path**: how many programs are playing, "mixed at" the graph rate when
  there are several, the surround filter when it is the default output, then
  the Modi with bits/kHz, or the fallback output in orange.
- **Playing**: one row per playback stream (filter-chain halves left out),
  including paused ones.
  - The tag is the layer it came through: `pulse` (`client.api` =
    `pipewire-pulse` on the node), `alsa` (`client.api` = `alsa` on its
    client, node named `alsa_playback.*`), `jack` (`client.api` = `jack`,
    from the pipewire-jack source; JACK is not installed, so never seen
    here), otherwise `native`.
  - Then its own rate and channels and a verdict: `paused` (no active
    link), `through <filter>` (cyan), `resampled to X` (its rate differs from
    the graph's), `downmixed to stereo`, `volume scaled` (its volume is not
    100%; orange) or `direct` (green).
  - Left/Right change the selected stream's volume in 5% steps, M mutes it,
    Enter opens details: layer, what it sends (rate, sample format,
    channels), what it becomes (with the stream's own `resample.quality`),
    where it goes, volume, and the graph period from `pw-top`. A volume set
    here is a stream volume, which WirePlumber remembers for that program.
  - Under the volume, a level bar like the inputs' (`audio/Level.qml`,
    shared with them) shows what the program adds to the output: the monitor
    reads the stream before its volume (Quickshell divides the volume out),
    so the bar multiplies it back in; muted or paused, it has no monitor and
    is flat. A stream lacking a channel of its output (mono into the stereo
    Modi) gets no bar, since Quickshell 0.3.2 cannot meter it; its details
    say "not metered".
  - Formats, drivers, client APIs and resampler quality come from one
    `pw-dump` run when the panel opens and whenever streams, links or the
    default output change, plus once 6 s later to see the device suspend
    (`audio/Graph.qml`). Volume, mute, links and link state are Quickshell's
    (`Quickshell.Services.Pipewire`).
- **Inputs**: every capture device with its gain, a level bar (Quickshell's
  `PwNodePeakMonitor`, cube-root scale, one capture stream per input while
  the panel is open, none after) with a yellow mark for the peak of the last
  1.5 s, `default`, its rate, "heard by <program>" for each capture stream
  linked to it, and `clipping` (red) at 0.99 on that scale, kept for 2 s.
  Selection runs on from the programs; Left/Right set the gain, M mutes,
  Enter makes it the default input, which WirePlumber keeps until another is
  chosen, over the Nix priority.
- **No signal** (`audio/NoSignal.qml`, a singleton that runs whether the
  panel is open or not): an ALSA input whose capture PCM is `RUNNING` while
  `hw_ptr` stays put between two reads 750 ms apart
  (`/proc/asound/card<N>/pcm<D>c/sub<S>/status`, from the node's
  `alsa.card`, `alsa.device` and `alsa.subdevice`) delivers no samples.
  Silence still moves `hw_ptr`, so a quiet room is not flagged. The Blue
  microphone falls into this now and then until its cable is replugged.
  - `/proc` is read only while one of the input's links is active (a program
    or a level monitor records from it), and once when the input appears
    (shell start or reload, replug), by opening it for about 1.5 s with a
    level monitor. The reads stop once two of them decide, so a microphone
    that hangs in the middle of a recording is flagged only when it next
    starts running; a flagged input is read on while it runs.
  - The row then says `no signal · replug the cable` in red, its level is
    flat with no monitor, and Enter explains in the footer instead of making
    it the default. The bar's audio item gets a red dot.
  - One desktop notification per input and fault; the flag goes when
    samples flow or the input goes away.
- **Set in Nix**: greyed rows from `~/.local/share/desk/audio/locked.json`,
  generated from `services.pipewire.extraConfig` and the WirePlumber ALSA
  rules (allowed rates with no fixed rate, the Modi's S24LE format,
  min-quantum and the daemon's `resample.quality`, the Blue microphone's
  session priority); the file comes from the definition that sets each value.
  Enter shows it in the footer. No file, no section.
- The daemon's `resample.quality` does not reach program streams, which
  resample in the client; that is why the row says "daemon" and the details
  show each stream's own quality.

### Calendar panel

`Calendar.qml` (parts in `calendar/`), a 360 px card under the bar's clock.

- **The clock** on the bar: the week as seven dots, Monday first (gone
  filled, today large and purple, to come hollow), the short date, a ring
  that fills clockwise from midnight, and the time. When timed events start
  within the hour a cyan note follows it: `1 event at 11:00`, `2 events at
  11:00`, or `3 events from 10:00` when they start at different times; it
  goes once the last of them has started.
- **The month**: ISO week numbers on the left, weekends in pink, today
  filled, the selected day outlined in pink. Dots under a day show which
  calendars have something that day, one per calendar in its own colour, at
  most three. A one-line legend under the month names the calendars present
  in the shown month. The header shows the week number, or `syncing…`.
- **The day**: the selected day's events are always listed under the month:
  all-day first, past events today faded, several-day events as "day N of
  M". "time zone unknown" in orange means the event's own time zone could
  not be read, so its time may be off.
- **Keys**: ←→ move by a day and ↑↓ by a week, across months; PgUp/PgDn
  change month, keeping the day number; T jumps to today; F swaps the panel
  for the [big view](#calendar-big-view) on the same day; Enter or O opens
  the selected day in the Nextcloud web calendar; R syncs now; Esc closes. A
  click on a day selects it.
- **Data**: read-only. Events come from the export that `calendar-sync`
  writes ([Calendar events](#calendar-events)), and the panel answers from
  memory. An orange footer means the last good sync is 30 minutes old or
  more (the server could not be reached) and says when it was; "No calendar
  is set up" means no export exists yet. The web calendar's address is read
  from the file `~/.local/share/desk/calendar/source.json` names, only when O
  is pressed, and is never kept or logged.
- `calendar/queries.js`, the panel's and the reminders' decisions, is plain
  JavaScript that node runs too (the `calendar-panel` check, [Tests](#tests)).

### Calendar big view

`CalendarFull.qml` (parts in `calendar/`: `CalendarFullShared.qml`,
`MonthCell.qml`), the same calendar as a card 80 % of the focused monitor's
width and height, in its middle. Super+Shift+C (`qs ipc call calendarfull
toggle`) opens it on today, and F in the calendar panel opens it on the
panel's selected day.

- **The month**: ISO week numbers on the left, then Monday to Sunday,
  weekends in pink, one row per week sharing the height. Each day names its
  events, as many as fit: an all-day event, or one begun on an earlier day,
  as its title on a bar of its calendar's colour; any other as a coloured
  edge, its start time and its title. What does not fit is counted on a
  last line, `3 more`. Today's number is on a purple pill, the selected day
  outlined in pink. Days outside the month show their number only. The
  header shows the week number, the month's weeks, or `syncing…`.
- **The day**: beside the month, the selected day's events as the panel
  lists them, scrolling when they do not fit, and under them the legend of
  the month's calendars, wrapping. Not shown while no export exists.
- **Keys**: as the panel's, except F, which swaps the big view for the
  panel on the same day. A click on a day selects it; a click outside the
  card closes.
- **Data, sync and web calendar**: the panel's (`calendar/CalendarActions.qml`
  runs R and O for both). Each view keeps its own sync state: after F the
  header's `syncing…` follows the service within 3 seconds, and a failure
  message from a sync started in the other view is not shown.
- **Look**: everything behind it on that monitor, the bar included, is
  dimmed by the shell and blurred by Hyprland (a layer rule for
  `desk-calendar-full` in `hypr/rules.lua`). Game mode turns Hyprland's blur
  off, and then it is only dimmed. A critical notification card or the OSD
  is drawn above it, sharp, when its window appears after the big view
  opens (both are Overlay surfaces, stacked in the order they appear, as
  over the drop-downs); one already up when it opens stays under it, as do
  the other notification cards, on the Top layer.
- It is not a drop-down, but it is in `common/Dropdowns.qml`: opening it
  closes any open drop-down, and opening a drop-down, the launcher, the
  cheat sheet or the session menu closes it. Like them it is an Overlay
  surface with the keyboard: not for use over a game.

### Calendar reminders

`calendar/Reminders.qml` (decisions in `calendar/queries.js`) turns the
calendar export into desktop notifications from the "Calendar" app.

- Each timed event reminds at its own alarms. An event with none reminds 60
  minutes before it starts. All-day events remind only at alarms before their
  first day, such as "the evening before", worded "tomorrow, all day"; on the
  days they cover, the morning digest announces them. Without an alarm, a
  full-day event counts as reminding at 09:00 on its first day, which the
  digest also covers.
- The two defaults are `DEFAULT_LEAD_MIN` and `DEFAULT_ALL_DAY_TIME` in
  `queries.js`. They copy the Nextcloud Calendar settings "Default reminder
  for part-day events" and "Default reminder for full-day events", which the
  sync cannot read, so change them together with those.
- A reminder card shows the title, then the time range, how long until the
  start, and the calendar, for example "11:00 – 12:00 · in 1 h · Work".
  It stays until dismissed or until 5 minutes after the start. A later
  reminder for the same event replaces it. **Open** shows the day in the
  calendar panel. A reminder whose moment passed while the PC was off still
  fires if the event has not started ("starts in 4 min"). An alarm set at or
  after the start fires while the event runs.
- The digest arrives once a day, at the first login, or at 06:00 if the
  session is already running. Its title is "Today · Sunday 15 November". It
  lists all-day events, then timed ones with their start, at most six lines
  then "and N more", and leaves out what is already over. With nothing on,
  there is no digest.
- While any monitor shows a fullscreen window (a game, or a fullscreen
  video), and while the screen is locked, reminders and the digest are held.
  When that ends they arrive at once, worded for that moment ("starts in 3
  min", "started at 11:00, 25 min ago"). Events already over are dropped,
  and more than three come as one summary. A maximised window does not hold.
  A game in borderless-windowed mode is not fullscreen to Hyprland and does
  not hold either.
- Nothing repeats across reloads or reboots: what has fired is kept in
  `~/.local/state/desk/calendar-reminders.json`.

### System panel

`System.qml` (parts in `system/`), a 420 px panel under the bar's chip.

- **Bar item**: the CPU's temperature (k10temp Tctl) and the eGPU's junction
  temperature, each orange or red near its limit; with the eGPU absent or
  asleep, only the CPU's. Resting the pointer on it lists every temperature
  in the machine (`system/Temperatures.qml`).
- **The panel** draws the UM890 Pro, the OCuLink cable and the DEG1 with the
  RX 6800 XT, its fans turning in proportion to the card's real fan speed.
  Under it, the cable's negotiated link against what the root port can do,
  and "≈ N W chip + card", the APU's package power plus the card's board
  power (not wall power).
- **Sections**: CPU (load, per-thread load, average clock and the configured
  maximum, tagged `nix` when NixOS sets it, hottest core from the APU's
  metrics, package power); Memory (used = total − available, cache, swap,
  both modules' temperatures); eGPU (load, VRAM, junction, memory
  temperature, fan rpm and duty, power, clocks, voltage, which outputs it
  drives, a throttling tag only while the card reports throttling); iGPU
  (load, VRAM, clock, voltage); Storage and network (NVMe temperature and
  read/write rate, free space for `/`, `/home`, `/mnt/games`, the default
  route's interface rate).
- **Keys**: ↑↓ choose a section, Enter shows its details (regulator
  temperatures, power limit, who controls the fans, CPU policy and clock
  limit with the file that sets it, link errors if any), Esc closes them,
  then the panel.
- **Data**: everything is read straight from sysfs and procfs
  (`system/Sensors.qml`; `gpu_metrics` decoded by `system/decode.js`), never
  from LACT's socket and never writing anything. Hardware is found by name
  and device path, not hwmon numbers. While the panel is closed only the two
  bar temperatures are read, every 5 seconds; hovering reads the temperatures
  each second (the memory modules and the NVMe no more often than every 10
  seconds, hover or not); the open panel reads about 30 small files a second
  and a few every 10 seconds. A sleeping eGPU is not read until it wakes. Memory-module
  alarm files are never read, because reading one clears it.
- **Deliberately not shown**: link saturation, because no traffic counter
  exists for this card on this kernel (`pcie_bw` is absent on Navi 21, and
  gpu_metrics v1.3 has no bandwidth fields), so the link line says only what
  was negotiated; CPU-only power, because RAPL is root-only, so "package" is
  the whole chip, CPU and built-in graphics together; per-program use, frame
  rate and frame time, which are MangoHud's job inside a game; history, which
  is not kept. Nothing of this panel is meant to be shown over a fullscreen
  game.

### Bluetooth panel

`BluetoothPanel.qml` (parts in `bluetooth/`), a 380 px panel under the bar's
Bluetooth glyph. Super+Ctrl+B (`qs ipc call bluetooth power`) turns the
adapter on or off without the panel and the OSD pill says which (Super+Shift+B
is Firefox). The bar adds the level in red beside the glyph while a connected
device reports under 15%.

- **The list**: paired devices, connected first, then by name, each with its
  kind and state, and a battery gauge when the device reports one (orange
  under 35%, red under 15%). The kind and glyph come from the icon BlueZ
  derives from the device's class (`bluetooth/devices.js`); BlueZ has no kind
  for watches or earbuds, and a device that reports none shows the plain
  mark. Then "Set in Nix": `~/.local/share/desk/bluetooth/locked.json`, one
  row while `hardware.bluetooth.powerOnBoot` is on; turning Bluetooth off
  here lasts until the next boot. Only a device's name may be shortened;
  every other line wraps.
- **What a connected device does here** shows as glyphs at the right of its
  row: a handset for calls, a music note for audio, play/pause for media
  controls, a network plug for network sharing; green in use now, white
  connected, grey allowed but not in use. Details list the same in words
  under "uses", only from evidence: the media transports, media control and
  network links BlueZ has set up and the hands-free link PipeWire holds
  (both reported by the agent helper), the device's PipeWire nodes (audio is
  "playing here" only while its node is linked to an output) and the service
  questions answered in this session (kept across reloads, not restarts; a
  trusted device is not asked). Input devices and file transfer show only as
  answered services: BlueZ exposes no connected state for them.
- **Calls** follow PipeWire's telephony service (`org.pipewire.Telephony` on
  the session bus, run by WirePlumber), which has one audio-gateway object
  per phone whose hands-free link is set up: the handset is white while that
  link is up, green with "in a call now" while call audio runs through this
  computer, and gone when the link drops. A grey handset means calls were
  allowed in this session but are not connected. PipeWire's card cannot tell
  this: its `audio-gateway` profile looks the same with or without
  hands-free.
- **Known behaviour: a switch to a text console drops calls.** Leaving the
  graphical seat (Ctrl+Alt+F*) makes WirePlumber stop
  its Bluetooth monitor, which frees PipeWire's Bluetooth side: call audio in
  progress here stops (the phone falls back to its earpiece), the hands-free
  link and the phone's music drop. Back on the seat the profiles are
  registered again, but calls return only when the phone reconnects
  hands-free (C, C here, or from the phone); PipeWire does not reopen the
  link (WirePlumber `monitors/bluez/enumerate-device.lua`, PipeWire
  `backend-native.c`).
- **Keys**: the footer always lists the keys that work anywhere in the panel
  (↑↓ select, S, V, B, Esc) and adds the selected row's. ↑↓ select; Enter
  opens details (address, trust, battery, the codec PipeWire negotiated,
  uses), pairs a nearby device, or names the file of a Set in Nix row; C
  connects or disconnects; T switches trust (details); F forgets, after a
  second F; S scans for 30 s and lists named, unpaired devices under
  "Nearby", strongest signal first (RSSI from the agent; sorted by name, and
  it says so, when none is reported); V makes this computer visible for 2
  minutes so a phone can find and pair with it; B turns the adapter on or
  off; Esc steps back, then closes. With no device listed nothing is
  selected; ↓ reaches the Set in Nix rows.
- **Pairing**: `desk-bt-agent` (`bt-agent.py`, `bt-agent.nix`), a small
  Python helper the shell starts once and restarts if it exits, is BlueZ's
  default agent; Quickshell has no agent and QML cannot export a D-Bus
  object. Codes, PINs, "pair without a code" and service requests from
  untrusted devices open a centred modal (`bluetooth/PairModal.qml`) on the
  panel's monitor, or on the focused one when the panel is closed. Nothing is
  ever answered without a key. Services are named in plain words with the
  question they mean (`bluetooth/services.js`); T there allows this and
  anything else the device asks, now and later, by trusting it. BlueZ asks
  one service at a time and holds the rest where the agent cannot see them,
  so there is no count of questions waiting. The user's yes to a pairing
  (code, no-code, passkey or PIN) trusts the device at once, before BlueZ
  reports it paired, so the services a phone opens right after pairing are
  allowed without a question instead of waiting on the modal while the
  phone's own timeout (about 15 s) runs. A refused pairing never trusts. If
  the pairing then fails, BlueZ would keep a trusted, unpaired device
  (`src/device.c`, `device_bonding_complete`), so the shell withdraws the
  trust: at once for a pairing started here, otherwise when the device
  disconnects unpaired or after a minute. The result of a pairing is read
  from BlueZ's `Paired` and the agent's requests, not from the reply to
  `Pair()`, which QtDBus abandons after its call timeout. Every request,
  answer and cancel goes to the shell's log (`journalctl --user -u
  quickshell`) by method, request id and short service UUID, never a device
  name or address.
- **Pairable**: the adapter accepts pairing only while this computer pairs a
  device or while V runs. BlueZ turns it on whenever an agent registers, and
  the shell turns it off again. It stays on for pairings started here too:
  with it off, the kernel still pairs as initiator but without bonding, so
  nothing would be stored (`net/bluetooth/hci_event.c`, `smp.c`).
- **Codecs**: WirePlumber offers only SBC, SBC XQ and AAC over Bluetooth, for
  every device (`hosts/BrightFalls/audio/default.nix`): with LDAC, A2DP from
  a phone never settled against BlueZ 5.87.
- **Low battery**: one critical notification per device each time it drops
  under 15% (`bluetooth/BluetoothShared.qml`); remembered across reloads, not restarts.

### Office panel

`Office.qml`, with `office/OfficeShared.qml` (shared with the bar: placement,
the helper process, the state) and `office/office.js` (every decision: how
the helper's events change the state, ages, percent and raw brightness,
steps, locks, row texts, banners, the bar item; node-tested). A 360 px panel
under the bar's office item for one light, one blind and five sockets, all
through [`desk-mqtt`](#office-desk-mqtt), which the shell runs for as long
as it runs and starts again if it exits (after 2 s, doubling to a minute
while it keeps failing).

- **Bar item**: a bulb, yellow and lit while the light is on, hollow
  otherwise, and the sockets' total power now (`— W` while nothing is
  known). Greyed while the values are stale (broker or Zigbee2MQTT down).
  A click opens the panel.
- **Header tag**: `read only` in orange whenever the helper runs with
  `--read-only`; `live` only when it does not and the broker is up,
  Zigbee2MQTT online and the retained state read; otherwise nothing.
- **Light**: on or off, brightness as a slider in percent (Zigbee2MQTT's
  1..254 underneath). The fill is the confirmed value, the handle the one
  asked for. An off light keeps its last brightness as a greyed fill with no
  handle, and its slider takes no pointer input; ← or → steps from that
  brightness, and the release sends the new level, which turns the light on
  at it. With the light on, the slider is dragged with the mouse or stepped
  with ← →. No slider until a brightness has been reported.
- **Blind**: ▲ ■ ▼ (open, stop, close) and a position slider (0 closed, 100
  open). ▲ is off at 100 and ▼ at 0; ■ is lit while the motor runs, and the
  handle shows the target until it gets there. The state line reads
  Opening…, Closing…, Blocked, Closed or Open N%. A blind that does not list
  `position` gets the buttons only and Open / Closed / Stopped.
- **Sockets**: watched only; nothing in the panel can address one, by key or
  click, and the helper has no socket command. Sorted on, then off, then
  offline or silent, each by watts, with a share bar. The total counts the
  sockets that are online and reported ("4 of 5 sockets" when one is left
  out); while values are stale it says how long ago they were current.
- **Every row** shows its age on the right (orange from an hour). Offline
  devices are greyed and red ("Offline · was on"); a device with nothing
  retained says "No report yet".
- **Sending**: a slider is sent once, when the key or the mouse button is
  released (auto-repeat is ignored), and not at all if it ends where it
  started. A command shows "Sending…" until the device's next state confirms
  it. Not confirmed within 5 s: the handle goes back, the row says what was
  asked and when ("Not confirmed: asked 70 % at 18:43:05", "Did not start
  opening …") until the device's next report or command, and the footer
  says it for 5 s. Nothing is retried. Refused by the helper: "Not sent:
  " and the reason in words.
- **Locks**: controls are off while the broker is down, Zigbee2MQTT is not
  online (also while that is unknown), the device is offline, or
  Zigbee2MQTT has not confirmed the device as a light or a cover; pressing
  one then says which in the footer. Read-only does not lock: the controls
  move, the helper refuses, the row says so.
- **Banners**: red "Can't reach the MQTT broker" (or the broker's refusal)
  when it was never up; orange "Broker lost N min ago" or "Zigbee2MQTT is
  offline" with the values kept from before.
- **One line instead of the panel** when the helper's config is missing or
  invalid (the key at fault, never a value) or the helper is not running.
- **Keys**: ↑↓ select the light or the blind; ←→ step the selected slider
  10 % (sent on release); Enter switches the light; U, S, D open, stop and
  close the blind wherever the selection is; Esc closes. Mouse: drag a
  slider and release, click ▲ ■ ▼, click outside to close.
- **Log**: each command sent and its outcome go to the shell's log
  (`journalctl --user -u quickshell`, "office helper: …"), by the generic
  device ids from `desk-mqtt.nix`.
- **Read-only for development**: `readonly property bool readOnly` in
  `office/OfficeShared.qml`. `true` starts the helper as `desk-mqtt
  --read-only`, which refuses every command and publishes nothing; the save
  restarts the helper. It is `false`: the panel is live.

### Fleet panel

`Fleet.qml`, with `fleet/FleetShared.qml` (shared with the bar: placement,
the helper process, the state) and `fleet/fleet.js` (every decision: how the
helper's events change the state, host order, the header and pipeline, row
views and folding, info lines, which keys are lit, the questions, key to
command, the footer, the bar item; node-tested). A panel under the bar's
fleet item with one row per host: what it runs, what its comin is doing,
what a reboot changes, one chip, and the keys that apply. All of it comes
from [`desk-fleet`](#fleet-desk-fleet), which the shell runs for as long as
it runs and starts again if it exits (after 2 s, doubling to a minute while
it keeps failing). The panel never recomputes: chip, colours, texts and
whether a key is allowed (with the helper's reason when not) are the
helper's.

- **Bar item**: a server glyph and the number of hosts with a red, Pending,
  Behind or Reboot chip (none at zero). Dim with no number until a host has
  been read, or while the helper is not running. A click opens the panel.
- **Header**: "checked N s ago" (or "checking…") and `read only` or `live`.
  Under it the pipeline: master's commit, the last `build.yml` run on master
  (passed, building, queued or its conclusion), and the deploy branch's
  commit with "N behind" in orange. A GitHub error replaces the pipeline with
  a banner; the hosts are still read.
- **Rows**: in the helper's order, online hosts first; this computer marked.
  Lines fold to their first line ("… (I for all)"); I unfolds the selected
  row with its full paths, kernels, inhibitors and comin's messages. The row
  of a host where an action runs shows its state: a spinner and the last
  output line while running, then ok in green or failed with the exit code in
  red, and the sudo-password message in orange.
- **Questions** in the row, before anything that changes a running machine:
  switch (names the commit and what it replaces: a hand build, a testing
  branch; Enter switches, D diffs first, Esc cancels) and reboot (what it
  comes back on, or that it is not known; Enter, Esc). B (next boot) asks
  nothing. M opens the mode chooser: 1 manual, 2 automatic boot, 3 automatic
  switch (macOS 1 and 3), Esc back; the current mode is ticked and picking it
  sends nothing.
- **Keys**: ↑↓, J K, Home End select a host; S switch, B next boot, D diff,
  M mode, R reboot, T ssh (a plain terminal on this computer), I info, A the
  host's last action output, each only when lit; O opens the build run in
  the browser (`uwsm app -- xdg-open`); F5 probes everything again; Esc
  cancels the open question, else closes. A key that is not lit says the
  helper's reason in the footer for 2 s, as does a refusal. A click selects a
  row; nothing is mouse-only.
- **One line instead of the panel** when the helper was not found ("The
  fleet helper (desk-fleet) was not found.") or stopped and is being
  restarted.
- **While closed** the helper probes every 5 minutes, so the bar's number
  stays true; while open every 60 s, with the header and spinner ticking.
- **Read-only for development**: `readonly property bool readOnly` in
  `fleet/FleetShared.qml`. `true` starts the helper as `desk-fleet
  --read-only`, which refuses switch, boot, mode and reboot (they run
  nothing), while probes, diff, ssh and attach work as usual; the save
  restarts the helper. It is `false` in the repository: the panel is live
  once deployed.

### Tailscale panel

`Tailscale.qml`, with `tailscale/TailscaleShared.qml` (shared with the bar:
placement, the `tailscale status` calls, the last answer, the mesh-host file)
and `tailscale/tailscale.js` (every decision, see [Tailscale: status and mesh
hosts](#tailscale-status-and-mesh-hosts)). Super+V, or a click on the bar
item between Bluetooth and Network, opens it. It is read-only: it runs only
`tailscale status --json` and never writes to the daemon.

- **Bar item**: the Tailscale glyph, in the foreground while on, grey while
  off, orange when something wants attention, purple with the open mark
  while the panel is open.
- **Contents**: the well shows this computer; MY HOSTS are the peers in
  `~/.local/share/desk/tailscale/hosts.json`, under their repository names;
  OTHER DEVICES are every other peer. Without the mesh-host file every peer
  is under OTHER DEVICES and T is never offered.
- **Keys**: ↑↓ J K Home End select, Enter unfolds the details, Y opens the
  copy chooser (1 name, 2 DNS name, 3 IPv4, 4 IPv6; in the logged-out states
  Y copies `sudo tailscale login`), T opens Ghostty with `ssh <alias>` on an
  online mesh host that runs sshd, O opens the admin console (the login page
  while a login is pending), F5 reads now, Esc goes back or closes.
- **Polling**: `--peers=false` at shell start and every 30 s while the panel
  is closed (for the bar item); the full call on open, every 5 s while open
  and on F5; one call at a time; a call still running after 10 s gets
  SIGTERM, then SIGKILL 2 s later.

### Token panel

`Tokens.qml`, with `tokens/TokensShared.qml` (shared with the bar:
placement, the helper process, the panel's state, the limits file and its
watch) and `tokens/tokens.js` (every decision: how the helper's answers and
events change the state, every text and colour of the four pages and the bar
item, what each key does, the footer, the reading of the limits file;
node-tested). Super+U, or a click on the bar item left of the fleet item,
opens it. It shows how much Claude Code has been used on this computer, and
the plan limits as Claude Code last reported them. It is read-only.

- **Bar item**: a pie glyph and the weekly all-models percentage, rounded
  down, from the limits file. Foreground below 80 %, orange from 80 %, red at
  100 % (compared before rounding). Dimmed, value kept, when no running
  Claude Code session has reported the current window for an hour (while one
  does, the file is refreshed every 15 minutes); an empty ring and a dash, dimmed, with no reading
  (no file, or the week it was written in has reset). Purple with the open
  mark while the panel is open. It changes when the file does, and on a
  minute tick while a reading exists; it never starts the helper.
- **Overview** (what it opens on): the plan limits (the weekly row with its
  reset, when the figure was seen (the file's `evidence_at`, the reporting
  session's transcript time, else when it was written), `as of 17:58` today
  or `as of Mon 17:58` before, and a meter; a muted per-model row; the 5-hour row; a line saying
  what happens at 100 %, or that the reading is stale, or that none is known
  yet), today's output and sessions with the context read from cache and
  today at API prices, the last 14 days of output as bars (today purple, the
  peak named), 30 days (the split by model family, cache hit, the
  sub-agents' share of output, the total at API prices beside the plan's
  price, then that total by token type, as a bar and a row per type with its
  tokens, and by model family, a row per family with its share of tokens,
  largest first), and the 7-day top projects, each with its output and,
  muted before it, its figure at API prices.
- **Figures at API prices**: every page that shows token quantities also
  shows what they would cost at API list prices (`≈ $4.37`, `≈ $3,571`,
  `≈ $12.3 k`), as priced by the helper reply by reply. Each such page
  carries once, muted above the footer, `Estimates at API list prices; the
  plan is a flat $200.` (the plan figure from `PLAN`). A quantity made only
  of models missing from the price table says `unpriced` instead of a
  figure; one partly so says `≈ $N + unpriced`, and the page names the
  models once (`not priced: …`). A helper older than the cost fields gives
  the pages as they were, without the rows, the column and the S key (the
  overview still shows its old 30-day figure, and so the estimate line).
- **First read**: the helper builds its index from the newest transcripts
  back, so today, 7, 14 and 30 days become complete in turn. Until then a
  progress block (files read, size, percentage) stands where the first
  missing section would be, and the sections fill in as they become
  complete. The projects, detail and days pages show the same block until
  what they need is read.
- **Projects** (P): one row per project for today, 7 days or 30 days (Tab),
  by output or, after S, by figure at API prices (largest first, unpriced
  last; S again goes back, and each opening starts by output): name, output
  and share, a share bar, a small bar of the model split, sessions, last
  reply and the sub-agents' share, and the figure at API prices on the
  right; when the line and the figure do not fit side by side the line
  wraps. The summary says the order, the total output and the total at API
  prices. Shares and share bars are shares of output in both orders. Eight
  rows a page. Only a project name elides.
- **Detail** (Enter on a project): the project's output and share,
  sessions, sub-agents' share, figure at API prices and model split for the
  period (Tab changes it), that figure by token type (bar and rows, as on
  the overview), its last 14 days, and its six latest sessions (start, last
  reply, output, figure at API prices over the session's whole life,
  sub-agents included; replies and active time on a muted line under each).
- **Days** (D): the last 14 days, newest first: output as a bar and a
  number, the figure at API prices, sessions, and the day's top project.
- **Keys**: on the overview P projects, D days, R ("refresh counts") reads
  what was appended to the transcripts since the panel opened and reads the
  limits file again (hidden during the first read, unless it failed), Esc
  closes. R cannot refresh the weekly percentage: only a Claude Code
  session's status line writes it. For four seconds after R the footer says
  so, `Counting tokens again from the transcripts · quota as reported 17:58`
  (or `· no quota reported yet`). A held key repeats only ↑↓ and PgUp/PgDn. On projects ↑↓ select (past a page's end they turn the page),
  PgUp/PgDn page (only with more than one page), Tab period, S sort (output
  or API prices; the selected project stays selected), Enter detail, D
  days, Esc back. In the detail Tab period, Esc back to the same project
  and page. On days P projects, Esc back. The footer lists exactly the keys
  that do something; Tab and the letters count only without modifiers.
  There is no mouse selection.
- **Where the numbers come from**: everything but the limits from
  [`desk-tokens`](#tokens-desk-tokens), started when the panel opens and
  stopped (SIGTERM) when it closes by any path; if it exits while open the
  panel says so and starts it again after 2 s, doubling to a minute. A
  helper not on PATH gives one line in place of the panel. The limits come
  from `$XDG_RUNTIME_DIR/desk/claude-limits.json`, written by Claude Code's
  status line (see [the plan-limit
  file](../../../../../modules/home-manager/herdr/README.md#the-plan-limit-file)),
  watched with a `FileView`: the directory is watched too until a reading
  exists, so a file that appears after the shell started is still seen; R
  re-reads it, in case the watch missed a change. While the panel is closed
  nothing else runs.
- **Set by hand**: `PLAN` at the top of `tokens/tokens.js` holds the plan's
  name and price and the 5-hour row's text when Claude Code reports no
  5-hour window. Nothing reads them from the account.
- **What it does not show, and why**: no per-model weekly percentage (the
  status line's input carries only `five_hour`, `seven_day`, the all-models
  week, and a gateway's `spend_limit`, and the panel never reads credentials
  or calls the account's endpoints; the row says it is not reported); no
  5-hour meter unless Claude Code reports a 5-hour window; no "full in N
  days" pace line (it would turn token counts into a share of a limit whose
  token budget is not published); no session titles (the index keeps
  counters, never message text); no scrolling (the shell has none for
  panels; the projects list pages instead). The dollar figures are
  estimates at API list prices, not a bill.

### Tray menu

`tray/TrayMenu.qml`, with `tray/TrayShared.qml` (shared with the bar) and
`tray/menu.js` (the header's name and the entries' marks). A tray icon's
right-click menu, drawn by the shell rather than by Qt: the application's
own entries, read over DBusMenu through Quickshell's `QsMenuOpener`, in a
card like the drop-down panels' that hangs under the icon on that bar's
monitor. Opening it closes any open panel and the reverse (it is `tray` in
`common/Dropdowns.qml`). Left click on an icon is unchanged: it activates the
application, or opens the menu if the icon has only a menu.

- Header: the application's name, from the item's tooltip title, else its
  title, else its id, without a trailing unread count such as "(3)".
- Entries: a fixed 250 px width, labels wrap. Checkbox `✓` (green) or `☐`,
  partly checked `▣`; radio `●` (green) or `○`; disabled entries dim, with no
  hover and no action; separators as thin lines; a submenu has `›` on the
  right. Application icons on entries are not shown.
- Mouse plus Esc: hover selects, a click runs the entry and closes; a click on
  a submenu replaces the content in place with a back row (`‹` and the
  submenu's name, cyan) on top, at any depth. A click outside or Esc closes.
- The menu follows changes the application makes while it is open. If the
  application rebuilds its menu while a submenu is shown, the menu goes back
  to the top level; if it leaves the tray, the menu closes.
- No IPC target and no key: a tray menu is opened from its icon only.

## Wallpaper

One picture per monitor, drawn by hyprpaper on the Background layer, run as
the `hyprpaper` user service (Hyprland session only, `default.nix`). The
pictures are `assets/wallpapers/left.png` at the repo root (DP-1, the left
monitor) and `assets/wallpapers/right.png` (DP-2, the right one), 2560×1440
like the monitors, so `fit_mode = cover` shows them 1:1: ASCII renders of
two paintings in the Dracula palette. The two Macs show the same two
pictures on the same monitors (`modules/home-manager/darwin/desk-wallpaper/README.md`).

- **Matching** is by monitor description, not connector name, because the
  connector numbers are shared between the two GPUs and follow probe order.
  Each `monitor = desc:…` value is the monitor's `make model serial` as
  `hyprctl -j monitors` reports it in `description`; hyprpaper compares it as
  a prefix of the description. A `#` in a serial is written `##` (in
  hyprpaper's config a single `#` starts a comment). A monitor with no match
  shows `misc.background_color`.
- **The config** is generated in `default.nix` and passed to hyprpaper by
  store path (`-c`); nothing is written under `~/.config/hypr`, which stays
  desk-sync's. Splash text and hyprpaper's IPC are off.
- **To change a picture**, replace the PNG in `assets/wallpapers/` (same
  size, or the crop changes), rebuild and switch: the new store path changes
  the unit, and the switch restarts it. The Macs pick up the same file. A new monitor needs its description copied into
  `default.nix`.
- **At login** the first frames show `misc.background_color` (Dracula
  background, `looknfeel.lua`) until hyprpaper starts with the graphical
  session and draws the pictures. Game mode and `single-monitor` turn DP-2
  off; hyprpaper drops that monitor and draws it again when it returns.
- The lock screen covers the wallpaper; it is not shown while locked.

## Lock screen

Super+L, the session menu's Lock row, or `qs ipc call lockscreen lock`; also
before sleep. There is no idle lock and no lock at boot. Files: `lock.qml`
and `lock/` (the lock process), `Lockscreen.qml` and `LockState.qml` (its
side in the shell).

- **Look.** Both monitors go dark with the clock, the week dots and the date.
  The password field is only on the main monitor: the one at the layout's
  origin (DP-1 at 0x0 in `hypr/monitors.lua`), else the first one Quickshell
  lists, picked when the lock starts, so a monitor plugged in while locked
  shows only the clock. The main monitor also shows "N notifications" at the
  bottom right while any are waiting, never their content.
- **Keys.** Keys work on whichever monitor the pointer is on: typing shows
  dots, Backspace removes one, Esc clears, Enter checks. Caps Lock is
  announced under the field (read from Hyprland's main keyboard). A wrong
  password shakes the field, turns it red and counts the failures. If PAM
  holds further attempts off, the field shows PAM's own message. The correct
  password unlocks at once; nothing animates on the way out.
- **Separate process.** `lock.qml` is its own Quickshell configuration in the
  shell's directory (sharing `Theme.qml` and `lock/`), started as
  `systemd-run --user --unit=desk-lock --collect --quiet qs -n -p
  ~/.config/quickshell/lock.qml` (`LockState.qml`, and the bind in
  `hypr/bindings.lua`, which runs it directly so the key locks even while the
  shell is down). Its own unit keeps it out of the shell's cgroup, so
  reloading, crashing or restarting the shell cannot unlock or kill it, and
  the fixed unit name refuses a second lock while one runs. It does not
  reload on file changes. It exits after unlocking.
- **Locking.** `WlSessionLock` (ext-session-lock-v1): once Hyprland confirms
  the lock it draws nothing but the lock surfaces, on every monitor,
  including ones plugged in later. Each surface is opaque from its first
  frame, starting black like the frame Hyprland paints before it, so the
  fade-in never shows the desktop.
- **Password.** PAM, with the service named by `pamService` in `lock.qml`.
  The repository declares `desk-lock` for it
  (`security.pam.services.desk-lock` in `desktop-hyprland.nix`): `pam_unix`,
  no lockout; a wrong password costs pam_unix's delay of about 2 s.
  A service that does not exist means no password can unlock, so a renamed
  service has to be deployed before `pamService` names it. The lock screen
  keeps what is typed only until it hands it to PAM.
- **What is held while locked.** The lock tells the shell once Hyprland holds
  the lock (`qs ipc call lockscreen hold <pid>`); `Lockscreen.qml` then keeps
  every notification card, critical ones included, off screen with its
  timeout stopped, holds calendar reminders and the digest as during
  fullscreen, and sends the lock the count. All of it arrives when the lock
  process exits, however it exits. If it dies while Hyprland stays locked,
  the cards are released behind the dead lock.
- **Before sleep.** The shell holds a logind delay inhibitor ("Desktop shell",
  `systemd-inhibit --list`). When logind announces sleep it starts the lock
  and releases the inhibitor once the lock is up, so the machine wakes
  locked, whatever started the suspend. logind waits at most
  `InhibitDelayMaxSec` (5 s) for that. The watch for logind's announcement
  (`gdbus monitor`) is started again 5 s after it ends, with a warning in
  the shell's log. Untested on this machine, whose eGPU does not come back
  from sleep.
- **Preview.** With `DESK_LOCK_PREVIEW=1` in its environment, `lock.qml`
  shows the same faces as an overlay on DP-2, with no session lock and no
  keyboard, driven by its IPC preview functions.

### If the lock screen dies

Hyprland keeps the session locked when the lock process exits without
unlocking, and shows its own "lock screen died" picture. Recover from a text
console:

1. Ctrl+Alt+F4 and log in as matteo.
2. Run `desk-unlock`. It prints whether Hyprland is locked, stops what is
   left of the lock (`systemctl --user stop desk-lock`), and asks Hyprland to
   drop the dead lock (`hyprctl --instance 0 eval
   'hl.clear_crashed_lockscreen()'`, which Hyprland refuses while a lock
   process still holds the lock; the script then kills it and tries again).
3. When it prints `Hyprland says locked: false`, type `exit` and press
   Ctrl+Alt+F1 (Hyprland is on VT 1).

Any logged-in text console bypasses the lock: Hyprland switches VTs even while
locked. Log out of consoles when done.

## single-monitor

`single-monitor <command>`, for example as a Steam launch option
(`single-monitor %command%`), runs the command with DP-2 off and puts the
layout back when it ends, by exit, crash or signal (`display-layout`,
`hosts/BrightFalls/display-layout.sh`, through `hyprctl --instance 0`).

- **While it runs** Hyprland moves workspaces 6 to 10 and their windows onto
  DP-1; Super+6 … Super+0 show them there, and one first opened meanwhile is
  created on DP-1. Workspaces 1 to 5 are untouched.
- **When it ends**, `display-layout restore`: DP-2 back on, which returns
  workspaces 6 to 10 to it (including any created meanwhile, by their rule in
  `monitors.lua`); then `hyprctl reload`, which drops the rule
  `single-monitor` set. Each monitor then shows the workspace it showed
  before. The reload also ends game mode.
- A second `single-monitor` started inside the first only runs its command.
- Every rule the script sets states `disabled`: `hl.monitor` in a running
  session starts from the output's existing rule and changes only the fields
  given. Each comes with a short Hyprland notification, because a new monitor
  rule takes effect only when a monitor next draws a frame.

**Restoring by hand**, if DP-2 stays off:

- **Super+Shift+D** runs `display-layout restore`. It is in `rescue.lua`, out
  of reach of live edits, and works while locked. With nothing to restore it
  changes nothing; if the config reload fails, it sets the layout directly.
- **Super+Shift+R** (reload) applies `monitors.lua`, as long as the config
  parses.
- A new session always starts with `monitors.lua`'s layout.
- From a text console (Ctrl+Alt+F4, log in as matteo) or over SSH:
  `display-layout restore` or `hyprctl --instance 0 reload`, then `exit` and
  Ctrl+Alt+F1.

`HDMI-A-1` in `monitors.lua` is a 4K dummy plug on the eGPU, declared disabled
so it never takes part in the layout.

## Calendar events

The calendar panel reads one file that a user service refreshes from the
CalDAV account. Defined in `calendar.nix`; the export step is
`calendar-export.py`, built by `calendar-export.nix`.

```
CalDAV server ──pimsync, one way──▶ ~/.local/share/calendars/       (vdir, never edited here)
                                    │ calendar-export: copy + time-zone fix
                                    ▼
                                    ~/.cache/calendar-sync/vdir/    (derived copy; khal.db beside it)
                                    │ khal list, once per sync
                                    ▼
                                    ~/.cache/desk/calendar/events.jsonl ──▶ panel
```

- `calendar-sync.service` (oneshot): `pimsync sync` with
  `~/.config/pimsync/pimsync.conf`, then, only if that succeeded,
  `calendar-export` as `ExecStartPost`. A failed or offline sync leaves the
  last export in place. pimsync's state is in `~/.local/state/pimsync/`.
  `TimeoutStartSec=15min`, which systemd applies to the sync and to the
  export separately: a run that hangs fails, and the timer starts the next
  one.
- An `.ics` file that is not UTF-8 or not iCalendar is skipped and the rest
  are exported; one already exported drops out of the export once it turns
  bad. When any is skipped, the export prints
  `calendar-export: .ics files skipped (not UTF-8 or not iCalendar): N` to
  the unit's journal, with no file or calendar name. A skipped file is tried
  again on every run.
- `calendar-sync.timer`: 1 minute after the graphical session starts, then at
  every tenth minute of the clock, catching up after suspend (`Persistent`).
- Force a sync: `systemctl --user start calendar-sync.service` (the panel's
  R does the same). It blocks until done; `systemctl --user status
  calendar-sync` and `journalctl --user -u calendar-sync` show the outcome.
- khal is run once per sync rather than per question because its Python
  start-up alone is about 200 ms.

### Read-only, and where each guarantee is set

- `read_only` on the remote storage (`pimsync.conf`, from `calendar.nix`):
  pimsync refuses any write to the server.
- `one_way` on the pair: pimsync plans writes to the local side only; a local
  edit, deletion or new file is reverted on the next run. `pimsync sync -n`
  does not take `read_only` into account, so this is also what keeps a dry
  run's plan local.
- `on_empty sync` on the pair: a calendar emptied on the server is emptied
  locally too (the default would keep stale events). Under `one_way` it can
  only touch the local side.
- `collections from a`: every calendar on the account, found by
  `discovery principal`; nothing local is ever offered to the server.
- The export never writes the vdir. It reads it and keeps its own copy under
  `~/.cache/calendar-sync/`, where the time-zone fix is applied (editing the
  vdir would be reverted by pimsync and would count as a local change).
- Creating or changing events stays in the web calendar.

### Secrets

Three agenix files, encrypted to the BrightFalls host key only
(`secrets/secrets.nix`) and decrypted at activation to
`/run/agenix/brightfalls/caldav-{url,user,password}`, owner `matteo`, mode
0400 (`age.secrets` in `flake.nix`):

| File | Holds |
|------|-------|
| `caldav-url.age` | the CalDAV base, `https://<host>/remote.php/dav/` |
| `caldav-user.age` | the account's user name |
| `caldav-password.age` | an app password made for this sync |

pimsync reads each with `cmd cat <path>`; a trailing newline is tolerated.
`~/.local/share/desk/calendar/source.json` (`{"url_file": …}`) tells the
panel where the URL file is, for opening the web calendar; the address
itself is in no file of this repository. Any program running as `matteo` can
read all three.

To recreate one (a new file needs only the public key, so no identity):

```bash
cd secrets
rm brightfalls/caldav-password.age
printf '%s' '<value>' > /tmp/v   # then:
EDITOR="cp /tmp/v" nix run --inputs-from .. agenix -- -e brightfalls/caldav-password.age
rm /tmp/v
```

Commit the `.age` file and deploy; the next sync uses it.

### The export file

`~/.cache/desk/calendar/events.jsonl`, replaced atomically (temporary file in
the same directory, then rename) after every successful sync; absent until
the first. The panel's file watch survives the rename.

- Line 1, the header: `{"version": 1, "window_start": "YYYY-MM-DD", "days":
  N, "generated": "<ISO 8601 with offset>", "calendars": [{"name", "color"},
  …]}`. `calendars` lists only calendars with at least one entry in the
  window, in the server's order (pimsync's `order` file per calendar).
  `generated` is the time of the export, so of the last good sync.
- Lines 2 to N+1: one JSON array per day, line i+2 being day
  `window_start + i`, `[]` for an empty day. Each element has the string
  fields khal 0.14.1 prints with ISO formats: `start`, `end` (`YYYY-MM-DD
  HH:MM` local time, or `YYYY-MM-DD` all-day with an inclusive end),
  `all-day` (`"True"`/`"False"`), `title`, `calendar`, `calendar-color`,
  `uid`, `cancelled` (`""` or `"CANCELLED"`), `location`,
  `tz-unresolved` (`"True"`/`"False"`, below) and `alarms` (a list of
  `YYYY-MM-DD HH:MM` local times, below). A multi-day event appears on
  every day it touches with its original start and end, and the same
  `alarms`. Cancelled events and occurrences are included. A reader that
  finds no `alarms` treats it as `[]`; the header's `version` stays 1.
- Window: the first day of the month three months back to the last day of
  the month twelve months ahead.

### Time zones

khal reads a time whose `TZID` it cannot resolve in the local zone. Two
kinds occur in the synced data, neither with a `VTIMEZONE`:

- `GMT+hhmm` / `GMT-hhmm`: a fixed offset east (`+`) or west of UTC. The data
  shows the sign's meaning: Central European events say `GMT+0100` in winter
  and `GMT+0200` in summer. In the derived copy, `calendar-export` adds a
  fixed-offset `VTIMEZONE` for each such ID that a file uses, and changes no
  other byte, so khal converts them correctly.
- Anything else that is not an IANA or Windows name and has no `VTIMEZONE`
  (IDs a booking system made up): unresolvable. khal's fallback stays,
  and every entry of such an event gets `"tz-unresolved": "True"`. The test
  is khal's own (icalendar in pytz mode, same versions), applied to
  `DTSTART` and `DTEND`, per UID.

The derived copy is rewritten per file only when the vdir file's mtime
changes, and keeps that mtime, so khal re-indexes only what pimsync changed.
khal rescans a calendar only when its directory's mtime changes, so a
rewrite goes through a new file and a rename, which changes it; a run that
rewrites nothing leaves the directories alone and khal skips the rescan.
After a change to the rewrite, bump `COPY_FORMAT` in `calendar-export.py` to
rebuild the copy.

### Reminders in the export

`alarms` holds the moments this occurrence's own reminders fire, sorted and
without duplicates; `[]` when it has none. khal does not print alarms, so
`calendar-export` reads the `VALARM`s from the derived copy and attaches them
to khal's entries:

- Only `ACTION:DISPLAY` and `ACTION:AUDIO` count. E-mail alarms and Apple's
  `ACTION:NONE` placeholders are left out.
- Which `VEVENT` an entry belongs to: same calendar and `UID`; if an
  override (`RECURRENCE-ID`) of that UID has a `DTSTART` that, printed the
  way khal prints it, equals the entry's `start`, the override's alarms are
  used (none if it has none), otherwise the master's. The script never
  expands a recurrence itself: khal decides which occurrences exist (RRULE,
  RDATE, EXDATE, moved and cancelled ones), and the alarms follow its list.
  An override moved onto the exact start of another, unmodified occurrence
  of the same series would give both its alarms.
- A relative trigger is added to the entry's local wall-clock `start`, or
  `end` with `RELATED=END`, so "1 day before" keeps its hour across a
  clock change. An all-day entry starts at local midnight of its first day
  and ends at midnight after its last, so `TRIGGER:PT9H` is 09:00 on the day
  and `-PT15H` is 09:00 the day before.
- An absolute trigger (UTC, as RFC 5545 requires) is converted to the local
  zone; it is the same moment for every occurrence of a series.
- `REPEAT:n` with `DURATION:d` adds n more firings, d apart.
- Seconds are dropped. The local zone is khal's `local_timezone`, read from
  the khal config the script is given.

Nextcloud's default reminders are added only by its web app, to events
created there; events from phones, imports and invitations carry only the
alarms their client wrote, and the export reflects exactly that.

### Switching to vdirsyncer

If pimsync is dropped, only the sync half changes: vdirsyncer writes the same
vdir layout, and khal and the export read it as before. Replace the
`pimsync.conf` and `ExecStart` with a vdirsyncer config holding the same
guarantees: a `caldav` storage with `read_only = true` and `url.fetch`,
`username.fetch` and `password.fetch` each `["command", "cat", "<path>"]`; a
`filesystem` storage at `~/.local/share/calendars/` with `fileext =
".ics"`; a pair with `collections = ["from a"]` and `metadata = ["color",
"displayname"]`. Under `read_only`, vdirsyncer reverts local changes by
default (`partial_sync = "revert"`). Run `vdirsyncer discover` once, then
`ExecStart = vdirsyncer sync` followed by `vdirsyncer metasync` (colours and
names are a separate step there). vdirsyncer does not write the `order` file,
so the header's calendar order falls back to directory names.

## Office: desk-mqtt

`desk-mqtt` (`desk-mqtt.py`, `desk-mqtt.nix`) is the helper behind the
[office panel](#office-panel): one long-running process the
shell starts, as it starts `desk-bt-agent`, speaking JSON lines on stdin and
stdout. It watches one light, one blind and five sockets on Zigbee2MQTT
through the MQTT broker on Nexus, and sends commands to the light and the
blind only. The full protocol, every event and command with its fields, is
the docstring at the top of `desk-mqtt.py`.

- **In**: `<base>/bridge/state`, `<base>/bridge/devices`, and per device
  `<base>/<name>` and `<base>/<name>/availability`. Zigbee2MQTT retains all
  of them and stamps device state with `last_seen`, so a fresh start shows
  every device's last value and age at once. `{"event": "synced"}` comes 1 s
  after the subscription is acknowledged (Mosquitto writes retained messages
  after the SUBACK); a device with no values by then has nothing retained.
- **Out**: only `<base>/<light>/set` and `<base>/<blind>/set`, at QoS 0, once
  per command, never retried. Commands: light `on`, `off`, `brightness`
  1..254 (also switches it on); blind `open`, `close`, `stop`, `position`
  0..100. A command is confirmed by the device's next non-retained state
  showing the result within 5 s, else reported not confirmed. No `/get` is
  ever sent: retained state makes it unnecessary.
- **Walls**: sockets have no command at all (`COMMANDS` in `desk-mqtt.py` has
  no socket entry, and its single `publish` call asserts the kind); anything
  outside the command language is refused with a reason; a command is also
  refused while the broker is down, Zigbee2MQTT is offline, the device is
  offline, or `bridge/devices` does not show the target as a light (or a
  cover), so a config naming a socket as the light still cannot switch it.
  `--read-only` refuses every command; it is how the helper is run against
  the real broker during development.
- **Broker**: retried every 10 s; `broker` events say whether it was ever up
  and since when it is down. No ACL on the broker narrows what this machine
  may publish; the helper's allowlist is the only wall.
- **Cost**: 0.01 s CPU over 60 s and about 32 MB resident, read-only against
  the real broker with all seven devices reporting.

### Device list and secret

The repository holds only ids, kinds and labels (`desk-mqtt.nix`: `light`,
`blind`, and sockets `pc`, `egpu`, `desk1` to `desk3`). The broker and the
Zigbee2MQTT names are in `secrets/brightfalls/office-mqtt.age`, encrypted to
the BrightFalls host key and decrypted to `/run/agenix/brightfalls/office-mqtt`
(owner `matteo`):

```json
{"host": "<broker>", "port": 1883, "base": "zigbee2mqtt",
 "topics": {"light": "<name>", "blind": "<name>", "pc": "<name>",
            "egpu": "<name>", "desk1": "<name>", "desk2": "<name>",
            "desk3": "<name>"}}
```

Without the file the helper says `{"event": "config", "state": "missing"}`
and refuses every command; a malformed one gives `"invalid"` with the key at
fault (never a value). To recreate it (needs only the public key):

```bash
cd secrets
rm brightfalls/office-mqtt.age
EDITOR="cp /tmp/v" nix run --inputs-from .. agenix -- -e brightfalls/office-mqtt.age
rm /tmp/v
```

with the JSON written to `/tmp/v` first.

## Fleet: desk-fleet

`desk-fleet` (`desk-fleet.py`, `desk-fleet.nix`) is the helper for the fleet
panel: one long-running process, JSON lines on stdin and stdout like
`desk-mqtt`. For each host it says what the host runs, what its comin is
doing and what a reboot would change, picks the one chip that most wants
attention, and lists the actions allowed now with a reason for each one that
is not. It runs the panel's few deploy actions. The full protocol is the
docstring at the top of `desk-fleet.py`; the rules for every line and chip
are in `host_row()`.

- **Hosts**: this machine, then the hosts it may SSH into (`lib/ssh-mesh.nix`),
  with their kind and darwin flag from `lib/host-kinds.nix` (shared with the
  herdr workbench), generated into the package at build time.
- **Probing**: one read-only command per host (`PROBE`): this machine through
  `sh`, the others through `ssh -o BatchMode=yes -o ConnectTimeout=5`, in
  parallel, each row sent as it lands. GitHub (master, deploy, the testing
  branches, the last `build.yml` run on master, how far deploy is behind)
  through `gh`; a GitHub failure is its own event and the hosts are still read.
  Every 5 minutes, every 60 s while the panel says it is open, on `refresh`,
  and every 5 s for a host whose deploy the panel started, until comin has
  been idle for 20 s (at most 30 minutes).
- **Systems, not commits**: the running system's store path is looked up in
  comin's deployments and generations (comin's "dummy" deployments for a
  booted system it never deployed do not count). A newer commit that builds
  the same system is up to date; a hand build or a testing branch is never
  behind.
- **Next boot** is read without root as follows. The boot loader's default is
  set by whoever installed it last: comin's newest boot or switch deployment,
  or a hand `nixos-rebuild switch`/`boot`, which also moves the readable
  `/nix/var/nix/profiles/system` link (comin uses its own profile). So
  comin's staged system is the next boot only while that link is older than
  comin's deployment and no `LoaderEntryDefault`/`LoaderEntryOneShot` EFI
  variable is set; otherwise the row says `unknown`. A hand switch run
  straight from `switch-to-configuration` is not seen.
- **Testing branches on a manual host** are held for confirmation like any
  other commit (comin submits every built generation to its deploy
  confirmer), and comin deploys them with `test` however they are released,
  so `boot` is refused for a held testing generation.
- **Actions**: `switch`, `boot`, `mode` and `reboot` run `comin-deploy` or a
  reboot on the host (`systemctl reboot` here, which logind allows from the
  active session; `sudo -n systemctl reboot` elsewhere), in a tmux session of their own on a
  private socket (`$XDG_RUNTIME_DIR/desk-fleet/tmux.sock`, tmux pinned in the
  package), with no window; `attach` shows that session in Ghostty, running
  or finished, until the next action on the host replaces it. A remote reboot whose
  sudo wants a password runs again as `sudo systemctl reboot` in the same
  session, opened in Ghostty for the password. `diff`
  (`nix store diff-closures`) and `ssh` open in Ghostty at once.
- **Walls**: a host command runs only if the host's latest row allows it,
  `switch` and `boot` only with the generation the row holds; anything else
  is refused with a reason. A host with an action running is `busy` for
  every action but `diff` and `ssh`, also while its tmux session from an
  earlier helper still runs without an exit code, so a restart of the shell
  (which restarts the helper) cannot start a second action over the first.
  A restarted helper does not follow or report that earlier action;
  `attach` still shows it. The only strings that reach a host's shell are
  fixed commands plus a generation uuid, a mode from the row's list, or a
  system store path, each checked. `--read-only` refuses `switch`, `boot`,
  `mode` and `reboot` ("read-only") and runs nothing for them; probes, `diff`,
  `ssh` and `attach` still work, and `hello` says which mode it is in.
- **Rows** are final text for the panel. Each line has its full `text` and
  `first`, the text's first line, so a long error (a Nix eval trace) can be
  folded.
- **From the system, not pinned**: `ssh` and `ghostty` (the ones the mesh
  and the desktop are configured with), and `comin` and `comin-deploy` (each
  host's own).

## Tokens: desk-tokens

`desk-tokens` (`desk-tokens.py`, `desk-tokens.nix`) is the helper for the
token panel: JSON lines on stdin and stdout like `desk-fleet`, started when
the panel opens and stopped when it closes. It counts Claude Code's replies
from the transcripts into an index of its own and answers the panel's pages:
the overview, the projects of a period, one project, and the last 14 days.
The full protocol is the docstring at the top of `desk-tokens.py`.

- **What it reads**: only `*.jsonl` files at three places under
  `$CLAUDE_CONFIG_DIR/projects` (else `~/.claude/projects`): a session's main
  transcript `<key>/<session>.jsonl`, a sub-agent's
  `<key>/<session>/subagents/agent-*.jsonl` and a workflow sub-agent's
  `<key>/<session>/subagents/workflows/<name>/agent-*.jsonl`. A line is
  parsed only if its bytes contain `"usage"`; from an assistant record it
  keeps the six usage counters, the model, the timestamp, `message.id`,
  `requestId`, `sessionId`, `isSidechain` and `cwd`, and drops the rest.
- **What it never reads**: message content, tool input or output, titles,
  slugs, branch names; a workflow's journal, `.meta.json`, `tool-results/`,
  `memory/`; Claude Code's account files. It has no network code and starts
  no process. Nothing from a transcript is printed: errors are counts.
- **The index**: SQLite at `$XDG_STATE_HOME/desk/tokens/index.sqlite` (else
  `~/.local/state/desk/tokens/`), the directory 0700, the file 0600, with a
  schema version (schema 1 is upgraded in place, see "Stored costs"; any
  other version is rebuilt from scratch). One row per
  reply, keyed `message.id:requestId`, holding only ids, a working
  directory's row, model name, time, counters and costs; a row per transcript (path,
  inode, the byte after the last complete line read); folds and projects.
  Each sync reads a file from that byte; a file that shrank or got a new
  inode is read again from 0. A reply seen again (the streaming lines of one
  reply, a resumed or forked session) merges by per-field maximum, so reading
  twice never counts twice, and the smallest session id keeps it. Lines
  without both ids and `<synthetic>` replies are skipped and counted. A
  transcript Claude Code deletes keeps its replies in the index. Sessions,
  active time and projects are computed from the reply rows at each request,
  so they are the same however the files were read.
- **Sub-agents** count in their parent session (`sessionId`) and its
  project, flagged: they add to the session's output, not to its replies or
  its active time (the gaps under 10 minutes between main-conversation
  replies).
- **Days** are calendar days in the local time zone; "7 days" is today and
  the 6 days before it, and so on. A first run reads the newest files first,
  so today, 7, 14 and 30 days become complete in turn (a file last written
  before a period began cannot hold its replies); a page asked before its
  period is complete gets a "not ready" answer with the progress. It commits
  between files, at least every half second, and before saying a period is
  complete; a SIGTERM rolls back what was read since the last commit, which
  the next run reads again.
- **Projects** (`fold_cwd()`): a session belongs to the project of the
  working directory of its first main-conversation reply. `/tmp/tmp.*` is
  one project, "temporary directories". A `/tmp/claude-<uid>/<key>/…`
  scratch directory folds by name on `<key>`. An existing directory folds
  to its nearest `.git`: a `.git` directory is the project, a `.git` file
  pointing into `<repo>/.git/worktrees/` folds into `<repo>`, any other
  `.git` file (a submodule) is its own project; with no `.git` it is its own
  project. A gone `<repo>/.claude/worktrees/<name>` folds as `<repo>`. Any
  other gone directory is encoded like Claude Code's keys (every character
  but ASCII letters and digits to `-`) and folds into the known checkout
  whose encoded path is its longest prefix followed by `-`; with none it is
  its own project. A fold read from the file system is kept for good, so a
  worktree removed later stays with its repository; a fold by name is tried
  again at every sync, as more checkouts become known.
- **Known wrong folds**: a removed separate repository `repo-x` folds into
  a checkout `repo` (as does `repo.x`); a repository with no checkout left
  stands alone under its directory; a renamed repository splits in two; a
  session that changes directory stays with its first; a scratch key whose
  directory had no git (the home folder, say) stands alone under its
  encoded key.
- **Prices**: `desk-tokens-prices.json`, built in (`--prices` overrides it):
  USD per million tokens for input, output, 5-minute and 1-hour cache
  writes and cache reads, with the page they were read from and the date. A
  model id with a `-YYYYMMDD` suffix takes its base id's row. A tier
  (`above`, Haiku 5.5's prompts over 100,000 tokens) applies to a whole reply
  whose prompt (input, cache reads and both cache writes) is longer; there is
  no other tier. Batch, data-residency and fast-mode multipliers are not
  applied. A model missing from the table is reported by name and its tokens
  are not priced. The dollar figure is an estimate of what the same use
  would cost at API list prices, not a bill.
- **Cost fields**: every token quantity in an answer has a `cost` object
  beside it: `usd`, the sum over the replies that had a price; `priced`,
  false when there were replies and none had a price (then `usd` is 0.0 and
  not a figure); `partial`, true when some had none. A period with no
  replies is priced at 0.0. The 30-day totals and a project's totals add
  `by_type` (USD per token type, summing to `usd`), and the answers list the
  period's `unpriced_models`, never added to any figure. A session's cost
  covers its sub-agents, like its output; a day's cost follows local days.
  The overview keeps `last30.cost_usd`, the same value as `last30.cost.usd`.
- **Stored costs**: each reply's five costs and their sum are stored in its
  index row when it is read (NULL for an unpriced model), and window queries
  read them from a covering index, so an answer prices nothing. The index
  remembers a hash of the price table's rates; when the helper starts with a
  table whose hash differs, it reprices every reply from the stored counters
  in one transaction, reading no transcript. An index from before costs were
  stored (schema 1) gains the columns in place and is priced the same way,
  not rebuilt.

## Tailscale: status and mesh hosts

`user/quickshell/tailscale/tailscale.js` holds every decision of the
Tailscale panel, a read-only view of this computer and every device in the
tailnet. It takes the result of one `tailscale status --json` call (stdout,
exit code, stderr, whether it timed out, whether it was the light
`--peers=false` call) and returns what the panel and its bar item draw. The
returned shapes are the comment at the top of the file.

- **States**: no answer yet; the daemon not running; the call failing, hanging
  or printing something that is not status JSON (the last good list is kept,
  greyed, "as of" its time); and every `BackendState`, with logged out, login
  started and this computer's key expired told apart. Rows are live only in
  `Starting` and `Running`; in the other states with a map they are greyed.
- **Lines over any state**: each `Health` string whole, this computer not
  connected to control, its key within 14 days of expiry, an exit node in use
  or offline, an urgent security update, a newer version (which comes only
  with a flake update: `tailscale update` refuses on NixOS).
- **Rows**: "My hosts" (peers whose MagicDNS name is in the mesh-host file,
  under the repository's name and Fleet's glyph for their kind), then "Other
  devices"; online first, then by name. One chip per row by priority
  (Expired, Exit node down, Expiring, Offline, Exit node, Direct, Peer
  relay, Relayed, No path, Idle), a second line, details, and what can be
  copied. Peers `tailscale status` hides are hidden too (sharee nodes,
  Mullvad exit nodes not in use).
- **Never read**: `User` (login and display names), the tailnet's name,
  capabilities, Taildrop, location, SSH host keys. No person's or tailnet's
  name can reach the screen.
- **Keys**: navigation by peer ID across reads, Enter folds, Y opens a copy
  chooser (name, DNS name, IPv4, IPv6, each only when it exists) or copies
  `sudo tailscale login` while logged out, T opens `ssh <alias>` in Ghostty
  for an online mesh host that runs sshd, O opens the admin console (the
  login page while one is pending), F5 reads again. A key that does not apply
  gives the reason. Nothing writes to the daemon.
- **Mesh hosts**: `~/.local/share/desk/tailscale/hosts.json`, generated in
  `default.nix` from `lib/ssh-mesh.nix` and `lib/host-kinds.nix`: for each
  host with a `tailscale` name, `{ label, dns, alias, sshd, device }` (the
  SSH alias is its `principal`; `sshd` is whether it has a `port`). With no
  file, every peer is another device and T is never offered.

## Tests

Flake checks, defined in `tests/default.nix`; one is built with `nix build
.#checks.x86_64-linux.<name>`. `nix build -L
.#checks.x86_64-linux.brightfalls-tests` builds all of them but
`hypr-config`; a check added to `tests/default.nix` is in it with no other
edit. That attribute is what the `brightfalls-tests` job builds on every
pull request (`.github/workflows/pr-build.yml`), a required check for
merging into `master`. `hypr-config` is run by hand before a change to the
Hyprland config, not in CI: Hyprland's verify crashes (exit 139) on the full
config on GitHub's runners, cause not known.

- `nix build .#checks.x86_64-linux.desk-sync`: runs `tests/run.sh` against a
  temporary HOME: activation's table (a live symlink out of the store and a
  live directory at a file's path included), `status`, `reset`, and `pull`
  (a file with a newer copy in `incoming/` refused, the rest copied; the
  secret scan on added lines only, with the live file's line numbers).
- `nix build .#checks.x86_64-linux.calendar-export`: exports
  `tests/calendar/fixtures/` (five calendars: a weekly series with an
  EXDATE, a moved and a cancelled occurrence; New York; all-day, multi-day
  and midnight-crossing events; a cancelled event; an empty calendar;
  `GMT±hhmm` and custom zones; a daily all-day series with a cancelled
  occurrence; and `fixE`, one event per alarm shape above, including a
  series whose overrides have their own alarm and none, an e-mail alarm and
  Tokyo) as of 2026-11-15 and compares with `tests/calendar/expected.jsonl`.
  It then exports a changed copy again into the same work directory (a
  calendar and a file removed, two files edited) and compares with a run
  from scratch, and checks that a copy made by an older format is rebuilt,
  that a run with nothing changed leaves a calendar's directory mtime alone
  and that a later edit to an already copied file still reaches the export.
  Last, a calendar with a file that is not UTF-8 and one that is not
  iCalendar must export the same as without them and print the skipped
  count with no file name, and an exported file turned unreadable must drop
  out. No network, no secrets. About 5 s. To regenerate the expected file after an intended
  change, run the built `calendar-export` with
  `CALENDAR_NOW=2026-11-15T10:00:00+00:00`, a khal config from
  `calendar-export.nix` and that file as the output, and review the diff.
- `nix build .#checks.x86_64-linux.calendar-panel`: runs
  `user/quickshell/calendar/queries.js` under node against invented events
  (`tests/calendar/panel/`, written by `make-fixture.js` and
  `make-reminders-fixture.js` there, plus a small export built inline for
  markup in titles and calendar names, unlisted calendars and long
  summaries, and another for the big view: what a day cell shows when its
  events fit or not, the header's week note, and each key's action, its
  move and whether a held key repeats), in London time (the test first
  asserts the zone, so a run in UTC fails rather than pass the
  daylight-saving cases vacuously).
- `nix build .#checks.x86_64-linux.bluetooth-panel`: runs
  `user/quickshell/bluetooth/services.js` and `devices.js` under node
  against invented devices and links (`tests/bluetooth/test-bluetooth.js`):
  service names and questions, kinds, battery tiers, order, the nearby
  filter, low-battery crossings, and what the "uses" lines and glyphs say,
  calls included.
- `nix build .#checks.x86_64-linux.tray-panel`: runs
  `user/quickshell/tray/menu.js` under node (`tests/tray/test-tray.js`): the
  header's name and the entries' check and radio marks, with the button-type
  values read from the installed Quickshell's `quickshell-core.qmltypes`.
- `nix build .#checks.x86_64-linux.common-panel`: runs
  `user/quickshell/common/notify.js` under node
  (`tests/common-panel/test-common.js`): the `gdbus … Notify` arguments it
  builds for the shell's notifications, read back the way gdbus parses them
  (typed and untyped), so that names with quotes, backslashes, newlines or
  the shape of a GVariant value reach the server unchanged. The reader is
  a transcription of glib's parser; the check does not run gdbus. Under 1 s.
- `nix build .#checks.x86_64-linux.office-panel`: runs
  `user/quickshell/office/office.js` under node
  (`tests/office-panel/test-office-panel.js`) against invented helper events,
  inline and as lines hand-written in the helper's format in
  `tests/office-panel/fixtures/` (one file per
  panel state; `"@-N"` in a time means N s before the test's fixed now):
  ages, brightness percent and raw values, steps, the row and header texts,
  locks and their footer texts, banners (connecting included), the sockets'
  total, the bar item, the pending, confirmed, not-confirmed (each
  wording) and refused paths, and a device list with no sockets.
- `nix build .#checks.x86_64-linux.office-helper`: runs `desk-mqtt` against
  a Mosquitto on loopback, with `tests/office/test-desk-mqtt.py` playing
  Zigbee2MQTT under invented names and a spy on `#`: retained state at
  connect and "nothing retained", availability and Zigbee2MQTT offline, a
  confirmed and an unconfirmed command, the blind's close, stop and position
  confirmed, socket and malformed commands refused with nothing published,
  the broker dropping and coming back, the broker unreachable at start and
  refusing the connection, a missing config and each way a config can be
  invalid, read-only, a config that names a socket as the light, malformed
  messages of each kind from the broker (ignored, the helper still
  reports), and the network thread dying (broker down, exit status 1).
  About 45 s.
- `nix build .#checks.x86_64-linux.fleet-panel`: runs
  `user/quickshell/fleet/fleet.js` under node
  (`tests/fleet-panel/test-fleet-panel.js`) against `desk-fleet` lines
  hand-written in the helper's format in `tests/fleet-panel/fixtures/` (built from the helper's example
  rows: every chip, the cases the old panel read wrong, actions, GitHub
  error, refusals, long texts) and inline events: order, header, pipeline,
  folding, keys lit, questions, the command each key sends (the switch's
  generation as given), navigation, footers and the bar item.
- `nix build .#checks.x86_64-linux.tailscale-panel`: runs
  `user/quickshell/tailscale/tailscale.js` under node
  (`tests/tailscale-panel/test-tailscale-panel.js`) against hand-made status
  answers in `tests/tailscale-panel/fixtures/` (invented names, documentation
  address ranges): every panel state (failed calls as stdout, exit code and
  stderr), every line over a state, every chip and second-line combination,
  names, sort and hidden peers, the wording at each boundary, every key's
  decision with the reasons it gives, the bar item for light and full
  answers, and junk input. Under 1 s.
- `nix build .#checks.x86_64-linux.wifi-panel`: runs
  `user/quickshell/network/wifi.js` under node
  (`tests/wifi-panel/test-wifi-panel.js`) against invented networks in
  `tests/wifi-panel/fixtures/` and the module's enum names, copied by hand
  and checked, with `Network.qml`'s four name arrays, against the installed
  Quickshell's `quickshell-network.qmltypes`:
  the section's states, signal tiers, security words, order and the order
  held during a join, the password check, every key and event of the join,
  forget and cancel machine with its effects, footer hints, details and the
  bar item; a sentinel password is checked never to reach state, effects or
  view. Under 1 s.
- `nix build .#checks.x86_64-linux.fleet-helper`: `tests/fleet/test-desk-fleet.py`
  runs `desk-fleet`'s state model against three real probes cut down to the
  fields it reads (`tests/fleet/fixtures/`) and cases built in the test (every
  chip, the cases the old herdr panel read wrong, next boot unknown, Darwin,
  no GitHub, the command gate), then the built helper against fake `ssh`,
  `comin`, `comin-deploy`, `sudo`, `ghostty` and `gh`: refused commands run
  nothing, a switch here is followed every 5 s until comin is idle, mode over
  ssh, a failing action, a reboot whose sudo wants a password, this machine's
  reboot without sudo, attach, diff, ssh, GitHub failing; a multi-line error's
  `first`; a second run with `--read-only` in which every write is
  refused and runs nothing while probes, diff, ssh and attach still work; a
  helper restarted while an action runs, which refuses a second action on
  that host as busy; and shell text in a host's comin answer, which is
  refused and never run.
  About 50 s.
- `nix build .#checks.x86_64-linux.tokens-helper`:
  `tests/tokens/test-desk-tokens.py` runs `desk-tokens`' pure functions
  (line parsing, the read plan, active time, prices and tiers, folding on a
  real directory tree, day boundaries across both daylight-saving changes),
  then the built helper against invented transcript trees: streaming and
  forked duplicates, an offset falling inside a reply, a truncated last line,
  sub-agent and workflow files (journals, `.meta.json`, `tool-results/` and
  `memory/` made unreadable and never opened), skipped lines, shrunk,
  replaced and deleted files, London and Auckland days, distinct sessions,
  active time read in three pieces, folds kept and re-tried, prices, a first
  run's order and readiness with a page asked too early, SIGTERM mid-sync,
  stdin EOF, the index's mode and columns, a source with no network or
  process code, and no line the helper prints (stdout or stderr) holding
  text from a transcript. About 10 s.
- `nix build .#checks.x86_64-linux.tokens-panel`: runs
  `user/quickshell/tokens/tokens.js` under node in New York time
  (`tests/tokens-panel/test-tokens-panel.js`) against `desk-tokens` answers
  hand-written from the helper's contract in `tests/tokens-panel/fixtures/`,
  and progress events and limits files built in the test: every page's view
  and texts, the figures at API prices, keys, footers, the limits file's
  reading and the bar item, with days that cross the daylight-saving change
  of 1 November 2026; the plan's name and price come from `PLAN` itself.
  Under 1 s.
- `nix build .#checks.x86_64-linux.system-panel`: runs
  `user/quickshell/system/decode.js` under node (`tests/system/test-system.js`)
  against invented gpu_metrics blobs (both layouts, unfilled fields, the
  throttle word) and `/proc`, sysfs, `df` and LACT texts: CPU busy time,
  memory, the uplink and its bytes, disk counters and volumes, the PCIe link
  state, AER counts, the LACT fan line, heat levels and the figures' format.
- `nix build .#checks.x86_64-linux.display-layout`: runs
  `hosts/BrightFalls/display-layout.sh` against a fake `hyprctl`
  (`tests/display-layout/run.sh`): usage, the DP-1 and DP-2 rules matching
  `monitors.lua`, restore with nothing to do, after a lost monitor, with the
  capture card on, after a reload that does not parse (direct rules) and
  when nothing comes back (exit 1, layout kept), an eval error, and
  `single`: the command's arguments and status, DP-2 off while it runs, the
  restore and the workspaces put back when it ends, is killed or
  single-monitor itself is terminated, a nested call, and no Hyprland.
  About 1 s.
- `nix build .#checks.x86_64-linux.hypr-config`: lays `user/hypr/`,
  `user/desk/` and `defaults/hypr/` out as installed and runs
  `Hyprland --verify-config` on `hyprland.lua` and on `rescue.lua` and
  `theme.lua` alone, checks that `hyprland.lua` reaches both of those at
  their installed paths (it loads them through `pcall`, so a missing one is
  silent) (`tests/hypr/run.sh verify`). A misspelt key name in a bind
  fails it (`Unknown key`); a mouse button code out of range does not.
  About 1 s once Hyprland is in the store. Not in CI (see above).
- `nix build .#checks.x86_64-linux.hypr-theme`: runs `theme.lua` under Lua
  5.5, with no Hyprland, against the shipped `theme.json` and broken ones
  (alpha, short and named colours, blank fonts, unknown keys, an escaped
  quote, a truncated file, no file, no `XDG_CONFIG_HOME`)
  (`tests/hypr/run.sh theme`). Under 1 s.
- `nix build .#checks.x86_64-linux.quickshell-lint`
  (`tests/quickshell-lint/`): lays `user/quickshell` out as Quickshell's
  scanner does (a `qmldir` per directory, module `qs.<dir>`, `singleton`
  from `pragma Singleton`) and runs Qt's `qmllint` on every QML file with
  Quickshell's installed type files; then checks every `qs ipc call` in
  `bindings.lua`, `rescue.lua` and the QML against the `IpcHandler`s (the
  target and function exist, the argument count matches, every handler
  parameter has a type Quickshell carries, no target is declared twice);
  then plants fifteen faults in copies and fails if any of them passes.
  About 10 s.
  - Catches: syntax errors, an unknown `qs.` import, component or `.js`
    file, a misspelt id, Qt or Quickshell property or singleton member, a
    bind or QML call to a missing target or function or with an argument
    too many, an untyped IPC parameter.
  - Cannot catch: anything at run time (binding loops, JS errors inside
    functions, wrong values or logic, layout, a process that fails to
    start); members read through an outer id inside a delegate (the files
    have no `pragma ComponentBehavior: Bound`, so `root.opne` there passes
    while a misspelt id does not); members of the types the allowlist
    accepts broadly (`screen`, `UntypedObjectModel` values, `margins.*` in
    `Bar.qml`, `Notifications.qml` and `Osd.qml`, the popup anchor in
    `system/Temperatures.qml`); which process an IPC call reaches, calls
    from outside the repository, and argument types; the `.js` libraries'
    own code (the node checks cover their logic). Quickshell's `//@ pragma
    Internal`, `.qml.json`, `//@ if` and hand-written `qmldir` files are
    not reproduced (none is used); one would make the check misreport, not
    pass.
  - Reading a failure: `file:line:col: message [category]` for `qmllint`
    (paths relative to `user/quickshell`), `ipc: file:line: …` for the IPC
    part, `FAIL <plant>` when the check stopped catching a fault class, and
    `allowlist line N matches no warning (remove it)` when an upstream gap
    has closed.
  - Accepted warnings are in `tests/quickshell-lint/allowlist`: one regex
    per line, matched against `file: message [category]` plus the first
    line of qmllint's first suggestion (for "Unqualified access", the
    identifier in quotes after the message), anchored, narrowed to the type
    and member (and the file when the cause is local), with a comment naming
    the upstream gap or qmllint limit. No `// qmllint disable` in the QML.
    After a Quickshell or Qt update, delete the lines reported unused and
    check each new warning against the new `.qmltypes` before allowing it.
  - It reads the repository's `user/quickshell`: a live edit is checked
    after `desk-sync pull`.
- `nix build .#checks.x86_64-linux.desk-unlock`: runs `desk-unlock.sh`
  against fake `hyprctl`, `systemctl` and `pkill`
  (`tests/desk-unlock/run.sh`): a crashed lock cleared at once, a stuck one
  stopped, a hung one refused, killed through its unit and cleared on the
  second try, one outside its unit killed by command line (the pattern
  matching the lock process alone, not the shell or an editor on
  `lock.qml`), one nothing frees, and no Hyprland. The fakes' wording is
  invented; the real `hl.clear_crashed_lockscreen()` refusal has not been
  seen. Under 1 s.
- `nix build .#checks.x86_64-linux.bluetooth-agent`: runs `desk-bt-agent`
  against two private `dbus-daemon`s, with `tests/bluetooth/test-bt-agent.py`
  playing BlueZ on one and PipeWire's telephony service on the other under
  invented addresses: registration as the default KeyboardDisplay agent,
  each request (confirmation accepted and refused, passkey, PIN, service,
  the two display requests), a cancel while a request is open, stale and
  malformed answers, the links at start and as transports, media control,
  PAN and RSSI change, hands-free links and call audio, the telephony
  service leaving and coming back, Release, and stdin closing (unregister,
  `exit`). Under 1 s.
- `nix build .#checks.x86_64-linux.audio-output-cycle`: builds
  `audio-output-cycle` (Super+Shift+O, `../audio-output-cycle.nix`) against
  fake `pw-dump`, `wpctl` and `notify-send` and runs it
  (`tests/audio-output-cycle/run.sh`): the order stereo, surround A,
  surround B and back, a default outside the cycle, a missing surround sink
  skipped, only stereo, no DAC, and the notification replacing the last
  one. Under 1 s.
