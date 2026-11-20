# Agent instructions: the BrightFalls Hyprland session and its Quickshell shell

Read this before any work on the Hyprland session on BrightFalls or on its
desktop shell (Quickshell), including work that starts in the live
`~/.config/quickshell` or `~/.config/hypr` and never touches this directory.
What each piece is and how it works is in [README.md](README.md); this file
is how to work on it. Repo-wide rules are in the root `AGENTS.md`.

State as of 2026-11-17. "State and open work" at the bottom says what is
unproven; check it before relying on anything.

## What this is

A Hyprland 0.57 session under UWSM, the only desktop on the machine, started
by greetd (automatic login once per boot, tuigreet after a logout), with a
desktop shell written in
QML for Quickshell 0.3.2: bar, launcher, notifications, OSD, cheat sheet,
session menu, polkit dialog, network, audio, calendar, system, Bluetooth,
office, fleet, Tailscale and token panels, tray menus, and a lock screen.

- **Nix** (`hosts/BrightFalls/desktop-hyprland.nix` for the system,
  `default.nix` here for the user) pins the packages, declares services,
  secrets, PAM, and generates read-only data the shell shows. The
  wallpapers (`assets/wallpapers/` at the repo root) are Nix-only too: never edited live.
- **The config files** are ordinary writable files under `~/.config`, copied
  from `user/` here at activation and hot-reloaded. They are developed live
  and brought back to this directory with `desk-sync pull`. README:
  "Two layers", "Activation", "desk-sync", "Editing live".

Code is written and checked in the repository first, where the lint and
node checks run without reloading the user's shell, and put live in a
separate step ("Practices", "Live work"). Some changes need
both halves at once (a panel plus the Nix file that feeds it). Decide which
half a change belongs to before starting.

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
  `desk-sync pull <worktree>` for files already in the manifest (it refuses
  a file with a newer copy waiting in `incoming/`, or with an added line
  that looks like a secret: README, "desk-sync"), a hand copy
  into `user/…` for files created live, then `diff -rq` of the live tree
  against `user/` must be silent, then a grep for leftovers (test IPC
  targets, overrides, temporary paths) before the commit.
- **Deploys are the user's.** Commit when asked; give the switch command for
  the worktree they deploy from, never "pull" (the commits are already
  there). Wait for them to say it is deployed before checking it live.

### The Shell Atlas

One published page draws every surface of the shell in every state its
source can reach, and its design system: the BrightFalls Shell Atlas,
<https://claude.ai/artifact/6MqpiuaSGvJztQaM7GCKpa> (private to the owner;
read it with the Artifact tool). It opens with the design system (palette,
derived colours, type scale, measures, shared components, layers, motion),
then has one section per surface, and ends with a source map: every `.qml`
and `.js` file and the sections that cite it.

- **Read it before designing.** A new panel or state starts from the
  Atlas's design system and the nearest existing surface, not from memory.
- **It is drawn from source, not screenshots.** Each state cites the file
  and line that produces it, and each section's "Not drawn" paragraph says
  what the source does not settle. Its header names the commit it was drawn
  from: a state added or changed since is not in it. The source wins.
- **Keep it current.** A change to what a surface draws (a state, a string,
  a colour, a key) updates that surface's section in the same piece of
  work, and the design system section when a shared value changes. Read the
  artifact, change the section, publish to the same URL.
- **All names and figures in it are invented**, by the public-repository
  rule below. Keep it that way.

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
- **No notification, no focus.** Check the notification call's exit status
  and read back the `uint32` id it returns before the 10 s wait starts. If
  either fails, abort the batch and take no focus. Arm any timer that takes
  focus only after that check. (A focus batch once armed its timer before a
  failed notification call, and a password modal over test data held the
  keyboard unannounced.)
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
  once. No such line means no reload: only a changed `.qml` gives one, not a
  `touch`, nor a `.js` changed alone (see "Practices", "Live work").

### Permissions and being blocked

- Agents run with a scoped allowlist plus `--add-dir` for exactly the
  directories they need; `/nix/store` is readable. Never bypass mode.
- The repository tracks `.claude/settings.local.json`, which allows every
  Bash command, web fetch and web search, so every checkout and worktree
  carries it, and an agent started in one inherits it whatever
  `--allowedTools` says (two audit agents ran a network tool on no list this
  way). An agent that must stay inside its allowlist is started with
  `--setting-sources user`, its `--allowedTools`, and an explicit
  `--disallowedTools` list for the network tools. Allow rules match by
  prefix: a command must start with the allowed words (no `git -C`, no
  variables, no chains).
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
| Builds and config checks | The toplevel builds, generated files have the right content, `Hyprland --verify-config` accepts the Lua, `qmllint` accepts the QML (syntax, imports, ids, properties, singleton members) and every `qs ipc call` names a real target and function | That it works in the session: nothing at run time (binding loops, JS errors, layout), nor members read through an outer id inside a delegate |
| Injected data and preview modes, live | The panel's states and wording (a fake export, a fake sysfs tree, a data override, a no-focus preview) | That real hardware or a real service produces that data |
| Real hardware with the user | The real path end to end | Cases the hardware cannot produce on demand |
| After the deploy | That Nix put everything in place | |

