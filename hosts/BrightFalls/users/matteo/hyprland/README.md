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
  `uwsm app -- <id>.desktop`, each in its own systemd scope. A query
  starting with `=` is a calculator (arithmetic, `^`, `%`, `sqrt abs round
  floor ceil`, `pi e`; its own parser, no interpreter) and one starting with
  `:` searches emoji by name; the prefix shows as a chip, Backspace on an
  empty query goes back to apps, and Enter copies the result or emoji with
  `wl-copy`. Their parts are in `launcher/`: `Calc.qml`, `Emoji.qml` and
  `emoji.txt`, the emoji list, read on first use. `emoji.txt` is generated
  from the pinned `unicode-emoji` package by `gen-emoji.py` (beside this
  README, not installed), whose header has the command.
- `Bar.qml`: a floating rounded strip on every monitor, 6 px
  from the top, left and right edges and 34 px tall including its border.
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
- `SessionMenu.qml` (Super+Escape or the power key, `qs ipc call session
  toggle`): a modal on the focused monitor with Lock (disabled until there is
  a lock screen), Log out (`uwsm stop`), Switch to GNOME (sets the user's
  saved session in AccountsService to `gnome`, which GDM's greeter
  preselects, then logs out), Reboot and Shut down. Up/Down and Enter, or the
  row's letter; Reboot and Shut down act on a second press. logind ignores a
  short press of the power key (`desktop-hyprland.nix`) so the menu can take
  it; a long press still powers off.
- `Polkit.qml`: the session's polkit authentication agent, in place of
  hyprpolkitagent. Each request is a modal on the focused monitor with the
  message, the identity, a password field and the action id; Enter
  authenticates, Esc cancels, a wrong password clears the field and says so.
  Requests queue and show one at a time. `qs ipc call polkit cancel` cancels
  the one showing. Quickshell tries to register the agent once per process,
  when `Polkit.qml` first loads, and reloads keep that registration; if
  another agent held the session then, it takes a Quickshell restart.
