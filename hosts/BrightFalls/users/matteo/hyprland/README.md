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
  [Calendar panel](#calendar-panel), [Calendar reminders](#calendar-reminders),
  [System panel](#system-panel), [Bluetooth panel](#bluetooth-panel),
  [Tray menu](#tray-menu)
- [Lock screen](#lock-screen)
- [single-monitor](#single-monitor)
- [Calendar events](#calendar-events) (the sync behind the calendar)
- [Tests](#tests)

## The session

greetd starts the session on VT 1 with `uwsm start -e -D Hyprland
hyprland.desktop`, the command of `hyprland-uwsm.desktop` (`desktop.nix`).
The first login of each boot is automatic, with no password: the login
keyring stays locked until the first unlock at the lock screen, or until an
app asks for it and a prompt takes the password. After a logout, or if the
session ends, tuigreet asks for the password on VT 1 and starts the same
session. The plain `hyprland.desktop` stays installed for `uwsm start`,
with `NoDisplay` so no session chooser offers it
(`desktop-hyprland.nix`). `~/.config/uwsm/env-hyprland` is a read-only Nix-managed
file that points `AQ_DRM_DEVICES` at the udev links `/dev/dri/dgpu` and
`/dev/dri/igpu`.

There is no other desktop. The services the session's apps rely on are
declared in `hosts/BrightFalls/desktop.nix`: gnome-keyring (secret service)
and gcr-ssh-agent (`SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh`), gvfs, udisks2,
upower, dconf, the portals (`hyprland` first, `gtk` for the file chooser
and settings, `gnome-keyring` for secrets), and the apps that stay:
Nautilus, Loupe, Papers, File Roller, Seahorse. GTK and Qt look, the dark
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
`~/.local/share/desk/` (`desktop-hyprland.nix` and `calendar.nix`):
`network/`, `audio/`, `system/` and `bluetooth/locked.json` (values set in
Nix, shown greyed with a `nix` tag) and `calendar/source.json`.

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
  drop its incoming copy, and print what applies it (`hyprctl reload` for
  `hypr/`; nothing for `quickshell/`, which reloads itself). `<path>` is
  relative to `~/.config` (`hypr/bindings.lua`) or the live path.
- `desk-sync pull <checkout-dir>`: copy edited live files into
  `<checkout-dir>/hosts/BrightFalls/users/matteo/hyprland/user/` and print
  `git status --short` for that subtree. No commit. A file with something that
  looks like a secret (a private key block, `password=`/`token:`-style
  assignment, a bearer token, a run of 40 or more letters and digits without
  `-`, `/` or `.`) is not copied; the file and line are named and it exits 1.

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

The five drop-down panels (network, audio, calendar, system, Bluetooth)
behave alike: each opens under its bar item on that bar's monitor (or the
focused monitor from a key or IPC), centred on the item and kept 6 px inside
the screen, with the item marked (purple, underlined) while open. Each takes
the keyboard, closes on Esc or a click outside, and opening one closes the
others (`common/Dropdowns.qml`). Each has an IPC `toggle` (`qs ipc call
<target> toggle`).

| Component | Open | IPC target |
|-----------|------|------------|
| Launcher | Super+Space, the bar's menu button | `launcher` |
| Cheat sheet | Super+K | `cheatsheet` |
| Session menu | Super+Escape, power key | `session` |
| Network | Super+N, bar network icon | `network` |
| Audio | Super+A, middle click on bar audio item | `audio` |
| Calendar | Super+C, bar clock | `calendar` |
| System | Super+Y, bar temperature chip | `system` |
| Bluetooth | Super+B, bar Bluetooth glyph | `bluetooth` |
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
right click opens the item's menu, see [Tray menu](#tray-menu)), the system chip (two temperatures, see
[System panel](#system-panel)), Bluetooth, network, and audio. The audio item
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
- A body shows as many lines as the sender broke it into, from two up to
  eight: a long body with no line breaks shows two lines.
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
output changing (its name), Bluetooth turned on or off. It takes no input and
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
Shut down act on a second press. There is no suspend: the eGPU does not come
back from it.

### Polkit dialog

`Polkit.qml`: the session's polkit authentication agent. Each request is a
modal on the focused monitor with the message, the identity, a password field
and the action id; Enter authenticates, Esc cancels, a wrong password clears
the field and says so. Requests queue and show one at a time. `qs ipc call
polkit cancel` cancels the one showing. Quickshell tries to register the
agent once per process, when `Polkit.qml` first loads, and reloads keep that
registration; if another agent held the session then, it takes a Quickshell
restart.

### Network panel

`Network.qml` (parts in `network/`), a 380 px panel under the bar's network
icon. Wired devices only; Wi-Fi is not built.

- Wired devices first: a connected one shows link speed, IPv4 address and
  its last speed test; Enter opens its details (address, gateway, DNS, MAC,
  link speed and duplex, the last run of each provider). Enter never
  disconnects. Addresses come from `nmcli`, the default route from `ip`,
  duplex from sysfs, all read when the panel opens; the rest from
  `Quickshell.Networking`.
- "Set in Nix": greyed rows from `~/.local/share/desk/network/locked.json`
  (Tailscale on, IPv6 off, Wake-on-LAN interfaces, hostname, firewall on; a
  row only while the setting has that value), each naming the repo file that
  sets it, which Enter shows in the footer.
- Keys: Up/Down move, Enter, Esc closes details, then the panel; S opens the
  speed test chooser.

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
    level monitor.
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
  change month, keeping the day number; T jumps to today; Enter or O opens
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
  start, and the calendar, for example "11:00 – 12:00 · in 60 min · Work".
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
  each second; the open panel reads about 30 small files a second and a few
  every 10 seconds. A sleeping eGPU is not read until it wakes. Memory-module
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
  no lockout; a wrong password costs pam_unix's delay of about 2 s. Then
  `pam_gnome_keyring` hands the same password to the running keyring daemon,
  which unlocks the login keyring if it is locked (it is after the automatic
  login).
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
  `InhibitDelayMaxSec` (5 s) for that. Untested on this machine, whose eGPU
  does not come back from sleep.
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

## Tests

Flake checks, defined in `tests/default.nix`:

- `nix build .#checks.x86_64-linux.desk-sync`: runs `tests/run.sh` against a
  temporary HOME. Also run in PR CI.
- `nix build .#checks.x86_64-linux.calendar-export`: exports
  `tests/calendar/fixtures/` (five calendars: a weekly series with an
  EXDATE, a moved and a cancelled occurrence; New York; all-day, multi-day
  and midnight-crossing events; a cancelled event; an empty calendar;
  `GMT±hhmm` and custom zones; a daily all-day series with a cancelled
  occurrence; and `fixE`, one event per alarm shape above, including a
  series whose overrides have their own alarm and none, an e-mail alarm and
  Tokyo) as of 2026-11-15 and compares with `tests/calendar/expected.jsonl`.
  No network, no secrets. To regenerate the expected file after an intended
  change, run the built `calendar-export` with
  `CALENDAR_NOW=2026-11-15T10:00:00+00:00`, a khal config from
  `calendar-export.nix` and that file as the output, and review the diff.
- `nix build .#checks.x86_64-linux.calendar-panel`: runs
  `user/quickshell/calendar/queries.js` under node against invented events
  (`tests/calendar/panel/`, written by `make-fixture.js` and
  `make-reminders-fixture.js` there), dates in London time.
- `nix build .#checks.x86_64-linux.bluetooth-panel`: runs
  `user/quickshell/bluetooth/services.js` and `devices.js` under node
  against invented devices and links (`tests/bluetooth/test-bluetooth.js`):
  service names and questions, kinds, battery tiers, order, the nearby
  filter, low-battery crossings, and what the "uses" lines and glyphs say,
  calls included.
- `nix build .#checks.x86_64-linux.tray-panel`: runs
  `user/quickshell/tray/menu.js` under node (`tests/tray/test-tray.js`): the
  header's name and the entries' check and radio marks.