**Report vocabulary.** Every claim in a report is one of: **proven on real
hardware** (and by whom: the agent's script, or the user at the keyboard),
**simulated** (injected or faked data), **expected** (read in the source,
not run), **not done**. Never blur them; the coordinator repeats them to the
user as written.

**Pure logic.** Decisions live in plain `.js` files that QML imports and node
runs (see "Practices"). Run them with
`nix shell nixpkgs#nodejs -c node <test.js> <library>`. Every check, what it
covers and which run in CI: README, "Tests" (the 22 checks defined in
`tests/default.nix`).
One check: `nix build .#checks.x86_64-linux.<name>`; all but `hypr-config`:
`nix build -L .#checks.x86_64-linux.brightfalls-tests`, which is what CI
builds and which takes a new check in `tests/default.nix` with no other
edit. The node checks and `quickshell-lint` read the repository's files, so
they fail until a live change to those files is pulled. For a new test,
break the code once and watch it fail.

**Builds.** Before every push, on the merged branch, the coordinator runs:

```bash
nix build -L .#checks.x86_64-linux.brightfalls-tests .#checks.x86_64-linux.hypr-config \
  .#nixosConfigurations.BrightFalls.config.system.build.toplevel --no-link --print-out-paths
```

through `hc run --bg --no-notify --name <name> "…; echo EXIT=\$?"` and
`hc wait`. Nix does not compile QML, so the toplevel says nothing about the
shell loading; `quickshell-lint` runs `qmllint` over it as Quickshell lays it
out, and checks every `qs ipc call` against the `IpcHandler`s. It catches
syntax errors, unknown imports and components, misspelt ids, properties and
singleton members, and binds to a missing IPC target or function. It does
not catch anything at run time (binding loops, JS errors in functions,
wrong values, layout), members read through an outer id inside a delegate
(no file has `pragma ComponentBehavior: Bound`), or members of the types
its allowlist accepts broadly; the full list, and how to read a failure or
add an allowlist line, is in README, "Tests". So after a QML change the
`Configuration Loaded` line in the shell's log is still the proof that it
loads. For Lua, the `hypr-config` check runs `Hyprland --verify-config`
on the repository's files laid out like the install (`tests/hypr/run.sh
verify`); a live edit needs the same on a temporary copy (`config/hypr/*`,
`share/desk/hypr/*`, `XDG_CONFIG_HOME`/`XDG_DATA_HOME` pointed at it). Both
catch a misspelt key name in a bind (`Unknown key`), not a mouse button code
out of range.

**Injected data and previews.** Allowed during development: temporary IPC
targets, a property that points a loader at a fixture, a data override, a
no-focus preview mode on DP-2. Remove them before the report; anything kept
on purpose is named in it (the lock screen's `DESK_LOCK_PREVIEW=1` is kept,
and so is `audio/NoSignal.qml`'s `statusRoot`, pointed at a copy of the
`/proc/asound` tree to simulate a microphone that sends nothing, and the
`readOnly` switches in `office/OfficeShared.qml` and `fleet/FleetShared.qml`,
which start their helper with `--read-only`; README, "Office panel" and
"Fleet panel").
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
  Bluetooth, office, fleet, tailscale, tokens): a root component, one line in `shell.qml`; a small singleton
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
- **Comments** follow the root rules: true, only what the code cannot say,
  never about the task or the history.

## Practices

What working on this shell has taught: the rule, its reason, what taught it.

**Code**

- **Decisions in node-tested `.js`; QML draws and runs effects** (`fleet.js`,
  `tailscale.js`, `tokens.js`, `wifi.js`): the sweep's `.js` fixes landed
  with a failing test, its QML ones stay expected. Not yet: Office's keys.
- **Plain rows, not module objects; look one up by name when an effect runs**
  (`Network.qml:90-100`): Quickshell drops an unsaved `WifiNetwork` as its
  scanner stops.
- **Never write what a binding reads inside its update; `Qt.callLater` it**
  (`Network.qml:369-372`): the network panel's `wifiIn` loop (488df5a).
- **A held key acts once, except keys that move** (`isAutoRepeat`, `repeat`
  in a `.js`; a release only after the surface's own press, `heldArrow`):
  the probe showed flagged repeats and stray releases; a held F forgot a
  network. Repeat: ↑↓ (J K Home End), ←→ in Audio, Office and Calendar,
  PgUp PgDn in Calendar and Tokens, typing. Unguarded: pairing, the lock.
- **Outside text is plain text** (`Text.PlainText`, or `esc()` in
  StyledText): a tag-shaped name draws as markup (over thirty `Text`s,
  f967125, 515518c).
- **Nothing runs while hidden**, and the cost is measured (`/proc/<pid>/stat`
  over 60 s). Named exceptions, for the bar or a warning: bar temperatures
  (5 s), the Tailscale light call (30 s), `desk-fleet`'s probe (5 min),
  `desk-mqtt`, the Bluetooth agent, `NoSignal.qml`, `Reminders.qml`, the
  token item's minute tick.
- **Helpers speak JSON lines, protocol in the `.py`'s docstring.** The QML
  forwards stderr (unread, Quickshell closes it: 4c8dacf), restarts at 2 s
  doubling to 60 s, and resets the back-off only on a healthy line.
  `desk-tokens` runs only while open, on purpose (`TokensShared.qml:39-45`).
  A one-shot command gets a watchdog (`tailscale status`: SIGTERM at 10 s,
  SIGKILL 2 s later).
- **Write atomically and only on change** (`desk-sync.sh:41-44`,
  `claude-limits.sh:106-107`, `calendar-export.py:127-145`): each write wakes
  every watcher; idle sessions made the limits file flip (489eef5).
- **Several writers need a merge rule**: the plan-limit file's is newest
  evidence (herdr README); "highest wins" kept a stale 88 % (7be6975).
- **Fixtures are invented or hand-written in the real format**; the one
  exception, `tests/fleet/fixtures/*.probe`, holds only public fields.
- **Privacy is held by checks**: `tokens-helper` (no network code, no text
  printed), `calendar-export` (counts, no names), `wifi-panel` (no password
  in state), `office-helper` (errors name the key, not the value),
  `desk-sync` (secret-shaped lines refused).
- **Set `TZ` in a check's script**: the builder resets a derivation's to UTC
  (`tests/default.nix:121`); `calendar-panel` passed vacuously (f35eef7).
- **No new inline component in a loaded file**: a hot reload may not
  register it (489eef5).

**Nix and the two layers**

- **A switch leaves a live-edited file**, its new copy in `incoming/`, which
  `pull` refuses, so an old edit cannot overwrite newer work (f35eef7).
- **No store path in a `user/` file**: the copy outlives its generation (the
  mpv shim's crash loop, 8dd7558); pass it on a command line (hyprpaper's
  `-c`).
- **Monitors by description where the tool allows** (hyprpaper's `desc:`,
  `default.nix:54-58`): connector numbers follow probe order (6b035fa).
  Hyprland and the bar still name DP-1 and DP-2.
- **`quickshell-lint`** catches syntax, imports, names and IPC calls to
  nothing; nothing at run time, nor members through an outer id in a
  delegate. Full list: README, "Tests".

**Live work** (the rules: "The user's desktop is in use")

- **Repository first, then live as a group** (`.js` before `.qml`): a
  half-applied state logged warnings, so a mixed state is no test.
- **Only a changed `.qml` reloads the shell**: not a `touch`, not a `.js`
  alone (seen 2026-11-17).
- **Temporary hooks are removed, and their absence proven by `grep`.**

### Checklists

Files that change together, walked through the example named. "Caught" is
what a check catches if one is forgotten; nothing catches the rest.

- **Drop-down panel** (the token panel): the QML in "Code map", "To add a
  drop-down panel"; `name/name.js` and its check; the bar item and bind
  below; README's section, Contents, table and panel counts; the code map's
  rows. Caught: calls to a missing target, misspelt members (lint).
- **Removing one**: the same. Lint fails while a bind names it, evaluation
  while `tests/default.nix` does. The live files stay: delete them by hand.
- **Bar item** (`Bar.qml:503-562`): the item, its look from the `.js`
  (`limits().bar`) and a test, README's Bar sentence, and an entry under
  "Nothing runs while hidden" if it runs while closed. Caught: names.
- **Helper** (`desk-tokens`): `.py` with its docstring, `.nix`,
  `home.packages`, the `Process`, a helper check, README section, code map.
  A secret (`desk-mqtt`): `secrets/secrets.nix`, `age.secrets` in
  `flake.nix`, the path (`default.nix:124`), the `.age` in git. Caught: the
  build, the check; a missing `home.packages` entry only at run time.
- **Check** (`common-panel`): `tests/<name>/` and its attribute, in
  `brightfalls-tests` by itself (`tests/default.nix:19-24`); `git add`
  first; README "Tests", the code map's `tests/` row. `-L` prints the
  failing derivation's log.
- **Bind** (Super+U in `bindings.lua`): `bind()`, for the cheat sheet; a
  free key (`hyprctl binds`); the IPC target; README's table. Caught: the
  call's target, function and arguments (lint); a misspelt key
  (`hypr-config`, by hand). Not: a taken key.

### Never without the owner's eyes

Eyes: the owner, at the machine, does the step that matters.

- **The lock** (`lock.qml`, `lock/`, `Theme.qml`, `LockState.qml`,
  `desk-lock` PAM, `desk-unlock.sh`): a fault locks the owner out. The
  preview, then the owner unlocks a real lock; the recovery tried.
- **Bluetooth pairing** (`Agent.qml`, `PairModal.qml`, `bt-agent.py`): it
  answers BlueZ. The owner pairs a real phone.
- **The office light and blind, the fleet's switch, boot, mode and reboot**
  (`desk-mqtt.py`, `office.js`, `Office.qml`; `desk-fleet.py`, `fleet.js`,
  `Fleet.qml`): real devices, real machines. The owner presses the keys.
- **Passwords and saved networks** (`Polkit.qml`, `PasswordModal.qml`, F):
  a held Enter spends a PAM attempt, F deletes a profile. The owner.
- **The session menu's reboot and shut down**: the owner. **Overlay
  surfaces** (a game under one loses scanout): the owner, over a real game.

## Code map

Paths are relative to this directory. Line counts change; the shape should
not.

**Nix and helpers**

| Path | What |
|------|------|
| `../../../desktop-hyprland.nix` | System side: Hyprland with UWSM and the hidden plain entry, udev GPU links, logind keys, `desk-lock` PAM service, Fira Sans, and every generated `locked.json` |
| `default.nix` | User side: the two layers, `desk-sync` and `desk-unlock` packages, the commands binds and panels run, the `quickshell` and `hyprpaper` user services (the wallpaper's config), the Tailscale panel's mesh-host file (`~/.local/share/desk/tailscale/hosts.json`, from `lib/ssh-mesh.nix` and `lib/host-kinds.nix`), imports `calendar.nix` |
| `calendar.nix` | `pimsync.conf`, `source.json`, `calendar-sync.service` and `.timer` |
| `calendar-export.nix`, `calendar-export.py` | The export step (khal, time-zone fix, alarms) and its khal config; shared with the check |
| `bt-agent.nix`, `bt-agent.py` | `desk-bt-agent`, the BlueZ pairing agent the shell runs (JSON lines on stdin/stdout); also reports each device's links, calls from PipeWire's telephony service on the session bus |
| `desk-mqtt.nix`, `desk-mqtt.py` | `desk-mqtt`, the office panel's MQTT client (JSON lines on stdin/stdout): watches the light, blind and sockets on Zigbee2MQTT, publishes only the light's and blind's `/set`; the device ids and labels are in the `.nix`, the broker and names in the `office-mqtt` agenix secret (README, "Office: desk-mqtt") |
| `desk-fleet.nix`, `desk-fleet.py` | `desk-fleet`, the fleet panel's helper (JSON lines on stdin/stdout): probes this machine and its SSH mesh hosts read-only, reads the pipeline through `gh`, decides each host's row (`host_row()`, pure) and runs switch, boot and mode through `comin-deploy` and reboot through `systemctl reboot`, in private tmux sessions; the host list is generated from `lib/ssh-mesh.nix` and `lib/host-kinds.nix` (README, "Fleet: desk-fleet"). Run by `fleet/FleetShared.qml` |
| `desk-tokens.nix`, `desk-tokens.py`, `desk-tokens-prices.json` | `desk-tokens`, the token panel's helper (JSON lines on stdin/stdout): reads Claude Code's transcripts incrementally into a SQLite index of replies (counters, ids, model, time, working directory; never text), folds working directories into projects (`fold_cwd()`, pure) and answers the overview, projects, project and days pages; the price table is built in (README, "Tokens: desk-tokens") |
| `desk-sync.sh` | `desk-sync activate|status|reset|pull` |
| `desk-unlock.sh` | Recovery from a text console when the lock screen dies |
| `gen-emoji.py` | Generates `user/quickshell/launcher/emoji.txt` (not installed) |
| `tests/` | Flake checks, and `brightfalls-tests`, every check but `hypr-config` (README, "Tests"): `run.sh` (desk-sync), `calendar/fixtures` + `expected.jsonl` (export), `calendar/panel/` (queries.js under node in London time), `bluetooth/` (services.js and devices.js under node), `tray/` (menu.js under node, button types from Quickshell's type file), `common-panel/` (common/notify.js under node, its arguments read as gdbus reads them), `office-panel/` (office.js under node, hand-written helper lines in `fixtures/`), `office/` (desk-mqtt against a loopback Mosquitto), `system/` (decode.js under node), `display-layout/` (display-layout.sh against a fake hyprctl), `hypr/` (`run.sh verify`: the Lua through `Hyprland --verify-config`, the `hypr-config` check; `run.sh theme`: theme.lua under Lua, the `hypr-theme` check), `desk-unlock/` (desk-unlock.sh against fakes), `bluetooth/test-bt-agent.py` (desk-bt-agent against private D-Bus daemons), `audio-output-cycle/` (audio-output-cycle against fake PipeWire tools), `fleet/` (desk-fleet's model against cut-down real probes in `fixtures/` and built cases, then the helper against fakes), `fleet-panel/` (fleet.js under node, hand-written helper lines in `fixtures/`), `tailscale-panel/` (tailscale.js under node, hand-made status answers in `fixtures/`), `wifi-panel/` (wifi.js under node, invented networks and the module's enum names in `fixtures/`, checked against the installed Quickshell's type file), `tokens/` (desk-tokens' pure functions, then the built helper against invented transcript trees built by the test), `tokens-panel/` (tokens.js under node in New York time, hand-written helper answers and limits files in `fixtures/`), `quickshell-lint/` (`run.sh`: qmllint over `user/quickshell` laid out as Quickshell does, `ipc.js`: every `qs ipc call` against the `IpcHandler`s, `allowlist`: accepted warnings with their causes) |
| `defaults/hypr/` | Read-only layer: `rescue.lua` (terminal, reload, exit, restore-monitors binds), `theme.lua` |
| `../../../display-layout.sh` | `display-layout single` and `restore`, behind `single-monitor` and Super+Shift+D (built in `gaming.nix`) |
| `../../../../../assets/wallpapers/` | `left.png` (DP-1) and `right.png` (DP-2), drawn by the `hyprpaper` service declared in `default.nix`, monitors matched by description (README, "Wallpaper") |
| `user/desk/theme.json` | The palette |
| `../../../audio/` | PipeWire and WirePlumber settings the audio panel reports, Bluetooth codecs |

**Hyprland** (`user/hypr/`): `hyprland.lua` (entry, requires the rest, then
`rescue.lua`), `monitors.lua` (outputs, workspace rules), `input.lua`,
`looknfeel.lua` (gaps, animations, tearing, scanout, `disable_autoreload`),
`rules.lua` (game rule, critical-notification and calendar big-view layer
rules), `bindings.lua` (every bind, through `bind()`), `autostart.lua`.

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
| `Network.qml`, `Audio.qml`, `Calendar.qml`, `System.qml`, `BluetoothPanel.qml`, `Office.qml`, `Fleet.qml`, `Tailscale.qml`, `Tokens.qml` | The nine drop-down panels (each the biggest file of its feature) |
| `CalendarFull.qml` | The calendar's big view: a centred card 80 % of the monitor, blurred behind (layer rule in `hypr/rules.lua`), in `Dropdowns` as `calendarfull`, no bar item |
| `Lockscreen.qml`, `LockState.qml` | The shell's side of the lock: IPC `lockscreen`, hold, sleep inhibitor; the launch command and `held` state |
| `lock.qml` | The lock process itself (a separate Quickshell config) |

Directories (`import qs.<dir>`):

| Directory | What |
|-----------|------|
| `common/` | Shared by panels: `Style.qml` (singleton: bar metrics, `panelTop`, edge, radius, the cards' `growDuration`, surface, soft, track, scrim colours), `Dropdowns.qml` (singleton registry: `add()` a panel, `closeOthers()`, `anchor()`/`centre()` for placement), `DropCard.qml` (the card, shadow, placement and eased height), `KeyHints.qml` (the drop-downs' footer: hints that wrap, or a wrapped `message` in their place), `LockedList.qml` (loads `locked.json` for an area), `NixTag.qml`, `SectionHeader.qml`, `notify.js` (the `gdbus … Notify` command for the shell's three notification senders, its text quoted so gdbus passes it unchanged; node-tested) |
| `launcher/` | `Calc.qml` (parser, evaluator), `Emoji.qml` (lazy list, search), `emoji.txt` (generated) |
| `notifications/` | `Card.qml` (one card), `Entry.qml` (timeout, replacement, leave animation) |
| `network/` | `NetworkPanel.qml` (singleton shared with the bar: `screen`, `toggleRequested`), `SpeedTest.qml` (providers, process, parsing), `Gauge.qml`, `PasswordModal.qml` (the Wi-Fi password modal: masked field, `take()` hands the text over once and empties it), `wifi.js` (all Wi-Fi decisions: section state, rows and order, security words, password check, the join/forget/cancel machine and its effects, hints, details, bar look; node-tested) |
| `audio/` | `AudioPanel.qml` (shared singleton), `Stack.qml` (the DAC drawing), `Modi.qml` (`/proc/asound` reads), `Graph.qml` (`pw-dump`), `Level.qml` (level bar), `NoSignal.qml` (singleton, runs always) |
| `calendar/` | `CalendarPanel.qml` (shared singleton, also the export loader, minute clock and bar hint), `CalendarFullShared.qml` (the big view's singleton: `screen`, `toggleRequested`, `showRequested`), `CalendarActions.qml` (sync, web calendar and flash for one view; one per view, polls only while it is open), `MonthCell.qml` (a big-view day cell), `Reminders.qml` (reminders, digest, held items), `queries.js` (all calendar decisions, the big view's cells and keys included; node-tested) |
| `system/` | `SystemPanel.qml` (shared singleton), `Sensors.qml` (singleton, every read, at three levels), `decode.js` (gpu_metrics and /proc parsing, throttle decode, when a slow read is due; node-tested), `Machine.qml` (drawing), `Ring.qml`, `Temperatures.qml` (bar hover list) |
| `bluetooth/` | `BluetoothShared.qml` (shared singleton: adapter, devices, RSSI, links, answers, low battery), `Agent.qml` (runs `desk-bt-agent`, open requests), `PairModal.qml`, `services.js`, `devices.js` (node-testable) |
| `office/` | `OfficeShared.qml` (shared singleton: `screen`, `toggleRequested`, `readOnly`, runs `desk-mqtt` and restarts it, `office` state, `send()`, `failed`), `office.js` (all office decisions: applying helper events, ages, percent ↔ raw, locks, row texts, banners, bar view; node-tested) |
| `fleet/` | `FleetShared.qml` (shared singleton: `screen`, `toggleRequested`, `said`, `readOnly`, runs `desk-fleet` and restarts it, `fleet` state, `send()`, `open`/`closed` to the helper), `fleet.js` (all fleet decisions: applying helper events, order, header, pipeline, row views and folding, info lines, keys lit, questions, key to command, navigation, footer texts, whether a spinner turns, bar view; node-tested) |
| `tailscale/` | `TailscaleShared.qml` (shared singleton: `screen`, `toggleRequested`, the light and full `tailscale status` calls, the watchdog, `answer`, the mesh-host file), `tailscale.js` (all Tailscale decisions: a status call's result sorted into a state, the lines over it, the well, groups, rows, chips, second lines, details, copy choices, ssh allowed or why not, key to action, navigation by peer ID, footer hints, bar look, last-seen, expiry and byte wording; node-tested) |
| `tokens/` | `TokensShared.qml` (shared singleton: `screen`, `toggleRequested`, runs `desk-tokens` only while the panel is open and restarts it, the panel state `st`, `key()`, the limits file and its directory watch, the minute tick, `limits`, `said`), `tokens.js` (all token-panel decisions: applying the helper's answers and events and which of them reset the restart back-off, re-asks, every page's view and texts, key to action, footer hints, the limits file's reading, its "as of" times and the line after R, the bar look, the hand-set `PLAN`; node-tested) |
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
`bluetooth/BluetoothShared.qml`, `office/OfficeShared.qml` (which also
runs the helper, so the bar has the light and the watts while the panel is
closed), `fleet/FleetShared.qml` (which also runs the helper, so the bar has
its count), `tailscale/TailscaleShared.qml`, `tokens/TokensShared.qml`
(which also holds the limits reading the bar shows) and, for the tray menu,
`tray/TrayShared.qml`. `*Panel` and `*Shared` are the same role under two
names; a new one is `*Shared`. "Panel" does not mean placement only:
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
anything it shows. The calendar panel, the shortest, is the model to copy;
the rest of what changes with it is under "Practices", "Checklists".

## State and open work

As of the date at the top.

**Built and on `master`:** the session under UWSM, the config machinery and
`desk-sync`, the palette, launcher (apps, calculator, emoji), bar,
notifications (critical ones above fullscreen), OSD, cheat sheet, session
menu, polkit dialog, network panel with speed test (two providers), audio
panel (the DAC stack, per-program rows and levels, inputs, no-signal flag),
clock and calendar (sync, export, reminders, digest), system panel,
Bluetooth panel with pairing agent, lock screen with a recovery command,
tray right-click menus drawn by the shell (`tray/`), office panel (light,
blind, sockets' power through `desk-mqtt`; live, not read-only), fleet panel
(Super+G: each host's system, comin, next boot, one chip, and switch, boot,
mode, reboot, diff, ssh and output through `desk-fleet`; `readOnly: false`,
live as deployed), Tailscale panel (Super+V:
this computer and every device in the tailnet, read-only), Wi-Fi in the
network panel (radio, scan, join, forget, the password modal, the bar mark;
the radio off at every boot through `wifi-radio-off-at-boot` in
`hosts/BrightFalls/networking.nix`), token panel (Super+U: Claude Code
usage through `desk-tokens` and the plan limits from the status line's file,
read-only).

**Live now, ahead of the deploy:** every QML and `.js` file of the sweep's
fixes was copied into the live `~/.config/quickshell` on 2026-11-17 and
loaded without a warning (`diff -rq` of the live tree against `user/`
silent, `qs ipc show` unchanged). `desk-sync status` shows the 37 changed
files as `edited`; `common/notify.js` is not in the deployed manifest.
There are no stand-ins.

**To do at the next deploy:**
- Nothing to undo by hand: the 37 `edited` files match the new generation and
  turn `clean`, and `common/notify.js` is installed with the same content.
  Check `desk-sync status` is all `clean`.
- The plan-limit writer (`modules/home-manager/herdr/scripts/claude-limits.sh`)
  changes only at the switch. After it, each window in
  `$XDG_RUNTIME_DIR/desk/claude-limits.json` has `evidence_at` and `kind`.
  Until then the token panel's weekly row says `as of` the old writer's last
  rewrite.

From the token panel's deploy, done or not by now, no report says:
- One `hyprctl reload` (then `hyprctl configerrors`) for Super+O, Super+G,
  Super+V and Super+U, if the running Hyprland has not loaded them; the
  cheat sheet lists "Tokens" in the Session group once it has.
- `~/.config/mako/` is left over from before the shell was the notification
  daemon (`desk-sync` leaves dropped files alone); delete it.
- `systemctl --user restart quickshell`, if the shell has not started since
  `shell.qml` lost `//@ pragma UseQApplication` (pragmas are read at startup
  only); then check its log is clean.

**Never tested:**
- The final lock build (self-release removed) locked for real; the lock
  before sleep; `desk-unlock`'s fallback for a hung lock process (simulated
  only, in the `desk-unlock` check).
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
  (simulated with hand-written helper lines, and node-tested): the broker lost,
  Zigbee2MQTT offline, a device offline, a command not confirmed.
- Fleet panel: seen for real only read-only, by an agent (the real fleet's
  rows, the bar item with its count and dim, a switch sent with the row's
  generation and refused, A with no session, F5, T and D on this computer,
  the helper-not-found line). Fixtures and node only: every chip, the
  questions and the mode chooser, an action running, ok, failed and the
  sudo message, the GitHub banner, long texts. Never done: real key presses
  and clicks, Super+G in a reloaded session, O, and any real switch, boot,
  mode change, reboot or attach to a real session; the user's first switch
  is the first. The helper's actions are proven only against fakes
  (`fleet-helper`).
- Tailscale panel: seen for real only Running, with an agent's real keys
  (F5, J, K, Home, End, Enter, Y, 2, Esc, T on Nexus). Every other state,
  overlay and chip is simulated with fixtures; O, the arrows and Super+V in
  a reloaded session not done.
- Wi-Fi: simulated only, through a data override in the live shell since
  removed: all twelve designed states, the password modal, the bar's three
  cases, and every key and event sequence (driven through the panel's key
  function, not real key presses). Seen for real only `No Wi-Fi device.`
  before the driver was enabled. Never done: a real radio toggle, scan,
  join, wrong password or forget; real key presses in the panel; the modal
  with keyboard focus; the 30 s watchdog firing on its own. Upstream
  Quickshell has open crash reports around toggling the radio and access
  points coming and going; whether 0.3.2 has them fixed is not confirmed,
  so the first W is also the first test of those.
- Token panel: seen for real by an agent, with the real helper on a scratch
  index (the first read's progress, every page from real answers, no helper
  after closing) and the bar item on the real bar with a scratch limits
  file. Simulated with a stand-in helper and keys over a temporary IPC
  target: every page state, every key and the keys that must do nothing,
  long names eliding, the helper missing, stopped and recovering, the limits
  watch (directory and file created after the shell started, replaced by
  rename), no helper process after every close, the figures at API
  prices on every page (unpriced and partly unpriced, the widest figures, S
  in both orders) and every page from a helper without cost fields. Never
  done: real key presses and clicks, the window with real keyboard focus,
  Super+U in a reloaded session, the limits file written by a real Claude
  Code session, the figures from the real helper's answers.
- The sweep's fixes (2026-11-17): live and loading cleanly (the agent's
  check of the log). Seen for real by the user at the keyboard, 2026-11-17,
  and nothing wider: M held in the audio panel mutes once; R in the session
  menu arms once, then Esc; Super+K over the open system panel closes the
  panel; the network footer's Enter and Esc labels; the token panel's `as
  of` time and the line after R. Expected only, from the code and the
  checks: the OSD's Bluetooth glyph from the state; outside names drawn
  as plain text (bar, OSD, notification cards, the calendar, network,
  audio, office, system, Bluetooth, launcher and polkit panels, the speed
  test); the one notification sender (`common/notify.js`) in the Bluetooth,
  no-signal and reminder notifications; the office panel with no sockets;
  the token helper's stderr in the log, its back-off and a close before it
  started; reminders sent once; slow sensors read at most every 10 s; the
  logind watch restarted after it ends; the fleet spinner; a held key
  acting once except the moving keys in the other panels and modals; the
  other centred modals closing the drop-downs; the speed test reading the
  route when the chooser opens, and a cancelled run's end ignored; wrapping
  in the wired details, Nix labels and speed-test failure; Audio's footer;
  the polkit field cleared on hide; Office's release only after its own
  press; `R refresh counts`; the bar's weekly figure from the new limits
  writer, which is not live until the switch.
- Calendar big view (Super+Shift+C, F from the drop-down): built and
  checked only (lint, verify-config, node); never loaded, seen or keyed
  live; the blur and the dim never seen.
- Most pointer and key input was driven by the user, not by agents; whatever
  a report lists as expected still is.

**Not built:**
- Friendly launcher category names, scrolling for panels taller than the screen (the audio panel runs
  off the bottom with many programs).

**Code follow-ups** (estimates for one agent working live; the ones that
change what the user sees need the user's look first):
1. **Pure logic out of QML into node-tested `.js`** (1 to 3 h a library):
   - Network's wired half: the nmcli, route and duplex parsers
     (`Network.qml:871-916`), the `speedtests.jsonl` reduction, written
     twice (`:533-545`, `:927-945`), `age()` (`:475`), the gauge scale.
     Wi-Fi's decisions are already in `network/wifi.js`.
   - Audio: `facts()` and `details()` (`Audio.qml:219-283`), whose verdict
     rules are written twice, and the path text.
   - Cheatsheet: grouping, keycaps and column balancing
     (`Cheatsheet.qml:58-161`).
   - Bluetooth: `codecName()` and `rowSub()` (`BluetoothPanel.qml:378-435`)
     into `bluetooth/devices.js`. `details()` stays: it reads PipeWire.
   - The calculator (`launcher/Calc.qml`, all of it pure) and `Apps.rank`
     (`Apps.qml:46`), with a launcher check; its float results are wrong
     today (see the defects below).
   - `Sensors.parseTopo` (`system/Sensors.qml:52`) into `system/decode.js`.
   - Office's key, release and commit rules (`Office.qml:131-186`) into
     `office/office.js`; they drive the real light and blind.
   - `network/SpeedTest.qml`'s parsers (`parseCloudflare`,
     `parseSpeedtest`): they emit signals and change state as they parse,
     so they need splitting into parse and apply first.
2. **Shared drop-down window, row selection, bar open mark** (3 to 4 h):
   the `PanelWindow` shell (layer, focus, click-off, key forwarding) is
   copied in ten files, the nine panels and `tray/TrayMenu.qml`, with four
   different key-forwarding signatures; Network, Audio and Bluetooth have
   identical selection code; `Bar.qml` draws the 14×2 open mark nine times.
3. **Small ones** (minutes each): `#191a21` (text on purple) is hard-coded
   in `Polkit.qml:303` and `BluetoothPanel.qml:1021`; `lock/LockFace.qml`
   copies the "soft" formula (leave it until the lock can be re-tested);
   `Apps.qml:93` keeps a `scan.again` flag for what setting `running` on a
   running `Process` already does (as `audio/Graph.qml` now relies on); the
   `\n` escape in `common/notify.js` has no failing assertion behind it.
   Live only, not in the repository: `~/.config/hypr/dms/`, unused
   DankMaterialShell output (the user's call).
4. **Typing the lint check accepts by name** (each a rename or a type, then
   the matching line out of `tests/quickshell-lint/allowlist`):
   `System.qml:208` declares `property var rows` on a `Grid`, over Grid's own
   row count (rename it, say `pairs`); `lock/LockFace.qml:261` declares
   `property string state`, over Item's states machinery (rename it, say
   `fieldState`; test it in the lock preview); `Network.qml:1126` types the
   wired rows as `NetworkDevice` while `hasLink` and `linkSpeed` are on
   `WiredDevice`. All three work today.
5. **`pragma ComponentBehavior: Bound`** in the delegate-heavy files would
   let `quickshell-lint` check members read through an outer id inside a
   delegate. It changes how delegates resolve ids, so it is a QML change to
   each panel, tested live one panel at a time; an option, not a fix.

Not worth doing, so off the list: a helper to pick the screen by name (17
identical one-liners; a helper replaces one line with one line and has no
natural home); a shared flash timer (seven copies of 11 lines whose
durations differ by design and are documented); renaming
`BluetoothPanel.qml` (`Bluetooth` is Quickshell's own singleton, and a
rename leaves stale live files; the naming rule is under "Names to know").

**Open defects**, read in the source and not reproduced live (each small):
- `lock.qml:213`: the second half of the completion test (a failure whose
  last message was an error) never passes, because Quickshell clears
  `messageIsError` before it emits `completed` (`src/services/pam/qml.cpp`;
  seen with the `qs` binary against a scratch PAM stack). Nothing in the
  shipped `desk-lock` stack sends a message during a check, so no state is
  lost today. A repair tests `systemMessage` alone: `pam_faillock` sends its
  lockout notice as information, not as an error. Needs the owner's lock
  test.
- `BluetoothPanel.qml:604-605`: Esc on a code shown for a pairing the
  device started only closes the modal, which opens again at the device's
  next key. The cancel needs `d.pairing`, which Quickshell sets only in its
  own `pair()`. Needs a Bluetooth keyboard to prove.
- `Audio.qml` `pathHops()`: the path ends at the Modi whenever a Modi sink
  exists, whatever the default output is.
- A drop-down's bind can open it over a centred modal (launcher, cheat
  sheet, session menu, polkit dialog): the modals are not in `Dropdowns`,
  so nothing closes them. Not seen in this direction, but a bind was seen
  to fire under a drop-down's exclusive keyboard (the probe); the other
  direction is fixed (the modals call `Dropdowns.closeOthers("")`). Needs
  the modals in `Dropdowns` or the shared window (follow-up 2).
- `launcher/Calc.qml:56,93-105`: float results (`floor((0.1+0.7)*10)` gives
  7, `1 % 0.1` gives 0.1); fix with the move to `.js` above.
- `network/SpeedTest.qml` route: if the route query started by the panel's
  opening still runs when the chooser opens, that earlier read is used.
- Quickshell's `Process`, read in its source (`src/io/process.cpp:290-299`),
  not seen: a restart asked for while a start fails is lost, for any
  `Process` in the shell.
- `desk-sync.sh:43-44`: `reset` on a live directory at a manifest file's
  path fails ("could not reset") and leaves `<path>.desk-new` beside it.
  A hand-made state; removing the stray file on a failed `mv` is one line.
- `desk-fleet.py`: a restarted helper refuses a second action on a host
  whose earlier action still runs, but does not follow or report that
  action; only `attach` shows it.

Leave until that code is touched (each needs a real phone or a real lock to
re-prove): `BluetoothPanel.qml:94-96`, the "trusted on yes" list is lost by
a reload mid-pairing; `bluetooth/PairModal.qml`, a held Enter or T can
answer the next request unseen (BlueZ often follows a confirmed pairing at
once with a service question, and T allows and trusts), and the remote
device's name, chosen by that device, is drawn as markup in the title and
the T line; `lock.qml:193-197`, a visible PAM prompt would leave the lock in
"checking" (unreachable with the shipped PAM stack, fails closed).

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
the automatic login and tuigreet after a logout; the SSH agent; file dialogs, screen sharing and dark GTK apps through the portals;
the default apps; printing; the CPU's energy preference without
power-profiles-daemon (it was `balance_performance`); no failed units.

**To investigate:** the `hypr-config` check fails on GitHub's runners
(ubuntu-24.04, Nix sandbox): `Hyprland --verify-config` on the full
`hyprland.lua` exits 139 (a segfault), while `rescue.lua` and `theme.lua`
alone and every other assertion pass; the same derivation passes on
BrightFalls. It is out of the `brightfalls-tests` job until this is
understood. Leads: what differs on the runner (no `/dev/dri`, the CPU, the
kernel); which part of the config triggers it, bisected with temporary CI
runs.

**Known bugs, pinned by the checks and not fixed** (each check says what
to change once the bug is fixed):
- Latent, unreachable with the shipped data: `queries.js` `parse`
  throws on a broken day line instead of returning null (`calendar-panel`).

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
- Warnings the shell logs now and then, older than the sweep and harmless
  as far as read (line numbers as logged by the deployed files):
  `@calendar/CalendarPanel.qml[23:5]: Unable to assign [undefined] to
  QDateTime` on a reload (`now` binds to a `SystemClock` declared after it,
  and is set again at the clock's first tick); `@Tokens.qml[536:17]: Unable
  to assign [undefined] to QString` (a cell's `text: modelData[0]`, cause not
  established); `@audio/NoSignal.qml[88:-1]: TypeError: Cannot read property
  'properties' of null` at start (now line 92, `statusPath` reading a null
  `node`, cause not established).