- `Network.qml` (Super+N, a click on the bar's network icon, `qs ipc call
  network toggle`; parts in `network/`): a 380 px panel under the bar's
  network icon on that monitor, with the icon marked while it is open. Wired
  devices first: a connected one shows link speed, IPv4 address and its last
  speed test, and Enter opens its details (address, gateway, DNS, MAC, link
  speed and duplex); Enter never disconnects. Addresses come from `nmcli`, the
  default route from `ip`, duplex from sysfs, all read when the panel opens;
  the rest from `Quickshell.Networking`. Then "Set in Nix": greyed rows read
  from `~/.local/share/desk/network/locked.json`, which
  `desktop-hyprland.nix` generates from the system configuration (Tailscale
  on, IPv6 off, Wake-on-LAN interfaces, hostname, firewall on; a row only
  while the setting has that value), each naming the repo file that sets it,
  which Enter shows in the footer. Up/Down move, Esc closes details, then the
  panel. S opens a chooser in place of the list: 1 Cloudflare
  (`cfspeedtest`, speed.cloudflare.com), 2 Speedtest.net (the Ookla CLI,
  `speedtest`, nearest server; unfree, its licence and GDPR notice accepted
  on its command line), 3 All in turn. Each provider row shows its own last
  result. The provider used last is preselected (Cloudflare with no history),
  so S then Enter repeats the previous test; Up/Down and Enter, or the
  number, run a row; Esc returns to the list. Providers (tool, command line,
  how live figures and the result are read) are described only in
  `network/SpeedTest.qml`. A test runs over the connection carrying the
  default route: latency, then download, then upload on two gauges with one
  shared scale: the interface's negotiated link speed, or, when that is
  unknown, the smallest of 100 Mb/s to 10 Gb/s that holds that connection's
  best stored result; a reading above it grows the scale to the next of
  those that holds it. The line under the gauges names the provider. Esc
  during a run kills it, stores nothing and returns to the list; a failure
  shows under empty gauges, Enter retries. All in turn adds provider chips
  above the gauges (current lit, finished green) and a table under them
  (down, up, ping per provider; a failed one says "failed" and the next
  still runs); when all are done the gauges show the fastest result and the
  screen stays until Esc. Esc during it stops the current run and keeps
  the finished ones. Each completed run is appended as one JSON line (`at`,
  `connection`, `interface`, `download_mbps`, `upload_mbps`, `ping_ms`,
  `provider` (`cloudflare` or `speedtest`; older lines without it count as
  Cloudflare), `tool`) to `~/.local/state/desk/speedtests.jsonl`, never
  trimmed. The row shows the newest run per NetworkManager connection and
  its provider; details list the last run of each provider. fast.com's
  `fast-cli` is not used: it rounds rates of 1 Gb/s and over to whole Gb/s.
- `Audio.qml` (Super+A, a middle click on the bar's audio item, `qs ipc
  call audio toggle`; parts in `audio/`): a 400 px panel under the bar's
  audio item on that monitor, with the item marked while it is open; opening
  it closes the network panel and the other way round. The output switcher
  stays on the bar (left click cycles, right click mutes, wheel sets the
  volume). Nothing runs while it is closed.
  - The stack (`audio/Stack.qml`): Magni 2 on Modi 2. The Magni is analog
    and never has a state. The Modi's light is cyan while its ALSA device is
    open, white while closed (idle), and the Modi is dashed and dim with no
    Modi sink in PipeWire ("missing"). Beside it the format it is open with
    and chips of what it can take, the current ones lit. Capabilities come
    from `/proc/asound/card<N>/stream0`, the open format from
    `pcm0p/sub0/hw_params` ("closed" when idle); N is the Modi sink's
    `alsa.card` property (`audio/Modi.qml`).
  - The path: how many programs are playing, "mixed at" the graph rate when
    there are several, the surround filter when it is the default output,
    then the Modi with bits/kHz, or the fallback output in orange.
  - Playing: one row per playback stream (filter-chain halves left out),
    including paused ones. The tag is the layer it came through: `pulse`
    (`client.api` = `pipewire-pulse` on the node), `alsa` (`client.api` =
    `alsa` on its client, node named `alsa_playback.*`), `jack`
    (`client.api` = `jack`, from the pipewire-jack source; JACK is not
    installed, so never seen here), otherwise `native`. Then its own rate and
    channels and a verdict: `paused` (no active link), `through <filter>`
    (cyan), `resampled to X` (its rate differs from the graph's), `downmixed
    to stereo`, `volume scaled` (its volume is not 100%; orange) or `direct`
    (green). Left/Right change the selected stream's volume in 5% steps, M
    mutes it, Enter opens details: layer, what it sends (rate, sample format,
    channels), what it becomes (with the stream's own `resample.quality`),
    where it goes, volume, and the graph period from `pw-top`. Formats,
    drivers, client APIs and resampler quality come from one `pw-dump` run
    when the panel opens and whenever streams, links or the default output
    change, plus once 6 s later to see the device suspend
    (`audio/Graph.qml`). Volume, mute, links and link state are Quickshell's
    (`Quickshell.Services.Pipewire`). A volume set here is a stream volume,
    which WirePlumber remembers for that program. Under the volume, a level
    bar like the inputs' (`audio/Level.qml`, shared with them) shows what the
    program adds to the output: the monitor reads the stream before its
    volume (Quickshell divides the volume out), so the bar multiplies it back
    in; muted or paused, it has no monitor and is flat. A stream lacking a
    channel of its output (mono into the stereo Modi) gets no bar, since
    Quickshell 0.3.2 cannot meter it; its details say "not metered".
  - Inputs: every capture device with its gain, a level bar (Quickshell's
    `PwNodePeakMonitor`, cube-root scale, one capture stream per input while
    the panel is open, none after) with a yellow mark for the peak of the
    last 1.5 s, `default`, its rate, "heard by <program>" for each capture
    stream linked to it, and `clipping` (red) at 0.99 on that scale, kept for
    2 s. Selection runs on from the programs; Left/Right set the gain, M
    mutes, Enter makes it the default input, which WirePlumber keeps until
    another is chosen, over the Nix priority.
  - No signal (`audio/NoSignal.qml`, a singleton that runs whether the panel
    is open or not): an ALSA input whose capture PCM is `RUNNING` while
    `hw_ptr` stays put between two reads 750 ms apart
    (`/proc/asound/card<N>/pcm<D>c/sub<S>/status`, from the node's
    `alsa.card`, `alsa.device` and `alsa.subdevice`) delivers no samples.
    Silence still moves `hw_ptr`, so a quiet room is not flagged. The Blue
    microphone falls into this now and then until its cable is replugged.
    `/proc` is read only while one of the input's links is active (a
    program or a level monitor records from it), and once when the input
    appears (shell start, replug), by opening it for about 1.5 s with a level
    monitor. The row then says `no signal · replug the cable` in red, its
    level is flat with no monitor, and Enter explains in the footer instead
    of making it the default. The bar's audio item gets a red dot. One
    desktop notification (sent over D-Bus to `Notifications.qml`) per input
    and fault; the flag goes when samples flow or the input goes away.
  - Set in Nix: greyed rows from `~/.local/share/desk/audio/locked.json`,
    which `desktop-hyprland.nix` generates the same way as the network
    panel's, from `services.pipewire.extraConfig` and the WirePlumber ALSA
    rules (allowed rates with no fixed rate, the Modi's S24LE format,
    min-quantum and the daemon's `resample.quality`, the Blue microphone's
    session priority); the file comes from the definition that sets each
    value. Enter shows it in the footer. No file, no section.
- `Calendar.qml` (Super+C, a click on the bar's clock, `qs ipc call calendar
  toggle`; parts in `calendar/`): the bar's centre is the clock: the week as
  seven dots, Monday first (gone filled, today large and purple, to come
  hollow), the short date, a ring that fills clockwise from midnight, and the
  time. When timed events start within the hour a cyan note follows it:
  `1 event at 11:00`, `2 events at 11:00`, or `3 events from 10:00` when they
  start at different times; it goes once the last of them has started. The
  panel is a 360 px card under the clock on that monitor, with the time
  marked while it is open; opening it closes the network and audio panels and
  the other way round.
  - The month: ISO week numbers on the left, weekends in pink, today filled,
    the selected day outlined in pink. Dots under a day show which calendars
    have something that day, one per calendar in its own colour, at most
    three. A one-line legend under the month names the calendars present in
    the shown month.
  - The selected day's events are always listed under the month: all-day
    first, past events today faded, several-day events as "day N of M".
    "time zone unknown" in orange means the event's own time zone could not
    be read, so its time may be off.
  - Keys: ←→ move by a day and ↑↓ by a week, across months; PgUp/PgDn change
    month, keeping the day number; T jumps to today; Enter or O opens the
    selected day in the Nextcloud web calendar; Esc closes; R syncs now. A
    click on a day selects it.
  - Read-only. Events come from the export that `calendar-sync` writes (how,
    and the file's format: "Calendar events" below), and the panel answers
    from memory. The header says `syncing…` while a sync runs. An orange
    footer means the last good sync is 30 minutes old or more (the server
    could not be reached) and says when it was; "No calendar is set up"
    means no export exists yet.
  - `calendar/queries.js`, the panel's queries, is plain JavaScript that node
    runs too: `nix build .#checks.x86_64-linux.calendar-panel` tests it
    against invented events (`tests/calendar/panel/`, written by
    `make-fixture.js` there).

- `calendar/Reminders.qml` (decisions in `calendar/queries.js`): reminders and
  the morning digest. The shell turns the calendar export into desktop
  notifications from the "Calendar" app. Each timed event reminds at its own
  alarms. An event with none reminds 60 minutes before it starts. All-day
  events remind only at alarms before their first day, such as "the evening
  before", worded "tomorrow, all day"; on the days they cover, the morning
  digest announces them. Without an alarm, a full-day event counts as
  reminding at 09:00 on its first day, which the digest also covers. The two
  defaults are `DEFAULT_LEAD_MIN` and `DEFAULT_ALL_DAY_TIME` in `queries.js`.
  They copy the Nextcloud Calendar settings "Default reminder for part-day
  events" and "Default reminder for full-day events", which the sync cannot
  read, so change them together with those.

  A reminder card shows the title, then the time range, how long until the
  start, and the calendar, for example "11:00 – 12:00 · in 60 min · Work".
  "time zone unknown" means the event's own time zone could not be read. The
  card stays until dismissed or until 5 minutes after the start. A later
  reminder for the same event replaces it. **Open** shows the day in the
  calendar panel. A reminder whose moment passed while the PC was off still
  fires if the event has not started ("starts in 4 min"). An alarm set at or
  after the start fires while the event runs.

  The digest arrives once a day, at the first login, or at 06:00 if the
  session is already running. Its title is "Today · Sunday 15 November". It
  lists all-day events, then timed ones with their start, at most six lines
  then "and N more", and leaves out what is already over. With nothing on,
  there is no digest.

  While any monitor shows a fullscreen window (a game, or a fullscreen video),
  reminders and the digest are held. When fullscreen ends they arrive at once,
  worded for that moment ("starts in 3 min", "started at 11:00, 25 min ago").
  Events already over are dropped, and more than three come as one summary. A
  maximised window does not hold. A game in borderless-windowed mode is not
  fullscreen to Hyprland and does not hold either. Nothing repeats across
  reloads or reboots: what has fired is kept in `~/.local/state/desk/calendar-
  reminders.json`.

- `System.qml` and `system/`: the system panel. Super+Y or a click on the chip
  in the bar. The bar item shows the CPU's temperature (k10temp Tctl) and the
  eGPU's junction temperature, each orange or red near its limit; resting the
  pointer on it lists every temperature in the machine. The panel draws the
  UM890 Pro, the OCuLink cable and the DEG1 with the RX 6800 XT, its fans
  turning in proportion to the card's real fan speed. Under it, the cable's
  negotiated link against what the root port can do, and "≈ N W chip + card",
  the APU's package power plus the card's board power (not wall power).
  Sections: CPU (load, per-thread load, average clock and the configured
  maximum, tagged `nix` when NixOS sets it, hottest core from the APU's
  metrics, package power); Memory (used = total − available, cache, swap, both
  modules' temperatures); eGPU (load, VRAM, junction, memory temperature, fan
  rpm and duty, power, clocks, voltage, which outputs it drives, a throttling
  tag only while the card reports throttling); iGPU (load, VRAM, clock,
  voltage); Storage and network (NVMe temperature and read/write rate, free
  space for `/`, `/home`, `/mnt/games`, the default route's interface rate).
  ↑↓ choose a section, Enter shows its details (regulator temperatures, power
  limit, who controls the fans, CPU policy and clock limit with the file that
  sets it, link errors if any), Esc closes them, then the panel.

  Everything is read straight from sysfs and procfs (`system/Sensors.qml`),
  never from LACT's socket and never writing anything. Hardware is found by
  name and device path, not hwmon numbers. While the panel is closed only the
  two bar temperatures are read, every 5 seconds; hovering reads the
  temperatures each second; the open panel reads about 30 small files a second
  and a few every 10 seconds. Memory-module alarm files are never read,
  because reading one clears it.

  Deliberately not shown: **link saturation**, because no traffic counter
  exists for this card on this kernel (`pcie_bw` is absent on Navi 21, and
  gpu_metrics v1.3 has no bandwidth fields), so the link line says only what
  was negotiated; **CPU-only power**, because RAPL is root-only, so "package"
  is the whole chip, CPU and built-in graphics together; **per-program use,
  frame rate and frame time**, which are MangoHud's job inside a game;
  **history**, which is not kept. Nothing of this panel is meant to be shown
  over a fullscreen game.

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
  The service has the same `ExecCondition` as `quickshell`, so in the GNOME
  session it is skipped.
- Force a sync: `systemctl --user start calendar-sync.service` (the panel's
  refresh does the same). It blocks until done; `systemctl --user status
  calendar-sync` and `journalctl --user -u calendar-sync` show the outcome.

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
the first.

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

### Reminders

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

### Tests

`nix build .#checks.x86_64-linux.calendar-export` exports
`tests/calendar/fixtures/` (five calendars: a weekly series with an EXDATE,
a moved and a cancelled occurrence; New York; all-day, multi-day and
midnight-crossing events; a cancelled event; an empty calendar; `GMT±hhmm`
and custom zones; a daily all-day series with a cancelled occurrence; and
`fixE`, one event per alarm shape above, including a series whose
overrides have their own alarm and none, an e-mail alarm and Tokyo) as of
2026-11-15 and compares with `tests/calendar/expected.jsonl`. No network, no
secrets. To regenerate the expected file after an intended change, run the
built `calendar-export` with `CALENDAR_NOW=2026-11-15T10:00:00+00:00`, a khal
config from `calendar-export.nix` and that file as the output, and review the
diff.

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
