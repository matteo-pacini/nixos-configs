# Agent instructions: the BrightFalls Hyprland session and its Quickshell shell

Read this before any work on the Hyprland session on BrightFalls or on its
desktop shell (Quickshell), including work that starts in the live
`~/.config/quickshell` or `~/.config/hypr` and never touches this directory.
What each piece is and how it works is in [README.md](README.md); this file
is how to work on it. Repo-wide rules are in the root `AGENTS.md`.

State as of 2026-11-15 (end of the build, PR #479). "State and open work" at
the bottom says what is unproven; check it before relying on anything.

## What this is

A Hyprland 0.57 session under UWSM, the only desktop on the machine, started
by greetd (automatic login once per boot, tuigreet after a logout), with a
desktop shell written in
QML for Quickshell 0.3.2: bar, launcher, notifications, OSD, cheat sheet,
session menu, polkit dialog, network, audio, calendar, system, Bluetooth and
office panels, tray menus, and a lock screen.

- **Nix** (`hosts/BrightFalls/desktop-hyprland.nix` for the system,
  `default.nix` here for the user) pins the packages, declares services,
  secrets, PAM, and generates read-only data the shell shows.
- **The config files** are ordinary writable files under `~/.config`, copied
  from `user/` here at activation and hot-reloaded. They are developed live
  and brought back to this directory with `desk-sync pull`. README:
  "Two layers", "Activation", "desk-sync", "Editing live".

So most changes are a live edit first and a repository change second, and
some need both halves at once (a panel plus the Nix file that feeds it).
Decide which half a change belongs to before starting.

## How to work here

The work is run by a **coordinator** session that talks to the user, writes
briefs and merges, and **agents** that do one piece each. If you are an
agent, you have a brief; follow it and this file. If you are working alone
with the user, you are both: keep the same discipline.

- **Pictures before code.** Anything the user will see starts as a published
  page of drawn options with numbered decisions and a recommended pick. The
  user picks; the chosen design is redrawn with all its states; only then is
  it built. Render the page locally (headless Chromium) and look at it before
  publishing it.
- **Spike before build** when the mechanism is unknown (it was for calendar
  sync, system sensors and Bluetooth pairing): a read-only investigation that
  proves the mechanism with evidence and builds nothing permanent. Its report
  decides the design; the build brief cites it.
- **One live writer at a time.** Only one agent edits the live
  `~/.config/quickshell` and `~/.config/hypr` at once: every save reloads
  the user's running shell, so two writers break each other's tests.
  Repository-only and research agents can run beside it. When two agents
  build two halves of one feature (say, a sync service in the repository and
  its panel live), they share a written **contract** (file formats, paths,
  commands); only the coordinator changes it.
- **Brief in, report out.** An agent gets one brief file, writes one report
  file, and sends one line when done (`hc send <coordinator> "…"`). The
  report lists live files edited and created (full paths, and whether each
  new file is hand-written or generated data), decisions with the source
  checked, what was verified with the decisive output, what is only
  expected, temporary things to remove, and how the user tests it by hand.
- **Bringing work back is the coordinator's job**, not the live agent's:
  `desk-sync pull <worktree>` for files already in the manifest, a hand copy
  into `user/…` for files created live, then `diff -rq` of the live tree
  against `user/` must be silent, then a grep for leftovers (test IPC
  targets, overrides, temporary paths) before the commit.
- **Deploys are the user's.** Commit when asked; give the switch command for
  the worktree they deploy from, never "pull" (the commits are already
  there). Wait for them to say it is deployed before checking it live.

### The user's desktop is in use

The user works at this machine while agents test on it. These rules are the
user's and are strict:

- **Keyboard focus, one thing at a time.** Before opening anything that
  takes keyboard focus (every drop-down panel, the launcher, the cheat sheet,
  the session menu, the polkit dialog), send a desktop notification
  **10 seconds before** saying what opens and for how long, do the job,
  close it, then send a second notification that the keyboard is free.
  Batch your looks into one window. Keys the user types otherwise land in
  your panel (it happened, and a speed test ran because of it).
- **Prefer checks that need no focus**: an IPC function that returns state,
  a temporary no-focus preview mode, the service log, `hyprctl layers`. The
  bar takes no focus and can be screenshotted any time.
- **Tests that need the user** are announced through the coordinator first,
  with an estimate and the number of steps, and start only on the user's go.
- **Instructions go through the coordinator in chat**, one step at a time,
  each acknowledged. A notification is not a channel for them: a body with
  no line breaks shows two lines and the rest is cut.
- Sending a notification from a script: `gdbus call --session --dest
  org.freedesktop.Notifications --object-path /org/freedesktop/Notifications
  --method org.freedesktop.Notifications.Notify …` with the timeout written as
  `int32 -1` (a bare `-1` is read as an option). `notify-send` is not on the
  agents' PATH.

### What an agent may do in the live session

- May: edit files under `~/.config/quickshell` and `~/.config/hypr`; read-only
  `hyprctl` queries; `hyprctl reload` only where the brief allows it, always
  followed by `hyprctl configerrors`; open and close surfaces over `qs ipc`;
  screenshot with `grim` (take `WAYLAND_DISPLAY` from
  `systemctl --user show-environment`).
- May not: start, stop or restart the compositor or the session; run a nested
  Hyprland; `hyprctl dispatch`, `eval` or `keyword`; restart the `quickshell`
  service unless a startup-only setting needs it (then say so in the report);
  `sudo`, `nixos-rebuild`, `desk-sync reset`; git, except where the brief says
  so; start other agents; change the user's audio defaults, volumes or
  devices (use test streams with unique client names, put volumes back).
- After every save: `journalctl --user -u quickshell --since "-30s"
  --no-pager` must show `Configuration Loaded`, or fix the error it names at
  once. A save of a singleton file is sometimes missed after an editor
  replaces the file; `touch` it.

### Permissions and being blocked

- Agents run with a scoped allowlist plus `--add-dir` for exactly the
  directories they need; `/nix/store` is readable. Never bypass mode.
- Compound shell commands (pipes, `&&`, `$(…)`, loops, `xargs`) stop on a
  permission prompt. Use single simple commands and the Read/Grep/Glob tools.
- A blocked agent is a permission decision for the coordinator, who declines
  and steers, or fetches the data and leaves a copy in the shared scratch
  directory. Never approve a prompt on the user's behalf. To have a file
  placed outside your directories, ask: `hc send <coordinator> "need: …"`,
  and carry on with other work.
- Paths under `/sys/bus/…` and `/etc/…` are often symlinks out of the allowed
  directories; expect to ask for copies.
- Start agents in a folder Claude Code already trusts (the worktree): a new
  folder stops at a trust prompt and the agent never starts. Check a few
  seconds after launch that it did.
- Don't guess Quickshell or Hyprland APIs: read their source in the store.
  `nix eval --raw .#nixosConfigurations.BrightFalls.pkgs.quickshell.src.outPath`
  gives its path (the same for `hyprland`); store paths get collected, so
  `nix build` that attribute if the path is gone.

## Testing strategy

Five levels. Each proves something different; say which one a claim rests on.

| Level | What it proves | What it cannot |
|-------|----------------|----------------|
| Pure logic under node, and as flake checks | The decisions in the `.js` libraries, against invented fixtures | Anything QML draws, any device |
| Builds and config checks | The toplevel builds, generated files have the right content, `Hyprland --verify-config` accepts the Lua | That it works in the session |
| Injected data and preview modes, live | The panel's states and wording (a fake export, a fake sysfs tree, a data override, a no-focus preview) | That real hardware or a real service produces that data |
| Real hardware with the user | The real path end to end | Cases the hardware cannot produce on demand |
| After the deploy | That Nix put everything in place | |

**Report vocabulary.** Every claim in a report is one of: **proven on real
hardware** (and by whom: the agent's script, or the user at the keyboard),
**simulated** (injected or faked data), **expected** (read in the source,
not run), **not done**. Never blur them; the coordinator repeats them to the
user as written.

**Pure logic.** Decisions live in plain `.js` files that QML imports and node
runs (see conventions). Run them with
`nix shell nixpkgs#nodejs -c node <test.js> <library>`. Wired as flake checks
(`tests/default.nix`, `flake.nix`):

```bash
nix build .#checks.x86_64-linux.desk-sync        # tests/run.sh, temporary HOME
nix build .#checks.x86_64-linux.calendar-export  # fixtures through the export
nix build .#checks.x86_64-linux.calendar-panel   # calendar/queries.js under node
nix build .#checks.x86_64-linux.bluetooth-panel  # bluetooth/services.js, devices.js under node
nix build .#checks.x86_64-linux.tray-panel       # tray/menu.js under node
nix build .#checks.x86_64-linux.office-panel     # office/office.js under node
nix build .#checks.x86_64-linux.office-helper    # desk-mqtt against a loopback Mosquitto
nix build .#checks.x86_64-linux.system-panel     # system/decode.js under node
nix build .#checks.x86_64-linux.display-layout   # display-layout.sh against a fake hyprctl
nix build .#checks.x86_64-linux.hypr-config      # user/hypr through Hyprland --verify-config
nix build .#checks.x86_64-linux.desk-unlock      # desk-unlock.sh against fake hyprctl, systemctl, pkill
nix build .#checks.x86_64-linux.bluetooth-agent  # desk-bt-agent against private D-Bus daemons
nix build .#checks.x86_64-linux.audio-output-cycle# audio-output-cycle against fake PipeWire tools
```

The calendar-panel, bluetooth-panel, tray-panel, office-panel and system-panel checks read the
repository's `.js` files, so they fail until a live change to those files is pulled. All of them
run on every pull request in the `brightfalls-tests` job (`pr-build.yml`), a required check for
merging into `master`. For a new test, break the code once and watch it fail.

**Builds.** Before every push, on the merged branch, the coordinator runs:

```bash
nix build .#checks.x86_64-linux.desk-sync .#checks.x86_64-linux.calendar-export \
  .#checks.x86_64-linux.calendar-panel .#checks.x86_64-linux.bluetooth-panel \
  .#checks.x86_64-linux.tray-panel .#checks.x86_64-linux.office-panel \
  .#checks.x86_64-linux.office-helper .#checks.x86_64-linux.system-panel \
  .#checks.x86_64-linux.display-layout \
  .#checks.x86_64-linux.hypr-config \
  .#checks.x86_64-linux.desk-unlock \
  .#checks.x86_64-linux.bluetooth-agent \
  .#checks.x86_64-linux.audio-output-cycle \
  .#nixosConfigurations.BrightFalls.config.system.build.toplevel --no-link --print-out-paths
```

through `hc run --bg --no-notify --name <name> "…; echo EXIT=\$?"` and
`hc wait`. Nix does not compile QML: a green build says nothing about the
shell loading. For Lua, the `hypr-config` check runs `Hyprland --verify-config`
on the repository's files laid out like the install (`tests/hypr/run.sh`); a
live edit needs the same on a temporary copy (`config/hypr/*`,
`share/desk/hypr/*`, `XDG_CONFIG_HOME`/`XDG_DATA_HOME` pointed at it). Both
catch a misspelt key name in a bind (`Unknown key`), not a mouse button code
out of range.

**Injected data and previews.** Allowed during development: temporary IPC
targets, a property that points a loader at a fixture, a data override, a
no-focus preview mode on DP-2. Remove them before the report; anything kept
on purpose is named in it (the lock screen's `DESK_LOCK_PREVIEW=1` is kept,
and so is `audio/NoSignal.qml`'s `statusRoot`, pointed at a copy of the
`/proc/asound` tree to simulate a microphone that sends nothing).
`qs ipc show` at the end must list only the real targets.

**Real hardware.** Announced, in as few rounds as possible, with the user
doing anything that needs a password, a key or a device. Live tests use
unique names (`desk-probe-*` audio streams, `Test: …` events from a fixture)
and leave state as it was.

**Stand-ins before a deploy.** Things only Nix provides (a generated
`locked.json`, a helper on PATH, a PAM service, a WirePlumber drop-in) are
stood in for by hand so the live shell can be tested: a hand-made file at the
final path, an out-link, an existing equivalent. Every stand-in is listed in
the report and **removed before the next deploy**: Home Manager will not
replace a regular file with its link (it moves it aside as `.backup`).

**After a deploy**, the coordinator checks: the running generation equals the
built one; the generated files exist (`~/.local/share/desk/*/locked.json`,
`source.json`); new services ran (`systemctl --user status <unit>`);
`desk-sync status` is clean; `hyprctl configerrors` is empty; the shell's
log has no errors.

## Safety rules

Each was learned the hard way or is one mistake away.

- **Never run Hyprland nested in the live session.** Exiting the nested one
  took the user's session down. Use `Hyprland --verify-config`.
- **The lock screen can lock the user out.** Develop it in its preview
  (`DESK_LOCK_PREVIEW=1`, no session lock, no keyboard). A build that can
  engage a real lock carries a self-release during development (60 s and a
  key chord) until the user has unlocked with their password; never engage a
  real lock on your own; have the recovery written, handed over and tried
  before the user depends on it (README, "If the lock screen dies"). Don't
  restart anything while a lock test is on.
- **Passwords and pairing are the user's.** Agents never learn, ask for,
  type or store a password, and never accept a pairing or answer a service
  question. Before any wrong-password test, read the PAM stack for lockouts;
  at most two wrong attempts.
- **Reading can change things.** `spd5118` (memory module) `*_alarm` files
  clear when read; NVMe temperature reads are admin commands to the drive (read
  them every 10 s at most); LACT's socket has no per-request authorisation (a
  client that can read can also write) and its queries wake a suspended GPU.
  Sensor work reads sysfs and procfs directly, never LACT, never writes.
- **A logged-in text console bypasses any lock**: Hyprland switches VTs while
  locked. Log out of consoles after using them.
- **Overlay surfaces cost games.** Any surface on the Overlay layer of a
  monitor turns off direct scanout and tearing for a fullscreen game there
  while it exists, a fade-out included. Only critical notifications may do
  that, only while one is up, with no animation. The drop-down panels are
  Overlay with exclusive keyboard focus: not for use over a game.
- **Public repository.** No server addresses, user names, calendar names,
  event content, device names or addresses, phone models, anything personal:
  in files, commits, reports, `hc send` messages or web requests. Describe by
  kind. Screenshots with personal data stay in scratch. Secrets go through
  agenix: a new one is encrypted to the host's public key with plain `age`
  (value piped, never displayed, no sudo) and committed together with the
  code that declares it; any eval needs the `.age` file in git.
- **Notification bodies** without line breaks show two lines. Break lines
  yourself, or say it in chat.

## Engineering conventions

- **Logic in pure `.js`, effects in QML.** Decisions go in plain-script
  libraries that QML imports and node runs (`calendar/queries.js`,
  `system/decode.js`, `bluetooth/services.js`, `bluetooth/devices.js`;
  export with `if (typeof module !== "undefined") module.exports = …`).
  Processes, files, D-Bus and drawing stay in small QML components.
- **Cheapest honest source, nothing while hidden.** Quickshell modules where
  they have the data (Networking, Pipewire, Bluetooth, Hyprland); `FileView`
  for sysfs and procfs; one `Process` run on open or on change; a
  session-long helper only where a D-Bus object must be exported (the
  Bluetooth agent: QML cannot export one) or a connection must be held and
  its loss reported (`desk-mqtt`, the MQTT client). Read when shown, never poll while
  hidden; measure the cost (`/proc/<pid>/stat` of the shell over 60 s), don't
  assume it.
- **Say only what is true.** No figure without a source (no link
  saturation, no CPU-only power); no state claimed that is not observed
  ("playing here" only while a node is linked); a line for what is
  deliberately not shown and why. If the hardware cannot tell, the panel
  doesn't pretend.
- **Values fixed by Nix** are shown greyed with a `nix` tag and the file
  that sets them, from `~/.local/share/desk/<area>/locked.json` generated in
  `desktop-hyprland.nix` (a row exists only while its setting has the value
  it states; `file` from the option's definitions). Never hard-code them in
  QML.
- **No truncation of information.** Only a name may elide; everything else
  wraps.
- **Anatomy of a drop-down panel** (network, audio, calendar, system,
  Bluetooth, office): a root component, one line in `shell.qml`; a small singleton
  shared with the bar for placement and open state; an IPC target with
  `toggle`; a bind through `bind()`; footer key hints; Overlay layer,
  exclusive keyboard, namespace `desk-<name>`, card under its bar item
  clamped 6 px from the screen edges; a click outside closes it; opening one
  closes the others. To add one, copy that anatomy from an existing panel
  (the code map below says where each shared piece lives).
- **Binds** go through `bind(group, keys, description, dispatcher, opts)` in
  `user/hypr/bindings.lua`, so they appear on the cheat sheet. Check the key
  is free in `hyprctl binds` first.
- **Surfaces** share one look: `Theme.background` at 0.96 alpha, a 1 px
  `Theme.purple` border, 10 px corners; colours and fonts only from
  `Theme.qml`, shared measures and derived colours (`surface`, `soft`,
  `panelTop`) from `common/Style.qml`.
- **Temporary hooks** are fine while developing and gone before the report.
- **Comments** follow the root rules: true, only what the code cannot say,
  never about the task or the history.

## Code map

Paths are relative to this directory. Line counts change; the shape should
not.

**Nix and helpers**

| Path | What |
|------|------|
| `../../../desktop-hyprland.nix` | System side: Hyprland with UWSM and the hidden plain entry, udev GPU links, logind keys, `desk-lock` PAM service, Fira Sans, and every generated `locked.json` |
| `default.nix` | User side: the two layers, `desk-sync` and `desk-unlock` packages, the commands binds and panels run, the `quickshell` user service, imports `calendar.nix` |
| `calendar.nix` | `pimsync.conf`, `source.json`, `calendar-sync.service` and `.timer` |
| `calendar-export.nix`, `calendar-export.py` | The export step (khal, time-zone fix, alarms) and its khal config; shared with the check |
| `bt-agent.nix`, `bt-agent.py` | `desk-bt-agent`, the BlueZ pairing agent the shell runs (JSON lines on stdin/stdout); also reports each device's links, calls from PipeWire's telephony service on the session bus |
| `desk-mqtt.nix`, `desk-mqtt.py` | `desk-mqtt`, the office panel's MQTT client (JSON lines on stdin/stdout): watches the light, blind and sockets on Zigbee2MQTT, publishes only the light's and blind's `/set`; the device ids and labels are in the `.nix`, the broker and names in the `office-mqtt` agenix secret (README, "Office: desk-mqtt") |
| `desk-sync.sh` | `desk-sync activate|status|reset|pull` |
| `desk-unlock.sh` | Recovery from a text console when the lock screen dies |
| `gen-emoji.py` | Generates `user/quickshell/launcher/emoji.txt` (not installed) |
| `tests/` | Flake checks: `run.sh` (desk-sync), `calendar/fixtures` + `expected.jsonl` (export), `calendar/panel/` (queries.js under node), `bluetooth/` (services.js and devices.js under node), `tray/` (menu.js under node), `office-panel/` (office.js under node, recorded helper lines in `fixtures/`), `office/` (desk-mqtt against a loopback Mosquitto), `system/` (decode.js under node), `display-layout/` (display-layout.sh against a fake hyprctl) |
| `defaults/hypr/` | Read-only layer: `rescue.lua` (terminal, reload, exit, restore-monitors binds), `theme.lua` |
| `../../../display-layout.sh` | `display-layout single` and `restore`, behind `single-monitor` and Super+Shift+D (built in `gaming.nix`) |
| `user/desk/theme.json` | The palette |
| `../../../audio/` | PipeWire and WirePlumber settings the audio panel reports, Bluetooth codecs |

**Hyprland** (`user/hypr/`): `hyprland.lua` (entry, requires the rest, then
`rescue.lua`), `monitors.lua` (outputs, workspace rules), `input.lua`,
`looknfeel.lua` (gaps, animations, tearing, scanout, `disable_autoreload`),
`rules.lua` (game rule, critical-notification layer rule), `bindings.lua`
(every bind, through `bind()`), `autostart.lua`.

**Quickshell** (`user/quickshell/`). `shell.qml` loads one line per
component. Root components, one per file:

| File | What |
|------|------|
| `Theme.qml` | Palette and fonts from `theme.json` (singleton) |
| `Bar.qml` | The bar on every monitor; anchors each drop-down's bar item with `Dropdowns.anchor()` |
| `Launcher.qml`, `Apps.qml` | Launcher and its app list and ranking (`Apps.rank`, also used for emoji) |
| `Notifications.qml` | Notification server, the cards' windows (normal and critical), DND, IPC |
| `Osd.qml` | The pill |
| `Cheatsheet.qml` | Keybinding sheet from `hyprctl -j binds` |
| `SessionMenu.qml`, `Polkit.qml` | Centred modals |
| `Network.qml`, `Audio.qml`, `Calendar.qml`, `System.qml`, `BluetoothPanel.qml`, `Office.qml` | The six drop-down panels (each the biggest file of its feature) |
| `Lockscreen.qml`, `LockState.qml` | The shell's side of the lock: IPC `lockscreen`, hold, sleep inhibitor; the launch command and `held` state |
| `lock.qml` | The lock process itself (a separate Quickshell config) |

Directories (`import qs.<dir>`):

| Directory | What |
|-----------|------|
| `common/` | Shared by panels: `Style.qml` (singleton: bar metrics, `panelTop`, edge, radius, the cards' `growDuration`, surface, soft, track, scrim colours), `Dropdowns.qml` (singleton registry: `add()` a panel, `closeOthers()`, `anchor()`/`centre()` for placement), `DropCard.qml` (the card, shadow, placement and eased height), `KeyHints.qml` (the drop-downs' footer: hints that wrap, or a wrapped `message` in their place), `LockedList.qml` (loads `locked.json` for an area), `NixTag.qml`, `SectionHeader.qml` |
| `launcher/` | `Calc.qml` (parser, evaluator), `Emoji.qml` (lazy list, search), `emoji.txt` (generated) |
| `notifications/` | `Card.qml` (one card), `Entry.qml` (timeout, replacement, leave animation) |
| `network/` | `NetworkPanel.qml` (singleton shared with the bar: `screen`, `toggleRequested`), `SpeedTest.qml` (providers, process, parsing), `Gauge.qml` |
| `audio/` | `AudioPanel.qml` (shared singleton), `Stack.qml` (the DAC drawing), `Modi.qml` (`/proc/asound` reads), `Graph.qml` (`pw-dump`), `Level.qml` (level bar), `NoSignal.qml` (singleton, runs always) |
| `calendar/` | `CalendarPanel.qml` (shared singleton, also the export loader, minute clock and bar hint), `Reminders.qml` (reminders, digest, held items), `queries.js` (all calendar decisions; node-tested) |
| `system/` | `SystemPanel.qml` (shared singleton), `Sensors.qml` (singleton, every read, at three levels), `decode.js` (gpu_metrics and /proc parsing, throttle decode; node-tested), `Machine.qml` (drawing), `Ring.qml`, `Temperatures.qml` (bar hover list) |
| `bluetooth/` | `BluetoothShared.qml` (shared singleton: adapter, devices, RSSI, links, answers, low battery), `Agent.qml` (runs `desk-bt-agent`, open requests), `PairModal.qml`, `services.js`, `devices.js` (node-testable) |
| `office/` | `OfficeShared.qml` (shared singleton: `screen`, `toggleRequested`, `readOnly`, runs `desk-mqtt` and restarts it, `office` state, `send()`, `failed`), `office.js` (all office decisions: applying helper events, ages, percent ↔ raw, locks, row texts, banners, bar view; node-tested) |
| `tray/` | `TrayMenu.qml` (root component: a tray icon's right-click menu over DBusMenu with `QsMenuOpener`, `tray` in `Dropdowns`; no IPC, no bind, no footer), `TrayShared.qml` (shared singleton: `screen`, `openRequested(item, screen)`), `menu.js` (header name, entry marks; node-tested) |
| `lock/` | `LockFace.qml`, one monitor's lock face; used only by `lock.qml` |

Imports: each panel imports its own directory and `qs.common`; `Bar.qml`
imports every feature directory; `Osd.qml` imports `qs.bluetooth` (it shows
`BluetoothShared.announce`); `Notifications.qml` and `calendar/Reminders.qml` read the
root `LockState`. No cycles: keep it that way, and don't make one panel
import another to talk to it (use `Dropdowns`, or D-Bus as Reminders does).
The lock (`lock.qml`, `lock/`) imports only `Theme.qml`, so a change to
`Theme.qml` can break the next lock: test it in the lock preview.

Names to know: the singleton each panel shares with the bar is
`network/NetworkPanel.qml`, `audio/AudioPanel.qml`,
`calendar/CalendarPanel.qml`, `system/SystemPanel.qml`,
`bluetooth/BluetoothShared.qml` and `office/OfficeShared.qml` (which also
runs the helper, so the bar has the light and the watts while the panel is
closed). "Panel" does not mean placement only:
`CalendarPanel` holds the export and the minute clock, and
`BluetoothShared` the adapter, batteries and remembered answers, because the
bar, the OSD and the reminders need them while the panel is closed.
`BluetoothShared` is not named `BluetoothPanel`, which is the root
component, nor `Bluetooth`, which is Quickshell's own singleton.

To add a drop-down panel: a root file and its line in `shell.qml`; a
singleton in its directory with `screen` and `toggleRequested(screen)`;
`Dropdowns.add(name, singleton)` on completion and
`Dropdowns.closeOthers(name)` when opening; a `DropCard` whose `centre` is
`Dropdowns.centre(name, screen)`; in `Bar.qml`, the item with
`Dropdowns.anchor(name, …)` and a click that emits `toggleRequested`; an
`IpcHandler` with `toggle`; a bind in `bindings.lua`; `KeyHints` at the
bottom; `LockedList` plus a generator in `desktop-hyprland.nix` if Nix fixes
anything it shows. The calendar or network panel is the shortest model.

## State and open work (2026-11-15)

**Built and in the branch:** the session under UWSM, the config machinery and
`desk-sync`, the palette, launcher (apps, calculator, emoji), bar,
notifications (critical ones above fullscreen), OSD, cheat sheet, session
menu, polkit dialog, network panel with speed test (two providers), audio
panel (the DAC stack, per-program rows and levels, inputs, no-signal flag),
clock and calendar (sync, export, reminders, digest), system panel,
Bluetooth panel with pairing agent, lock screen with a recovery command,
tray right-click menus drawn by the shell (`tray/`), office panel (light,
blind, sockets' power through `desk-mqtt`; live, not read-only).

**To do at the next deploy:**
- `~/.config/mako/` is left over from before the shell was the notification
  daemon (`desk-sync` leaves dropped files alone); delete it.
- `systemctl --user restart quickshell`: `shell.qml` no longer has
  `//@ pragma UseQApplication` (it was there only for the Qt platform menus
  the tray used before `tray/`), and pragmas are read at startup only. Then
  check the shell's log is clean; nothing else is known to need a
  QApplication, but this is the first start without one.

The earlier stand-ins (hand-made `locked.json` files, speed-test tools on a
profile link, the Bluetooth agent's temporary command) were gone when this
was written; check the reports of any newer work for its own.

**Never tested:**
- The final lock build (self-release removed) locked for real; the lock
  before sleep; `desk-unlock`'s fallback for a hung lock process.
- A game under Hyprland (Proton fullscreen on the RX 6800 XT with two
  monitors has open upstream freeze reports); locking over a game;
  critical notifications over a real fullscreen window.
- Suspend: the eGPU does not come back from it.
- Bluetooth keyboards (type-a-code pairing), LE devices, a real low-battery
  device.
- A real microphone hang with the no-signal flag (simulated only).
- Tray menus: running a real entry, real pointer hover, a real application's
  submenu, check or radio entries (none of the tray apps here has them; a
  fixture showed them), and a menu changing while open.
- Office panel: the user verified, with the real light and blind, the light
  on and off, brightness by keys and by mouse, the blind up, stop, down and
  to a position, and that the sockets are not clickable. Never seen for real
  (simulated with recorded helper lines, and node-tested): the broker lost,
  Zigbee2MQTT offline, a device offline, a command not confirmed.
- Most pointer and key input was driven by the user, not by agents; whatever
  a report lists as expected still is.

**Not built:**
- Wi-Fi in the network panel. Decided design: off at boot; scan, join,
  forget; the password in the centred modal; the Wi-Fi boot specialisation
  removed.
- Friendly launcher category names, scrolling for panels taller than the screen (the audio panel runs
  off the bottom with many programs).

**Code follow-ups** from the modularity review (estimates for one agent
working live; the ones that change what the user sees need the user's
look first). Its footer, height animation, naming, leftover and colour items
are done; what is left:
1. **Pure logic out of QML into node-tested `.js`** (2 to 3 h a panel):
   Network (nmcli/route/duplex parsing, the `speedtests.jsonl` reduction,
   done twice, `age()`), Audio (`facts()`, `details()`, path text),
   Cheatsheet (grouping and column balancing), Bluetooth (`rowSub()`,
   `details()`, codec names), `SpeedTest.qml`'s parsers.
2. **Shared drop-down window, row selection, bar open mark** (about 2 h):
   the `PanelWindow` shell (layer, focus, click-off, key forwarding) is
   copied in six panels; Audio and Bluetooth have identical selection code;
   `Bar.qml` draws the 14×2 open mark six times. The "pick the screen by
   name" line is repeated in 11 places.
3. **One notification sender** (about 30 min plus a device test): `gdbus …
   Notify` argument lists are built by hand in
   `bluetooth/BluetoothShared.qml`, `audio/NoSignal.qml` and
   `calendar/Reminders.qml`. The first two pass unquoted strings, so a
   device name that parses as GVariant text would be altered; Reminders
   quotes them (`gv()`).
4. **Small ones** (minutes each): the flash timer (`say()` and a `Timer`,
   2.5 s, Calendar 3.5 s, Office 5 s) is still copied in Network, Audio,
   Calendar, Bluetooth and Office; `Osd.qml` picks its glyph by matching the literal text
   `"Bluetooth on"` from `BluetoothPanel.qml`; the root `BluetoothPanel.qml`
   is named unlike `Network.qml`, `Audio.qml` and the rest; `#191a21` (text
   on purple) is hard-coded in `Polkit.qml` and `BluetoothPanel.qml`;
   `lock/LockFace.qml` copies the "soft" formula (leave it until the lock
   can be re-tested). Live only, not in the repository:
   `~/.config/hypr/dms/`, unused DankMaterialShell output (the user's call).

Also noted, no action planned: the centred modals (Launcher, Cheatsheet,
SessionMenu, Polkit, the pairing modal) keep their own footers rather than
`KeyHints` (the pairing modal's is a hand-built copy of the drop-down look); rings and level bars are separate drawings
per panel (they differ in size and behaviour); Polkit and the pairing modal
are hand-built modals sharing a look by copy; `system/Sensors.qml` reads
`system/locked.json` through its own batched reads rather than
`LockedList`; Notifications and the OSD sit at 44 px from the top, the
drop-downs at `Style.panelTop` (48).

**GNOME removed** (2026-11-15). GDM became greetd, and what GNOME's module
enabled implicitly is either declared (`desktop.nix`, `users/matteo/desktop.nix`,
`printer.nix`) or gone: GNOME Shell and Settings, ibus, power-profiles-daemon,
accounts-daemon, colord, EDS and Online Accounts, geoclue, at-spi. Proven
only by build and eval until the first boot without GNOME, which has to show:
the automatic login and tuigreet after a logout; the keyring locked after
the automatic login and unlocked by the first lock-screen unlock; the SSH
agent; file dialogs, screen sharing and dark GTK apps through the portals;
the default apps; printing; the CPU's energy preference without
power-profiles-daemon (it was `balance_performance`); no failed units.

**Known quirks:**
- The Blue microphone (`046d:0ab7`) can stop delivering samples until its
  power is cut (replug); no host-side fix exists upstream. The audio panel
  flags it.
- With LDAC, phone audio over A2DP never settled against BlueZ 5.87, so
  WirePlumber offers only SBC, SBC XQ and AAC, for every device
  (`hosts/BrightFalls/audio/default.nix`).
- `resample.quality` in the PipeWire daemon config does not reach client
  streams, which resample in the client (quality 4).
- Notification bodies without line breaks show two lines.
- Quickshell 0.3.2 cannot meter a mono stream into a stereo sink (it logs an
  error per cycle), so such rows get no level bar.
