# Agent instructions: the BrightFalls Hyprland session and its Quickshell shell

Read this before any work on the Hyprland session on BrightFalls or on its
desktop shell (Quickshell), including work that starts in the live
`~/.config/quickshell` or `~/.config/hypr` and never touches this directory.
What each piece is and how it works is in [README.md](README.md); this file
is how to work on it. Repo-wide rules are in the root `AGENTS.md`.

State as of 2026-11-15 (end of the build, PR #479). "State and open work" at
the bottom says what is unproven; check it before relying on anything.

## What this is

A Hyprland 0.57 session under UWSM, offered by GDM beside GNOME (GNOME is
still the default and the autologin session), with a desktop shell written in
QML for Quickshell 0.3.2: bar, launcher, notifications, OSD, cheat sheet,
session menu, polkit dialog, network, audio, calendar, system and Bluetooth
panels, and a lock screen.

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
```

The calendar-panel check reads the repository's `queries.js`, so it fails
until a live change to that file is pulled. Only `desk-sync` runs in PR CI
(`pr-build.yml`). For a new test, break the code once and watch it fail.

**Builds.** Before every push, on the merged branch, the coordinator runs:

```bash
nix build .#checks.x86_64-linux.desk-sync .#checks.x86_64-linux.calendar-export \
  .#checks.x86_64-linux.calendar-panel \
  .#nixosConfigurations.BrightFalls.config.system.build.toplevel --no-link --print-out-paths
```

through `hc run --bg --no-notify --name <name> "…; echo EXIT=\$?"` and
`hc wait`. Nix does not compile QML: a green build says nothing about the
shell loading. For Lua, `Hyprland --verify-config -c <copy>/hyprland.lua` on a
temporary copy laid out like the install (`config/hypr/*`,
`share/desk/hypr/*`, `XDG_CONFIG_HOME`/`XDG_DATA_HOME` pointed at it); an
unknown key name in a bind is ignored silently, so it cannot catch that.

**Injected data and previews.** Allowed during development: temporary IPC
targets, a property that points a loader at a fixture, a data override, a
no-focus preview mode on DP-2. Remove them before the report; anything kept
on purpose is named in it (the lock screen's `DESK_LOCK_PREVIEW=1` is kept).
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
  Bluetooth agent: QML cannot export one). Read when shown, never poll while
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
  Bluetooth): a root component, one line in `shell.qml`; a small singleton
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
| `../../../desktop-hyprland.nix` | System side: Hyprland with UWSM and the hidden plain entry, GDM default session, udev GPU links, logind keys, `desk-lock` PAM service, Fira Sans, and every generated `locked.json` |
| `default.nix` | User side: the two layers, `desk-sync` and `desk-unlock` packages, the commands binds and panels run, the `quickshell` user service, imports `calendar.nix` |
| `calendar.nix` | `pimsync.conf`, `source.json`, `calendar-sync.service` and `.timer` |
| `calendar-export.nix`, `calendar-export.py` | The export step (khal, time-zone fix, alarms) and its khal config; shared with the check |
| `bt-agent.nix`, `bt-agent.py` | `desk-bt-agent`, the BlueZ pairing agent the shell runs (JSON lines on stdin/stdout) |
| `desk-sync.sh` | `desk-sync activate|status|reset|pull` |
| `desk-unlock.sh` | Recovery from a text console when the lock screen dies |
| `gen-emoji.py` | Generates `user/quickshell/launcher/emoji.txt` (not installed) |
| `tests/` | Flake checks: `run.sh` (desk-sync), `calendar/fixtures` + `expected.jsonl` (export), `calendar/panel/` (queries.js under node) |
| `defaults/hypr/` | Read-only layer: `rescue.lua`, `theme.lua` |
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
| `Network.qml`, `Audio.qml`, `Calendar.qml`, `System.qml`, `BluetoothPanel.qml` | The five drop-down panels (each the biggest file of its feature) |
| `Lockscreen.qml`, `LockState.qml` | The shell's side of the lock: IPC `lockscreen`, hold, sleep inhibitor; the launch command and `held` state |
| `lock.qml` | The lock process itself (a separate Quickshell config) |

Directories (`import qs.<dir>`):

| Directory | What |
|-----------|------|
| `common/` | Shared by panels: `Style.qml` (singleton: bar metrics, `panelTop`, edge, radius, surface, soft, track, scrim colours), `Dropdowns.qml` (singleton registry: `add()` a panel, `closeOthers()`, `anchor()`/`centre()` for placement), `DropCard.qml` (the card, shadow, placement and eased height), `KeyHints.qml` (footer hints), `LockedList.qml` (loads `locked.json` for an area), `NixTag.qml`, `SectionHeader.qml` |
| `launcher/` | `Calc.qml` (parser, evaluator), `Emoji.qml` (lazy list, search), `emoji.txt` (generated) |
| `notifications/` | `Card.qml` (one card), `Entry.qml` (timeout, replacement, leave animation) |
| `network/` | `Panel.qml` (singleton shared with the bar: `screen`, `toggleRequested`), `SpeedTest.qml` (providers, process, parsing), `Gauge.qml` |
| `audio/` | `AudioPanel.qml` (shared singleton), `Stack.qml` (the DAC drawing), `Modi.qml` (`/proc/asound` reads), `Graph.qml` (`pw-dump`), `Level.qml` (level bar), `NoSignal.qml` (singleton, runs always) |
| `calendar/` | `CalendarPanel.qml` (shared singleton, also the export loader, minute clock and bar hint), `Reminders.qml` (reminders, digest, held items), `queries.js` (all calendar decisions; node-tested) |
| `system/` | `SystemPanel.qml` (shared singleton), `Sensors.qml` (singleton, every read, at three levels), `decode.js` (gpu_metrics and /proc parsing, throttle decode; node-run), `Machine.qml` (drawing), `Ring.qml`, `Temperatures.qml` (bar hover list) |
| `bluetooth/` | `Bt.qml` (shared singleton: adapter, devices, RSSI, links, answers, low battery), `Agent.qml` (runs `desk-bt-agent`, open requests), `PairModal.qml`, `services.js`, `devices.js` (node-testable) |
| `lock/` | `LockFace.qml`, one monitor's lock face; used only by `lock.qml` |

Imports: each panel imports its own directory and `qs.common`; `Bar.qml`
imports every feature directory; `Osd.qml` imports `qs.bluetooth` (it shows
`Bt.announce`); `Notifications.qml` and `calendar/Reminders.qml` read the
root `LockState`. No cycles: keep it that way, and don't make one panel
import another to talk to it (use `Dropdowns`, or D-Bus as Reminders does).
The lock (`lock.qml`, `lock/`) imports only `Theme.qml`, so a change to
`Theme.qml` can break the next lock: test it in the lock preview.

Names to know: the singleton each panel shares with the bar is
`network/Panel.qml`, `audio/AudioPanel.qml`, `calendar/CalendarPanel.qml`,
`system/SystemPanel.qml` and `bluetooth/Bt.qml`. "Panel" does not mean
placement only: `CalendarPanel` holds the export and the minute clock, `Bt`
the adapter, batteries and remembered answers, because the bar and the
reminders need them while the panel is closed.

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
Bluetooth panel with pairing agent, lock screen with a recovery command.

**To do at the next deploy:**
- Switch `lock.qml`'s `pamService` from `swaylock` to `desk-lock` once the
  deploy declaring `desk-lock` is live, not before (a missing PAM service
  means no password can unlock). Remove the old `~/desk-unlock` from the
  home directory; the `desk-unlock` command replaces it.
- `~/.config/mako/` is left over from before the shell was the notification
  daemon (`desk-sync` leaves dropped files alone); delete it.
- `systemctl --user restart quickshell` if `shell.qml`'s pragmas changed.

The earlier stand-ins (hand-made `locked.json` files, speed-test tools on a
profile link, the Bluetooth agent's temporary command) were gone when this
was written; check the reports of any newer work for its own.

**Never tested:**
- The final lock build (self-release removed) locked for real; the lock
  before sleep; `desk-unlock`'s fallback for a hung lock process.
- A game under Hyprland (Proton fullscreen on the RX 6800 XT with two
  monitors has open upstream freeze reports); locking over a game or a
  Sunshine stream; critical notifications over a real fullscreen window.
- Suspend: the eGPU does not come back from it.
- Bluetooth keyboards (type-a-code pairing), LE devices, a real low-battery
  device.
- A real microphone hang with the no-signal flag (simulated only).
- Most pointer and key input was driven by the user, not by agents; whatever
  a report lists as expected still is.

**Not built:**
- Wi-Fi in the network panel. Decided design: off at boot; scan, join,
  forget; the password in the centred modal; the Wi-Fi boot specialisation
  removed.
- `single-monitor` and the Sunshine prepare command on `hyprctl` instead of
  mutter's `gdctl`.
- Tray menu styling (they are Qt platform menus), friendly launcher category
  names, scrolling for panels taller than the screen (the audio panel runs
  off the bottom with many programs).
- The Bluetooth and system node tests live only in the build's scratch
  directory; they belong under `tests/` as flake checks.

**Code follow-ups** from the modularity review (estimates for one agent
working live; the ones that change what the user sees need the user's
look first):
1. **Footers and flash messages** (about 1 h). Two footer styles exist:
   drop-downs (cyan key, `common/KeyHints.qml`, plus hand-built copies in
   Network's list footer, Calendar, Bluetooth and `PairModal.qml`) and modals
   (Launcher, Cheatsheet, SessionMenu); one or two is the user's call. The
   flash message is handled four ways, with a `say()` timer copied in four
   panels (2.5 s, Calendar 3.5 s). **Bug:** Audio overlays its flash on the
   hints without growing the footer, so a flash longer than one line (the
   no-signal explanation) is cut off by the card's clip.
2. **Pure logic out of QML into node-tested `.js`** (2 to 3 h a panel):
   Network (nmcli/route/duplex parsing, the `speedtests.jsonl` reduction,
   done twice, `age()`), Audio (`facts()`, `details()`, path text),
   Cheatsheet (grouping and column balancing), Bluetooth (`rowSub()`,
   `details()`, codec names), `SpeedTest.qml`'s parsers.
3. **One height animation** (minutes, plus the user's pick): 260 ms in
   Network and Calendar, 200 ms elsewhere (`DropCard.growDuration`). Then
   move it to `Style`.
4. **Shared drop-down window, row selection, bar open mark** (about 2 h):
   the `PanelWindow` shell (layer, focus, click-off, key forwarding) is
   copied in five panels; Audio and Bluetooth have identical selection code;
   `Bar.qml` draws the 14×2 open mark five times. The "pick the screen by
   name" line is repeated in 11 places.
5. **One notification sender** (about 30 min plus a device test): `gdbus …
   Notify` argument lists are built by hand in `bluetooth/Bt.qml`,
   `audio/NoSignal.qml` and `calendar/Reminders.qml`. The first two pass
   unquoted strings, so a device name that parses as GVariant text would be
   altered; Reminders quotes them (`gv()`).
6. **Naming** (about 30 min, update this file with it): `Panel` and `Bt`
   against `AudioPanel`, `CalendarPanel`, `SystemPanel`; the root
   `BluetoothPanel.qml` against `Network.qml`, `Audio.qml` and the rest.
   `Osd.qml` picks its glyph by matching the literal text `"Bluetooth on"`
   from `BluetoothPanel.qml`.
7. **Leftovers** (15 min): `bluetooth/Agent.qml`'s unused `answered` signal
   and `command` property and a stale comment about IPC;
   `CalendarPanel.exportPath` (a fixture override nothing sets);
   `Reminders.fullscreenOverride` (a test input); `NoSignal.statusRoot`
   (kept as the way to simulate a hang: decide); a brace slip in
   `BluetoothPanel.qml`'s power toggle. Live only, not in the repository:
   `~/.config/hypr/dms/`, unused DankMaterialShell output (the user's call).
8. **Remaining colour copies** (15 min): the "soft" and "track" formulas in
   `notifications/Card.qml`, `audio/Stack.qml`, `audio/Level.qml`,
   `system/Machine.qml`, `system/Ring.qml` and `Osd.qml` could use `Style`;
   `#191a21` (text on purple) is hard-coded in `Polkit.qml` and
   `BluetoothPanel.qml`. Leave `lock/LockFace.qml` until the lock can be
   re-tested.

Also noted, no action planned: rings and level bars are separate drawings
per panel (they differ in size and behaviour); Polkit and the pairing modal
are hand-built modals sharing a look by copy; `system/Sensors.qml` reads
`system/locked.json` through its own batched reads rather than
`LockedList`; Notifications and the OSD sit at 44 px from the top, the
drop-downs at `Style.panelTop` (48).

**Removing GNOME.** Blockers: the login manager (GDM), an explicit keyring
and SSH agent, the `gdctl` users above, the game test. Then audit every
service GNOME's module enables implicitly (upower, power-profiles-daemon,
udisks2, accounts-daemon, colord, gvfs, dconf, portals), GTK look settings,
ibus. Order: make Hyprland the default session with GNOME still installed,
live with it, audit, replace GDM, remove GNOME.

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
