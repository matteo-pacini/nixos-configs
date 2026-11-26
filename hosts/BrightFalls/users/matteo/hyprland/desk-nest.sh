# desk-nest: the desktop shell, or any part of it, inside a sealed nested
# Hyprland on fixture data. README.md beside this file, "desk-nest".
#
# The Nix wrapper sets, before this text:
#   hyprland    the Hyprland executable; its package directory is how the
#               nested compositor's process is recognised
#   qs          the qs executable
#   nest_lua    the nested compositor's config (nest/hypr/nest.lua)
#   nest_pam    the lock's stand-in PAM directory (nest/pam, built)
#   inner_path  PATH inside the sandbox, after the checkout's nest/fakes/bin
#   icon_dirs   XDG_DATA_DIRS inside: the icon themes' share directories
#               only, so the launcher lists no installed application

usage() {
  cat >&2 <<'EOF'
usage: desk-nest [--name <name>] [--tree <checkout>] <command>
  up [--visible] [--watch] [--demo] [--fixtures <panel>=<name>]... [component...]
                         start a nest (no component named: the harness's default set)
                         --demo: the recording set (README.md, "Recording a tour")
  set [component...]     change the loaded components in place (none: the default set)
  fixtures               list the fixtures
  fixture <panel> <name> switch a panel's fixture
  ipc <args...>          qs ipc against the nested shell
  shot [name]            screenshot inside the nest; prints the PNG's path
  reload                 copy the checkout's shell in and reload it
  watch                  reload on every save in the checkout (until Ctrl+C)
  lock                   the lock screen in the nest; only the word nest-unlock opens it
  record [--clips] <steps> <outdir>
                         play a steps file against a --demo nest, recording it;
                         --clips: one mp4 per scene marker, no captions
  status                 whether it runs, and where its files are
  check                  compare the host session with the snapshot taken at up
  down                   end the nest and check the host
--name runs a second nest beside the first. --tree: the checkout to show
(default: the one the current directory is in); used by up only.
EOF
  exit 2
}

die() {
  echo "desk-nest: $*" >&2
  exit 1
}

components=(Launcher Bar Notifications Osd Cheatsheet SessionMenu Polkit Network Audio Calendar
  CalendarFull System BluetoothPanel Office Fleet Tailscale Tokens Weather TrayMenu Reminders Lockscreen)
units=(graphical-session.target wayland-wm@hyprland.desktop.service
  wayland-session@hyprland.desktop.target hyprland-session.target quickshell.service)
rel=hosts/BrightFalls/users/matteo/hyprland
# Where a --demo nest's wall clock starts. It runs at a hundredth of real
# speed (nest-services clock), so it reads 09:41 for 100 minutes yet moves,
# which the panels' rates need: two samples at one time give no rate.
demo_time="2026-11-25 09:41:00"

name=nest
tree_arg=.
while [ $# -gt 0 ]; do
  case $1 in
  --name)
    [ $# -ge 2 ] || usage
    name=$2
    shift 2
    ;;
  --tree)
    [ $# -ge 2 ] || usage
    tree_arg=$2
    shift 2
    ;;
  *) break ;;
  esac
done
[ $# -ge 1 ] || usage
cmd=$1
shift
[[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "a nest name is lower-case letters, digits and -"

state_home=${XDG_STATE_HOME:-}
# The XDG spec has a relative path ignored: it would put the state wherever
# desk-nest runs, a checkout included.
[[ $state_home == /* ]] || state_home=$HOME/.local/state
state_root=$state_home/desk-nest
state=$state_root/$name
# The files the nest's processes write in the state directory, which is
# otherwise read-only inside, so that the records the host trusts (the
# snapshot, the pids, the checkout, the lock) cannot be changed or replaced.
inside_files=(qs.out hyprland.out fakes.log nested.env lock.out services.out)
uid=$(id -u)
host_rt=${XDG_RUNTIME_DIR:-/run/user/$uid}
hypr_pkg=${hyprland%/bin/*}

# --- the checkout -----------------------------------------------------------

# Sets top (the checkout), hl (the shell's directory in it) and nest (its
# nest/), from a directory inside a checkout of this repository.
use_checkout() {
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) ||
    die "$1 is not inside a git checkout: run desk-nest from a checkout of this repository, or pass --tree"
  hl=$top/$rel
  [ -f "$hl/user/quickshell/shell.qml" ] ||
    die "$top is not a checkout of the BrightFalls shell (no $rel/user/quickshell/shell.qml)"
  nest=$hl/nest
}

# The checkout the running (or last) nest was started from.
saved_checkout() {
  [ -f "$state/checkout" ] || die "no nest named $name has been started (desk-nest up)"
  use_checkout "$(cat "$state/checkout")"
}

need_harness() {
  local f
  for f in "$nest/dev.qml" "$nest/fakes/bin" "$nest/fixtures/index"; do
    [ -e "$f" ] || die "the harness is missing from $top: no $f (a checkout from before the nest harness was merged?)"
  done
}

# The shell's files as a copy in the state directory, with the harness root
# and the lock's stand-in added. A copy, not a bind of the checkout: bwrap
# cannot add a file inside a read-only bind, and an overlay keeps showing a
# file's old version once an editor saves by renaming over it.
sync_tree() {
  mkdir -p "$state/tree"
  rsync -a --delete --exclude /dev.qml --exclude /lock-nest.qml --exclude /pam \
    "$hl/user/quickshell/" "$state/tree/"
  install -m 0644 "$nest/dev.qml" "$state/tree/dev.qml"
  # lock.qml plus one line pointing its PAM check at the stand-in.
  sed 's/^\( *\)config: root\.pamService$/&\n\1configDirectory: "pam"/' \
    "$state/tree/lock.qml" >"$state/tree/lock-nest.qml"
  [ "$(diff "$state/tree/lock.qml" "$state/tree/lock-nest.qml" | grep -c '^>')" = 1 ] ||
    die "lock.qml no longer has the line 'config: root.pamService' the lock's stand-in is added after"
  rm -rf "$state/tree/pam"
  cp -r "$nest_pam" "$state/tree/pam"
  chmod -R u+w "$state/tree/pam"
}

# --- the host session -------------------------------------------------------

# Sets host_env, host_wl and host_sig, or explains why there is no session to
# nest in.
host_session() {
  host_env=$(systemctl --user show-environment 2>&1) ||
    die "cannot reach your user systemd (${host_env:-no answer}). Run desk-nest from a terminal inside the running Hyprland session; a detached terminal (an ssh shell, a tmux server started outside the session) cannot query it."
  host_wl=$(sed -n 's/^WAYLAND_DISPLAY=//p' <<<"$host_env")
  host_sig=$(sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' <<<"$host_env")
  [ -n "$host_wl" ] && [ -n "$host_sig" ] ||
    die "no Wayland session: the user environment has no WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE"
  [ "$(systemctl --user is-active wayland-wm@hyprland.desktop.service || true)" = active ] ||
    die "the Hyprland session (wayland-wm@hyprland.desktop.service) is not active"
  [ -S "$host_rt/$host_wl" ] || die "the session's Wayland socket $host_rt/$host_wl does not exist"
}

# Without the window rule the nest's window maps on the owner's workspace
# with the keyboard until place_window moves it. This reads the file, not
# what Hyprland has loaded (hyprctl lists no window rules); place_window
# still catches a rule not loaded yet.
need_window_rule() {
  local f=${XDG_CONFIG_HOME:-$HOME/.config}/hypr/rules.lua
  grep -qE '^[^-]*name *= *"desk-nest"' "$f" 2>/dev/null ||
    die "$f has no window rule named desk-nest, so the nest's window would open on your workspace and take the keyboard. Deploy a generation whose rules.lua has it (the hl.window_rule named desk-nest in $hl/user/hypr/rules.lua), then run hyprctl reload. Not started."
}

host_hyprctl() {
  HYPRLAND_INSTANCE_SIGNATURE=$host_sig hyprctl "$@"
}

# Arguments: the sandbox pid, `hyprctl -j clients`, `hyprctl -j activewindow`.
# One line per aquamarine window on the host: address, ours (its process
# descends from the sandbox) or other, focused or unfocused, floating or
# tiled, WxH, pid, workspace name (last: a name may hold spaces).
# shellcheck disable=SC2016
windows_py='
import json, sys
nest = sys.argv[1]
active = (json.loads(sys.argv[3] or "{}") or {}).get("address", "")
def ours(pid):
    pid = str(pid)
    while pid not in ("", "0", "1"):
        if pid == nest:
            return True
        try:
            with open("/proc/%s/stat" % pid) as f:
                pid = f.read().rsplit(") ", 1)[1].split()[1]
        except (OSError, IndexError):
            return False
    return False
for w in json.loads(sys.argv[2]):
    if w.get("class") != "aquamarine":
        continue
    print(w["address"], "ours" if ours(w["pid"]) else "other",
          "focused" if w["address"] == active else "unfocused",
          "floating" if w["floating"] else "tiled", "%dx%d" % tuple(w["size"]),
          w["pid"], w["workspace"]["name"])
'

nest_windows() { # sandbox pid
  local clients active
  clients=$(host_hyprctl -j clients) && active=$(host_hyprctl -j activewindow) || return 1
  python3 -I -c "$windows_py" "$1" "$clients" "$active"
}

focused_address() {
  host_hyprctl -j activewindow | python3 -I -c 'import json, sys; print((json.loads(sys.stdin.read() or "{}") or {}).get("address", ""))'
}

# The monitors showing the special workspace "nest", space-separated.
special_shown() {
  host_hyprctl -j monitors | python3 -I -c '
import json, sys
print(" ".join(m["name"] for m in json.load(sys.stdin) if m["specialWorkspace"]["name"] == "special:nest"))'
}

# This nest's window, once only one is left: aquamarine maps a window for
# its first output, which the nest replaces with DP-1's.
our_window() { # sandbox pid; prints its nest_windows line
  local lines mine i
  for ((i = 0; i < 50; i++)); do
    lines=$(nest_windows "$1") || return 1
    mine=$(awk '$2 == "ours"' <<<"$lines")
    if [ -n "$mine" ] && [ "$(wc -l <<<"$mine")" = 1 ]; then
      echo "$mine"
      return 0
    fi
    sleep 0.1
  done
  echo "aquamarine windows on the host: ${lines:-none}" | tr '\n' ';' >&2
  return 1
}

# Makes sure this nest's window is on special:nest without focus, as the
# window rule puts it at map, before it can take focus. A dispatch can only
# act after the map, so when the rule missed, the window had focus from its
# map until here. Prints what it saw and did; returns 1 if it is still not
# on special:nest without focus.
place_window() { # sandbox pid, the address focused before up
  local w addr focus fl size ws
  w=$(our_window "$1") || {
    echo "could not find the nest's window among the host's windows"
    return 1
  }
  read -r addr _ focus fl size _ ws <<<"$w"
  if [ "$ws" = special:nest ] && [ "$focus" = unfocused ]; then
    echo "the window is on the special workspace 'nest', without focus ($fl, $size)"
    say_hidden
    return 0
  fi
  local was=$focus
  echo "the window rule did not apply: the window was on workspace $ws, $focus ($fl, $size)"
  host_hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = \"special:nest\", follow = false })" >/dev/null || true
  if [ "$was" = focused ] && [ -n "$2" ]; then
    host_hyprctl dispatch "hl.dsp.focus({ window = \"address:$2\" })" >/dev/null || true
  fi
  w=$(our_window "$1") || {
    echo "the nest's window is gone after moving it"
    return 1
  }
  read -r addr _ focus fl size _ ws <<<"$w"
  if [ "$ws" != special:nest ] || [ "$focus" != unfocused ]; then
    echo "moving it did not work: it is on workspace $ws, $focus"
    return 1
  fi
  echo "moved it to the special workspace 'nest', without focus ($fl, $size)"
  say_hidden
  [ "$was" = focused ] || return 0
  local now
  now=$(focused_address) || now=
  if [ -n "$2" ] && [ "$now" = "$2" ]; then
    echo "focus is back on the window that had it before up ($2)"
  else
    echo "focus is on ${now:-no window}, not on the window that had it before up (${2:-none})"
  fi
}

# A demo's nest maps a window for its first output and removes that output
# before the shell starts. Waits up to 2 s for the window to go; one still
# there is put right as any nest's.
no_window() { # sandbox pid, the address focused before up
  local lines i
  for ((i = 0; i < 20; i++)); do
    lines=$(nest_windows "$1") || {
      echo "could not read the host's windows"
      return 1
    }
    if ! awk '$2 == "ours"' <<<"$lines" | grep -q .; then
      echo "the nest has no window on the host: its only output is a headless DP-1"
      return 0
    fi
    sleep 0.1
  done
  echo "the nest's window is still on the host 2 s after its output was removed"
  place_window "$1" "$2"
}

say_hidden() {
  local shown
  if ! shown=$(special_shown); then
    echo "could not read which monitors show the special workspace 'nest'"
  elif [ -n "$shown" ]; then
    echo "the special workspace 'nest' is open on $shown: the window is on screen"
  else
    echo "no monitor shows the special workspace 'nest': the window is hidden"
  fi
}

# The host's session state into $state/<prefix>.{env,units,instances,cursor}.
# Fails rather than write a snapshot that would compare equal to anything.
snapshot() { # prefix
  local p=$state/$1 u s
  systemctl --user show-environment >"$p.env.raw" 2>/dev/null || return 1
  sort "$p.env.raw" >"$p.env"
  rm -f "$p.env.raw"
  grep -q '^WAYLAND_DISPLAY=.' "$p.env" && grep -q '^HYPRLAND_INSTANCE_SIGNATURE=.' "$p.env" || return 1
  : >"$p.units"
  for u in "${units[@]}"; do
    s=$(systemctl --user is-active "$u" 2>/dev/null || true)
    [[ $s =~ ^(active|inactive|failed|activating|deactivating|reloading)$ ]] || return 1
    printf '%s %s\n' "$u" "$s" >>"$p.units"
  done
  grep -qx 'graphical-session.target active' "$p.units" || return 1
  hyprctl instances >"$p.instances" 2>&1 || return 1
  [ -s "$p.instances" ] || return 1
  journalctl --user -n 0 --show-cursor --no-pager 2>/dev/null | sed -n 's/^-- cursor: //p' >"$p.cursor"
  [ -s "$p.cursor" ]
}

# Prints what differs between the snapshot taken at up and now. Returns 0 if
# nothing, 1 if something, 2 if the host could not be read.
host_differs() {
  local rc=0 f
  for f in env units instances cursor; do
    [ -s "$state/before.$f" ] || {
      echo "no snapshot from up in $state (before.$f): cannot compare"
      return 2
    }
  done
  snapshot now || {
    echo "could not read the host session's state now"
    return 2
  }
  for f in env units instances; do
    diff -U0 --label "at up: $f" --label "now: $f" "$state/before.$f" "$state/now.$f" || rc=1
  done
  local j
  j=$(journalctl --user --after-cursor "$(cat "$state/before.cursor")" --no-pager 2>&1) || {
    echo "could not read the user journal: $j"
    return 2
  }
  if grep -E 'graphical-session|hyprland-session|wayland-wm@|wayland-session@|quickshell\.service|Stopped target' <<<"$j"; then
    rc=1
  fi
  return $rc
}

recovery() {
  local line k
  if sandbox_pid >/dev/null 2>&1; then
    echo "Do not end the nest cleanly: its cleanup talks to the session. Instead:"
    echo "  kill -9 $(cut -d' ' -f1 "$state/supervisor")    # ends the nest with no cleanup"
  else
    # A pid recorded by a nest that has ended may be any process by now.
    echo "No nest named $name is running: these are differences from the snapshot taken at up ($(date -r "$state/before.env" '+%F %T')), and may not be a nest's doing (a new login changes them too)."
    echo "Only if a nest caused them, this puts the environment back:"
  fi
  while IFS= read -r line; do
    grep -qxF -- "$line" "$state/now.env" || printf '  systemctl --user set-environment %q\n' "$line"
  done <"$state/before.env"
  while IFS= read -r line; do
    k=${line%%=*}
    grep -q "^$k=" "$state/before.env" || printf '  systemctl --user unset-environment %q\n' "$k"
  done <"$state/now.env"
  echo "Never stop hyprland-session.target: it stops graphical-session.target and the session with it."
  echo "If the session ends anyway: log in again at tuigreet on tty1."
}

# --- the running nest -------------------------------------------------------

starttime() { # pid; field 22 of /proc/<pid>/stat
  local s
  s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  s=${s##*) }
  # shellcheck disable=SC2086
  set -- $s
  echo "${20}"
}

ppid_of() {
  local s
  s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  s=${s##*) }
  # shellcheck disable=SC2086
  set -- $s
  echo "$2"
}

lock_free() {
  [ -e "$state/lock" ] || return 0
  flock -n "$state/lock" true
}

# The sandbox's first process (host pid), only if it is provably this nest's:
# the lock is held, the supervisor and the sandbox process are alive with the
# start times recorded when they started, and the sandbox process is a child
# of bwrap, itself the supervisor's child. A pid reused after a crash fails
# the start time or the parentage.
sandbox_pid() {
  local sp ss cp cs b
  if lock_free; then
    echo "desk-nest: no nest named $name is running" >&2
    return 1
  fi
  if ! read -r sp ss 2>/dev/null <"$state/supervisor" || ! read -r cp cs 2>/dev/null <"$state/sandbox"; then
    echo "desk-nest: the nest named $name is starting or its records are missing ($state)" >&2
    return 1
  fi
  if [ "$(starttime "$sp")" != "$ss" ] || [ "$(starttime "$cp")" != "$cs" ]; then
    echo "desk-nest: the recorded processes are not the nest's (a reused pid?); refusing to touch them" >&2
    return 1
  fi
  b=$(ppid_of "$cp") && [ "$(ppid_of "$b")" = "$sp" ] || {
    echo "desk-nest: process $cp is not inside the nest's bwrap; refusing to touch it" >&2
    return 1
  }
  echo "$cp"
}

# The environment inside the sandbox, as name value pairs.
inner_vars() {
  local hc=$1
  vars=(
    HOME "$HOME" USER "${USER:-$(id -un)}" PATH "$nest/fakes/bin:$nest/services/bin:$inner_path"
    LANG "${LANG:-C.UTF-8}" TERM "${TERM:-xterm-256color}"
    XDG_DATA_DIRS "$icon_dirs" XDG_CONFIG_DIRS "${XDG_CONFIG_DIRS:-}"
    LOCALE_ARCHIVE "${LOCALE_ARCHIVE:-}" FONTCONFIG_FILE /etc/fonts/fonts.conf
    XDG_RUNTIME_DIR "$host_rt" WAYLAND_DISPLAY "$hc"
    XDG_CONFIG_HOME "$state/home/config" XDG_DATA_HOME "$state/home/data"
    XDG_CACHE_HOME "$state/home/cache" XDG_STATE_HOME "$state/home/state"
    XDG_SESSION_TYPE wayland XDG_CURRENT_DESKTOP Hyprland
    TZ "${TZ:-Europe/London}"
    HYPRLAND_NO_SD_VARS 1 HYPRLAND_NO_SD_TARGET 1 HYPRLAND_NO_SD_NOTIFY 1
    LIBSEAT_BACKEND desk-nest-none
    NEST_STATE "$state" NEST_TREE "$state/tree" NEST_FIXTURES "$nest/fixtures"
    NEST_DEMO "$(demo_clock)" NEST_PRELOAD "$faketime_preload"
    NEST_WALLPAPER "$top/assets/wallpapers/left.png"
  )
}

# Where the wall clock of a nest started with --demo starts; empty otherwise.
demo_clock() {
  cat "$state/demo" 2>/dev/null || true
}

# Sets clocked to the command prefix that runs a program on the demo clock
# (empty outside a demo): libfaketime reading the time nest-services clock
# writes, once per real second. libc_malloc_debug comes first in the preload:
# libfaketime's init mallocs, which inside jemalloc's own init (qs links
# jemalloc) calls clock_gettime back into libfaketime and deadlocks.
clock_prefix() {
  local c
  c=$(demo_clock)
  clocked=()
  [ -z "$c" ] || clocked=(env -u FAKETIME LD_PRELOAD="$faketime_preload" FAKETIME_TIMESTAMP_FILE="$state/home/runtime/demo-clock"
    FAKETIME_CACHE_DURATION=0 FAKETIME_DONT_FAKE_MONOTONIC=1)
}

# Runs a command inside the running nest, with the nested display.
inside() {
  local pid wl sig bus i envs=()
  pid=$(sandbox_pid) || exit 1
  wl=$(sed -n 's/^NESTED_WAYLAND=//p' "$state/nested.env" 2>/dev/null)
  sig=$(sed -n 's/^NESTED_SIG=//p' "$state/nested.env" 2>/dev/null)
  bus=$(sed -n 's/^NESTED_BUS=//p' "$state/nested.env" 2>/dev/null)
  [ -n "$wl" ] && [ -n "$sig" ] && [ -n "$bus" ] || die "the nested compositor is not up yet ($state/nested.env)"
  inner_vars "$wl"
  for ((i = 0; i < ${#vars[@]}; i += 2)); do envs+=("${vars[i]}=${vars[i + 1]}"); done
  # The bus is the nest's own (dbus-run-session's), reachable only through
  # the sandbox's mount and network namespaces.
  nsenter --target "$pid" --user --mount --pid --net --ipc --uts --preserve-credentials -- \
    env -i "${envs[@]}" HYPRLAND_INSTANCE_SIGNATURE="$sig" DBUS_SESSION_BUS_ADDRESS="$bus" "$@"
}

# Atomically, as the real writers replace their files.
put() { # file; content on stdin
  cat >"$1.desk-nest-new" && mv -f "$1.desk-nest-new" "$1"
}

write_components() {
  local c k ok list=()
  for c; do
    ok=0
    for k in "${components[@]}"; do [ "$c" = "$k" ] && ok=1; done
    [ $ok = 1 ] || die "no component $c; one of: ${components[*]}"
    list+=("\"$c\"")
  done
  if [ ${#list[@]} = 0 ]; then
    rm -f "$state/harness.json"
  else
    (
      IFS=,
      echo "{\"components\": [${list[*]}]}"
    ) | put "$state/harness.json"
  fi
}

# The index line for a panel and fixture: "<panel> <name> [words]".
index_line() { # panel name
  sed 's/#.*//' "$nest/fixtures/index" | awk -v p="$1" -v n="$2" '$1 == p && $2 == n { print; exit }'
}

# An index line's kind: its third field when that is place (a file the shell
# reads itself, placed on the host) or inside (an action run in the nest).
has_kind() { # index line, kind
  local p n k
  read -r p n k _ <<<"$1"
  [ "$k" = "$2" ]
}

# Prints the fixture's index line; fails, saying why, if there is none.
known_fixture() { # panel name
  local line
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] && [[ $2 =~ ^[A-Za-z0-9:.+_-]+$ ]] || die "no fixture '$1 $2'"
  line=$(index_line "$1" "$2")
  [ -n "$line" ] || die "no fixture '$1 $2' (desk-nest fixtures lists them)"
  echo "$line"
}

# Writes the panel's control file, then, for a fixture the shell reads from
# a file of its own, places that file: inside a running nest, else at the
# next up (place_all). The nest's processes can write in the private homes,
# so the host writes there only at up, after emptying them, before the nest
# starts. A fixture run inside needs the nest.
apply_fixture() { # panel name
  local line
  line=$(known_fixture "$1" "$2") || exit 1
  if has_kind "$line" inside; then
    # Notifications are sent by the fakes; any other panel's action is a
    # demo stand-in's (nest/services).
    if [ "$1" = notifications ]; then
      inside nest-notify "$2"
    else
      inside nest-services act "$1" "$2"
    fi
    return
  fi
  mkdir -p "$state/control"
  printf '%s\n' "$2" | put "$state/control/$1"
  if has_kind "$line" place && ! lock_free; then
    clock_prefix
    inside "${clocked[@]}" nest-place "$1" "$2"
  fi
}

seed() {
  local d p n line
  rm -rf "${state:?}/home"
  for d in config data cache state; do
    mkdir -p "$state/home/$d"
    # -L: some seed files are relative links into the checkout.
    [ -d "$nest/fixtures/home/$d" ] && cp -rLT "$nest/fixtures/home/$d" "$state/home/$d"
  done
  mkdir -p "$state/home/runtime/desk" "$state/control" "$state/shots"
  chmod -R u+w "$state/home"
  chmod 700 "$state/home/runtime" "$state/home/runtime/desk"
  # The first line of each panel is its default.
  while read -r p n; do
    line=$(index_line "$p" "$n")
    has_kind "$line" inside && continue
    [ -e "$state/control/$p" ] || printf '%s\n' "$n" >"$state/control/$p"
  done < <(sed 's/#.*//' "$nest/fixtures/index" | awk 'NF >= 2 && !seen[$1]++ { print $1, $2 }')
}

place_all() {
  local p line clocked
  clock_prefix
  for p in "$state"/control/*; do
    [ -f "$p" ] || continue
    line=$(index_line "${p##*/}" "$(cat "$p")")
    if [ -n "$line" ] && has_kind "$line" place; then
      NEST_STATE=$state NEST_FIXTURES=$nest/fixtures "${clocked[@]}" "$nest/fakes/bin/nest-place" "${p##*/}" "$(cat "$p")"
    fi
  done
}

# Inside the sandbox: start the nested compositor, wait for its sockets,
# replace its first output with one named as the real left monitor (the bar
# shows workspaces by monitor name), record the display and signature for
# ipc and shot, then start the shell on the harness root.
# A demo (NEST_DEMO, where its clock starts) replaces it with a headless DP-1
# instead, which draws at its own 60 Hz rather than when the host asks and
# leaves no window on the host; hides the pointer and parks it in the
# corner, so nothing is hovered; draws the wallpaper; starts the stand-in
# services (nest/services) and waits for them; and runs the shell on the
# slowed clock.
# shellcheck disable=SC2016
inner='
set -eu
exec 3>&- 9>&-
"$1" -c "$2" >"$NEST_STATE/hyprland.out" 2>&1 &
hp=$!
wl= sig=
for i in $(seq 50); do
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    case $s in *.lock) ;; *) if [ -S "$s" ]; then wl=${s##*/}; fi ;; esac
  done
  for d in "$XDG_RUNTIME_DIR"/hypr/*/; do
    if [ -S "$d.socket.sock" ]; then sig=$(basename "$d"); fi
  done
  [ -n "$wl" ] && [ -n "$sig" ] && break
  sleep 0.2
done
[ -n "$wl" ] && [ -n "$sig" ] || { echo "the nested compositor did not come up" >&2; kill $hp; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE=$sig
if [ -z "$NEST_DEMO" ]; then
  hyprctl output create wayland DP-1 >>"$NEST_STATE/hyprland.out" 2>&1
  hyprctl output remove WAYLAND-1 >>"$NEST_STATE/hyprland.out" 2>&1
else
  hyprctl output create headless DP-1 >>"$NEST_STATE/hyprland.out" 2>&1
  hyprctl output remove WAYLAND-1 >>"$NEST_STATE/hyprland.out" 2>&1
  hyprctl eval "hl.config({ cursor = { invisible = true } })" >>"$NEST_STATE/hyprland.out" 2>&1
  # DP-1 sits at 1600x0 (nest.lua): its bottom-right pixel.
  hyprctl dispatch "hl.dsp.cursor.move({ x = 3199, y = 899 })" >>"$NEST_STATE/hyprland.out" 2>&1
  mkdir -p "$XDG_CONFIG_HOME/hypr"
  printf "splash = false\nipc = false\nwallpaper {\n    monitor = DP-1\n    path = %s\n    fit_mode = cover\n}\n" \
    "$NEST_WALLPAPER" >"$XDG_CONFIG_HOME/hypr/hyprpaper.conf"
  WAYLAND_DISPLAY=$wl hyprpaper -c "$XDG_CONFIG_HOME/hypr/hyprpaper.conf" >"$NEST_STATE/services.out" 2>&1 </dev/null &
  nest-services start >>"$NEST_STATE/services.out" 2>&1 || echo "nest-services start failed" >>"$NEST_STATE/services.out"
fi
printf "NESTED_WAYLAND=%s\nNESTED_SIG=%s\nNESTED_BUS=%s\n" "$wl" "$sig" "$DBUS_SESSION_BUS_ADDRESS" >"$NEST_STATE/nested.env"
if [ -n "$NEST_DEMO" ]; then
  set -- env LD_PRELOAD="$NEST_PRELOAD" FAKETIME_TIMESTAMP_FILE="$NEST_STATE/home/runtime/demo-clock" \
    FAKETIME_CACHE_DURATION=0 FAKETIME_DONT_FAKE_MONOTONIC=1 "$3"
else
  set -- "$3"
fi
WAYLAND_DISPLAY=$wl QT_QPA_PLATFORM=wayland "$@" -p "$NEST_TREE/dev.qml" >"$NEST_STATE/qs.out" 2>&1 &
wait $hp
'

sandbox_cmd() {
  local i f
  inner_vars host-wayland
  sandbox=(
    bwrap --die-with-parent --new-session
    --unshare-pid --unshare-ipc --unshare-net --unshare-uts
    --ro-bind / /
    --dev /dev --dev-bind /dev/dri /dev/dri --proc /proc
    --tmpfs /tmp --tmpfs /run/dbus --tmpfs /run/systemd
    --tmpfs "$host_rt" --chmod 0700 "$host_rt"
    --bind "$host_rt/$host_wl" "$host_rt/host-wayland"
    --ro-bind "$nest" "$nest"
    --ro-bind "$hl/tests" "$hl/tests"
    --ro-bind "$state" "$state"
    --bind "$state/home" "$state/home"
    --bind "$state/shots" "$state/shots"
  )
  for f in "${inside_files[@]}"; do
    sandbox+=(--bind "$state/$f" "$state/$f")
  done
  sandbox+=(--bind "$state/home/runtime/desk" "$host_rt/desk")
  # A demo's invented machine (nest/services, sys-seed) over the real
  # paths the system panel and the bar read, read-only; the stand-in
  # rewrites it through the writable home. A path the host lacks is left
  # out: bwrap cannot make a mount point in /sys or /etc.
  local rel dest
  if [ -n "$(demo_clock)" ]; then
    while read -r rel dest; do
      if [ -e "$dest" ]; then sandbox+=(--ro-bind "$state/home/sys/$rel" "$dest"); fi
    done < <(python3 -I "$nest/services/services.py" sys-binds)
  fi
  sandbox+=(--clearenv)
  for ((i = 0; i < ${#vars[@]}; i += 2)); do
    sandbox+=(--setenv "${vars[i]}" "${vars[i + 1]}")
  done
  sandbox+=(--info-fd 3 dbus-run-session -- sh -c "$inner" sh "$hyprland" "$nest_lua" "$qs")
}

# Runs detached from the terminal, holding the lock (fd 9, inherited from up)
# for as long as the sandbox lives. bwrap dies with it: kill -9 of this
# process ends the nest with no cleanup.
supervise() {
  saved_checkout
  host_wl=$(cat "$state/host-wayland")
  sandbox_cmd
  # Records a crashed nest left are replaced here, before anything reads them.
  printf '%s %s\n' "$$" "$(starttime $$)" >"$state/supervisor"
  rm -f "$state/bwrap.info" "$state/sandbox"
  : >"$state/nested.env"
  exec 3>"$state/bwrap.info"
  "${sandbox[@]}" &
  local bw=$! cp="" i
  exec 3>&-
  for ((i = 0; i < 100; i++)); do
    cp=$(sed -n 's/.*"child-pid": *\([0-9][0-9]*\).*/\1/p' "$state/bwrap.info")
    [ -n "$cp" ] && break
    kill -0 "$bw" 2>/dev/null || break
    sleep 0.1
  done
  [ -n "$cp" ] && printf '%s %s\n' "$cp" "$(starttime "$cp")" >"$state/sandbox"
  local rc=0
  wait "$bw" || rc=$?
  echo "bwrap exited with $rc"
  rm -f "$state/bwrap.info" "$state/sandbox" "$state/nested.env" "$state/supervisor"
}

supervisor_alive() {
  local sp ss
  read -r sp ss 2>/dev/null <"$state/supervisor" || return 1
  [ "$(starttime "$sp")" = "$ss" ]
}

check_and_report() { # when
  local out rc=0
  out=$(host_differs) || rc=$?
  case $rc in
  0) echo "host unchanged ($1)" ;;
  2)
    echo "$out"
    echo "desk-nest: could not check the host ($1)" >&2
    ;;
  *)
    echo "$out"
    echo "HOST CHANGED ($1): the differences are above."
    recovery
    ;;
  esac
  return $rc
}

up() {
  local visible=0 watch=0 demo=0 fixtures=() comps=() f i line
  while [ $# -gt 0 ]; do
    case $1 in
    --visible) visible=1 ;;
    --watch) watch=1 ;;
    --demo) demo=1 ;;
    --fixtures)
      [ $# -ge 2 ] && [[ $2 == *=* ]] || die "--fixtures takes <panel>=<name>"
      fixtures+=("$2")
      shift
      ;;
    -*) usage ;;
    *) comps+=("$1") ;;
    esac
    shift
  done
  [ $demo = 0 ] || [ $visible = 0 ] || die "--demo leaves no window on the host to show: --visible does not go with it"
  use_checkout "$tree_arg"
  need_harness
  host_session
  need_window_rule
  mkdir -p "$state"
  case $state/ in "$top"/*) die "the state directory $state is inside the checkout" ;; esac
  exec 9>>"$state/lock"
  flock -n 9 || die "a nest named $name is already running (desk-nest --name $name status). A second one needs another name: desk-nest --name <other> up"
  printf '%s\n' "$top" >"$state/checkout"
  printf '%s\n' "$host_wl" >"$state/host-wayland"
  if [ $demo = 1 ]; then printf '%s\n' "$demo_time" >"$state/demo"; else rm -f "$state/demo"; fi
  for f in "${inside_files[@]}"; do
    rm -f "$state/$f"
    : >"$state/$f"
  done
  sync_tree
  seed
  [ $demo = 0 ] || python3 -I "$nest/services/services.py" sys-seed "$state/home/sys" ||
    die "could not write the demo's invented machine into $state/home/sys"
  # The clock's first reading, for what reads it before nest-services
  # clock runs (place_all below, the stand-ins' start).
  [ $demo = 0 ] || printf '%s\n' "$demo_time" >"$state/home/runtime/demo-clock"
  # Not apply_fixture: up holds the lock already, which it would take for a
  # running nest to place inside. place_all places them.
  for f in "${fixtures[@]}"; do
    line=$(known_fixture "${f%%=*}" "${f#*=}") || exit 1
    has_kind "$line" inside &&
      die "${f%%=*} ${f#*=} is sent to a running nest: desk-nest fixture ${f%%=*} ${f#*=}, after up"
    printf '%s\n' "${f#*=}" | put "$state/control/${f%%=*}"
  done
  place_all
  write_components "${comps[@]}"
  local before_focus
  before_focus=$(focused_address) || before_focus=
  snapshot before || die "could not read the host session's state (systemd, hyprctl instances, the journal); not starting"
  # The lock passes to the supervisor through fd 9.
  setsid -f "$0" --name "$name" _supervise </dev/null >"$state/supervisor.out" 2>&1
  exec 9>&-
  # The nest is out of the terminal's reach from here: Ctrl+C takes it down,
  # and a failed up says that it still runs and what to do.
  next="desk-nest --name $name down ends it"
  trap up_interrupted INT TERM
  trap 'up_failed $?' EXIT
  for ((i = 0; i < 300; i++)); do
    if [ -f "$state/qs.out" ] && grep -q 'Configuration Loaded' "$state/qs.out"; then break; fi
    if [ -f "$state/qs.out" ] && grep -q 'Failed to load configuration' "$state/qs.out"; then break; fi
    if [ $i -gt 20 ] && lock_free; then
      echo "desk-nest: the nest ended while starting. Its logs:" >&2
      tail -n 20 "$state/supervisor.out" "$state/hyprland.out" "$state/qs.out" 2>/dev/null >&2 || true
      check_and_report "after a failed start" || true
      exit 1
    fi
    sleep 0.1
  done
  local loaded=0 placed=1 pid shown
  grep -q 'Configuration Loaded' "$state/qs.out" 2>/dev/null && loaded=1
  # The supervisor records the sandbox's pid on its own clock.
  for ((i = 0; i < 50; i++)); do
    [ -s "$state/sandbox" ] && break
    sleep 0.1
  done
  if ! pid=$(sandbox_pid); then
    placed=0
  elif [ $demo = 1 ]; then
    no_window "$pid" "$before_focus" || placed=0
  else
    place_window "$pid" "$before_focus" || placed=0
  fi
  if [ $placed = 0 ]; then
    echo "desk-nest: the nest's window is not on the special workspace 'nest' without focus; taking the nest down" >&2
    "$0" --name "$name" down || true
    exit 1
  fi
  if [ $visible = 1 ]; then
    host_hyprctl dispatch 'hl.dsp.workspace.toggle_special("nest")' >/dev/null || true
    shown=$(special_shown) || shown=
    if [ -n "$shown" ]; then
      echo "--visible: the special workspace 'nest' is open on $shown"
    else
      echo "--visible: toggled the special workspace 'nest', but no monitor shows it"
    fi
  fi
  local rc=0
  check_and_report "the nest running" || rc=$?
  case $rc in
  0) ;;
  1)
    next="follow the recovery above"
    exit 1
    ;;
  *)
    next="desk-nest --name $name check, and down once it says host unchanged"
    exit 1
    ;;
  esac
  # A recording starts right after up, and the shell maps its bar a moment
  # after it says it loaded.
  if [ $loaded = 1 ] && [ $demo = 1 ] && { [ ${#comps[@]} = 0 ] || [[ " ${comps[*]} " == *" Bar "* ]]; }; then
    for ((i = 0; i < 100; i++)); do
      inside hyprctl -j layers 2>/dev/null | python3 -I -c '
import json, sys
levels = json.load(sys.stdin).get("DP-1", {}).get("levels", {})
sys.exit(0 if any(l.get("namespace") == "desk-bar" for ls in levels.values() for l in ls) else 1)' && break
      sleep 0.1
    done
    if [ $i -lt 100 ]; then echo "the bar is mapped on DP-1"; else echo "desk-nest: no bar on DP-1 10 s after the shell loaded" >&2; fi
  fi
  # The system item's temperatures appear with the shell's first sensor
  # snapshot, up to 5 s after it loaded; a take must not start before.
  if [ $loaded = 1 ] && [ $demo = 1 ] && { [ ${#comps[@]} = 0 ] || [[ " ${comps[*]} " == *" Bar "* ]] || [[ " ${comps[*]} " == *" System "* ]]; }; then
    local sensed=""
    for ((i = 0; i < 200; i++)); do
      sensed=$(demo_sensors) && break
      sleep 0.1
    done
    if [ $i -lt 200 ]; then
      echo "the shell reads the invented machine: $sensed"
    else
      echo "desk-nest: the shell has no CPU temperature 20 s after it loaded; it reports: ${sensed:-nothing} ($state/services.out)" >&2
      next="desk-nest --name $name down, and send $state/services.out and $state/qs.out"
      exit 1
    fi
  fi
  if [ $loaded = 1 ]; then
    echo "nest $name up: Configuration Loaded"
  else
    echo "nest $name up, but the shell did not load:"
    grep -nE 'ERROR|Failed|WARN' "$state/qs.out" 2>/dev/null | head -n 20 || echo "  (nothing in $state/qs.out after 30 s)"
  fi
  echo "  shell: $hl/user/quickshell (copied to $state/tree)"
  echo "  logs: $state/qs.out, $state/hyprland.out, $state/fakes.log"
  echo "  screenshots: desk-nest shot <name> -> $state/shots/"
  next="fix the error and desk-nest --name $name reload, or desk-nest --name $name down"
  [ $loaded = 1 ] || exit 1
  trap - INT TERM EXIT
  [ $watch = 0 ] || watch_tree
}

# up's EXIT trap once the supervisor runs.
up_failed() { # exit status
  [ "$1" = 0 ] || lock_free || echo "desk-nest: the nest named $name is still running: $next" >&2
}

# up's INT and TERM trap once the supervisor runs.
up_interrupted() {
  trap '' INT TERM
  echo "desk-nest: interrupted; taking the nest down" >&2
  local i
  # down needs the sandbox's record and the nested display.
  for ((i = 0; i < 150; i++)); do
    lock_free && break
    [ -s "$state/sandbox" ] && [ -s "$state/nested.env" ] && break
    sleep 0.1
  done
  lock_free || "$0" --name "$name" down || true
  exit 130
}

reload_shell() {
  sync_tree
  inside "$qs" ipc -p "$state/tree/dev.qml" call shell reload
}

watch_tree() {
  saved_checkout
  sandbox_pid >/dev/null || exit 1
  echo "watching $hl/user/quickshell (Ctrl+C to stop)"
  local f
  inotifywait -m -r -q -e close_write,moved_to,create,delete,move --format '%w%f' "$hl/user/quickshell" |
    while read -r f; do
      # One reload for a burst of events (an editor's save is several).
      while read -r -t 0.3 f; do :; done
      echo "$(date +%T) $(reload_shell 2>&1 | tr '\n' ' ')"
    done
}

down() {
  local pid out rc=0 i
  saved_checkout
  pid=$(sandbox_pid) || exit 1
  out=$(host_differs) || rc=$?
  if [ $rc != 0 ]; then
    echo "$out"
    if [ $rc = 1 ]; then
      echo "HOST CHANGED while the nest runs: the differences are above."
      recovery
    else
      echo "desk-nest: could not check the host; not ending the nest cleanly. To end it anyway with no cleanup: kill -9 $(cut -d' ' -f1 "$state/supervisor")" >&2
    fi
    exit 1
  fi
  # SIGTERM takes the same exit path as the nested exit bind, and works while
  # the nest is locked. Found inside the sandbox's own pid namespace, where
  # no host process is visible, by its executable.
  # shellcheck disable=SC2016
  inside sh -c 'found=
    for p in /proc/[0-9]*; do
      case $(readlink "$p/exe" 2>/dev/null) in
      "$1"/bin/Hyprland | "$1"/bin/.Hyprland-wrapped) found="$found ${p#/proc/}" ;;
      esac
    done
    set -- $found
    [ $# = 1 ] || { echo "expected one nested Hyprland, found $#: signalling none" >&2; exit 1; }
    kill -TERM "$1"' sh "$hypr_pkg" ||
    die "could not find the nested compositor; nothing else was signalled. To end the nest with no cleanup: kill -9 $(cut -d' ' -f1 "$state/supervisor")"
  for ((i = 0; i < 150; i++)); do
    lock_free && break
    sleep 0.1
  done
  local ended=1
  if lock_free; then
    echo "nest $name ended"
  else
    ended=0
    echo "desk-nest: the nest is still running 15 s after SIGTERM. End it with no cleanup: kill -9 $(cut -d' ' -f1 "$state/supervisor" 2>/dev/null)" >&2
  fi
  check_and_report "after down" || exit 1
  [ $ended = 1 ]
}

status() {
  if lock_free; then
    echo "nest $name: not running"
  elif pid=$(sandbox_pid 2>/dev/null); then
    echo "nest $name: running (sandbox pid $pid, supervisor $(cut -d' ' -f1 "$state/supervisor"))"
    local w addr focus fl size ws
    host_sig=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p') || host_sig=
    if [ -n "$(demo_clock)" ]; then
      echo "  window: none (--demo: a headless DP-1, the shell's clock from $(demo_clock), a hundredth of real speed)"
      echo "  sensors: $( (saved_checkout && demo_sensors) 2>/dev/null || true)"
    elif [ -n "$host_sig" ] && w=$(our_window "$pid" 2>/dev/null); then
      read -r addr _ focus fl size _ ws <<<"$w"
      echo "  window: workspace $ws, $focus, $fl, $size"
    else
      echo "  window: could not be read from the host session"
    fi
  else
    echo "nest $name: lock held, but its processes cannot be confirmed (starting?)"
  fi
  [ -f "$state/checkout" ] && echo "  checkout: $(cat "$state/checkout")"
  if [ -f "$state/harness.json" ]; then echo "  components: $(cat "$state/harness.json")"; else echo "  components: the default set"; fi
  local c
  for c in "$state"/control/*; do [ -f "$c" ] && echo "  fixture ${c##*/}: $(cat "$c")"; done
  echo "  state: $state"
  echo "  logs: $state/qs.out, $state/hyprland.out, $state/fakes.log"
}

# The shell's own reading of a demo's invented machine (nest/dev.qml,
# harness sensors): prints it, and fails while it has no CPU temperature.
demo_sensors() {
  local j
  j=$(inside "$qs" ipc -p "$state/tree/dev.qml" call harness sensors 2>/dev/null) || return 1
  printf '%s\n' "$j"
  python3 -I -c 'import json, sys; sys.exit(0 if (json.loads(sys.argv[1]) or {}).get("cpuTemp") is not None else 1)' "$j" 2>/dev/null
}

# The lock's stand-in in the nest, on the demo clock in a --demo nest.
start_lock() {
  local clocked
  clock_prefix
  # shellcheck disable=SC2016
  inside "${clocked[@]}" sh -c '"$1" -n -p "$2" >"$3" 2>&1 &' sh "$qs" "$state/tree/lock-nest.qml" "$state/lock.out"
}

# Plays a steps file against a running --demo nest while wf-recorder records
# its DP-1 inside, then captions it. README.md, "Recording a tour".
record() { # [--clips] steps outdir
  local clips=0
  if [ "$1" = --clips ]; then
    clips=1
    shift
  fi
  local steps=$1 out=$2 acts t0 now wait_s w t k a pid i rc=0 scenes=() stop_t='' end=''
  saved_checkout
  sandbox_pid >/dev/null || exit 1
  [ -n "$(demo_clock)" ] || die "record needs a nest started with up --demo (a headless DP-1 at 60 Hz on the slowed clock)"
  [ -f "$steps" ] || die "no steps file $steps"
  local sensed
  sensed=$(demo_sensors) || die "the shell has no CPU temperature from the invented machine (${sensed:-no answer}): not recording. desk-nest status shows what it reads."
  mkdir -p "$out"
  # Read whole first: a bad line fails before anything is recorded.
  acts=$(python3 -I "$steps_py" "$steps" "$out/captions.txt") || exit 1
  : >"$out/play.log"
  rm -f "$state/shots/record.mkv" "$state/shots/record.pid"
  # shellcheck disable=SC2016
  inside sh -c 'wf-recorder -o DP-1 -D -r 60 -c libx264rgb -x bgr0 -p crf=0 -p preset=ultrafast -m matroska -y -f "$1" >"$2" 2>&1 </dev/null &
    echo $! >"$3"' sh "$state/shots/record.mkv" "$state/shots/record.out" "$state/shots/record.pid"
  t0=$(date +%s.%N)
  pid=$(cat "$state/shots/record.pid")
  [[ $pid =~ ^[0-9]+$ ]] || die "the recorder did not start ($state/shots/record.out)"
  sleep 0.5
  inside kill -0 "$pid" 2>/dev/null || die "the recorder ended at once: $(tail -n 5 "$state/shots/record.out")"
  while IFS=$'\x1f' read -r -a w; do
    t=${w[0]}
    now=$(date +%s.%N)
    wait_s=$(awk -v a="$t0" -v b="$t" -v c="$now" 'BEGIN { printf "%.3f", a + b - c }')
    case $wait_s in -*) echo "late by ${wait_s#-} s: ${w[*]:1}" >>"$out/play.log" ;; *) sleep "$wait_s" ;; esac
    printf '%6.2f %s\n' "$(awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN { print a - b }')" "${w[*]:1}" >>"$out/play.log"
    case ${w[1]} in
    ipc) inside "$qs" ipc -p "$state/tree/dev.qml" call "${w[@]:2}" >>"$out/play.log" 2>&1 || true ;;
    fixture) (apply_fixture "${w[2]}" "${w[3]}") >>"$out/play.log" 2>&1 || true ;;
    set) (write_components "${w[@]:2}") >>"$out/play.log" 2>&1 || true ;;
    keys)
      a=()
      for k in "${w[@]:2}"; do a+=(-k "$k"); done
      inside wtype "${a[@]}" >>"$out/play.log" 2>&1 || true
      ;;
    chord) inside wtype -M "${w[2]}" -k "${w[3]}" -m "${w[2]}" >>"$out/play.log" 2>&1 || true ;;
    type) inside wtype -- "${w[*]:2}" >>"$out/play.log" 2>&1 || true ;;
    cursor)
      case ${w[2]} in
      hide) inside hyprctl eval 'hl.config({ cursor = { invisible = true } })' >>"$out/play.log" 2>&1 || true ;;
      show) inside hyprctl eval 'hl.config({ cursor = { invisible = false } })' >>"$out/play.log" 2>&1 || true ;;
      # DP-1 sits at 1600x0 (nest.lua); steps give x on DP-1.
      *) inside hyprctl dispatch "hl.dsp.cursor.move({ x = $((1600 + w[2])), y = ${w[3]} })" >>"$out/play.log" 2>&1 || true ;;
      esac
      ;;
    click)
      # wlrctl clicks through the virtual-pointer protocol where the
      # pointer is; hidden or not, it is moved there first.
      inside hyprctl dispatch "hl.dsp.cursor.move({ x = $((1600 + w[2])), y = ${w[3]} })" >>"$out/play.log" 2>&1 || true
      inside wlrctl pointer click "${w[4]:-left}" >>"$out/play.log" 2>&1 || true
      ;;
    lock) start_lock >>"$out/play.log" 2>&1 || true ;;
    scene) scenes+=("$t ${w[2]}") ;;
    stop)
      stop_t=$t
      break
      ;;
    esac
  done <<<"$acts"
  inside kill -INT "$pid" 2>/dev/null || true
  for ((i = 0; i < 100; i++)); do
    inside kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  inside kill -0 "$pid" 2>/dev/null && echo "desk-nest: the recorder is still running 10 s after it was told to stop" >&2
  cp "$state/shots/record.mkv" "$out/raw.mkv" || die "no recording ($state/shots/record.out)"
  cp "$state/shots/record.out" "$out/recorder.log"
  # "<n> <name> <start> <end>": a scene runs from its marker to the next
  # one, the last to stop; seconds of the recording, as in the steps file.
  : >"$out/scenes.txt"
  for ((i = 0; i < ${#scenes[@]}; i++)); do
    read -r t k <<<"${scenes[i]}"
    end=$stop_t
    [ $((i + 1)) = ${#scenes[@]} ] || read -r end _ <<<"${scenes[i + 1]}"
    printf '%02d %s %s %s\n' $((i + 1)) "$k" "$t" "$end" >>"$out/scenes.txt"
  done
  if [ $clips = 1 ]; then
    mkdir -p "$out/clips"
    while read -r i k t end; do
      ffmpeg -hide_banner -loglevel error -y -ss "$t" -t "$(awk -v a="$end" -v t="$t" 'BEGIN { print a - t }')" -i "$out/raw.mkv" -an \
        -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p -movflags +faststart "$out/clips/$i-$k.mp4" </dev/null || rc=1
    done <"$out/scenes.txt"
    echo "$out: raw.mkv, captions.txt, scenes.txt, clips/ ($(wc -l <"$out/scenes.txt") scenes), play.log, recorder.log"
    return $rc
  fi
  desk-nest-caption "$out/raw.mkv" "$out/captions.txt" "$out/demo.mp4" 60 || rc=$?
  echo "$out: raw.mkv, captions.txt, scenes.txt, play.log, recorder.log$([ $rc = 0 ] && echo ", demo.mp4")"
  return $rc
}

case $cmd in
up) up "$@" ;;
record)
  [ $# = 2 ] || { [ $# = 3 ] && [ "$1" = --clips ]; } || usage
  record "$@"
  ;;
_supervise)
  # Only as up starts it: holding the nest's lock on fd 9.
  if [ "$(readlink /proc/self/fd/9 2>/dev/null)" != "$(realpath -m "$state/lock")" ] || ! flock -n 9; then
    die "_supervise is started by desk-nest up only"
  fi
  supervise
  ;;
set)
  saved_checkout
  write_components "$@"
  echo "components: ${*:-the default set}"
  ;;
fixtures)
  if [ -f "$state/checkout" ]; then saved_checkout; else use_checkout "$tree_arg"; fi
  need_harness
  cat "$nest/fixtures/index"
  ;;
fixture)
  [ $# = 2 ] || usage
  if [ -f "$state/checkout" ]; then saved_checkout; else use_checkout "$tree_arg"; fi
  need_harness
  mkdir -p "$state"
  apply_fixture "$1" "$2"
  echo "$1: $2"
  ;;
ipc)
  saved_checkout
  inside "$qs" ipc -p "$state/tree/dev.qml" "$@"
  ;;
shot)
  shot=${1:-$(date +%Y%m%d-%H%M%S)}
  [[ $shot =~ ^[A-Za-z0-9_-]+$ ]] || die "a shot name is letters, digits, _ and -"
  saved_checkout
  mkdir -p "$state/shots"
  rc=0
  # A nest that has stopped drawing never answers a screencopy.
  inside timeout 10 grim "$state/shots/$shot.png" || rc=$?
  [ $rc = 124 ] && die "no frame within 10 s: the nest is not drawing"
  [ $rc = 0 ] || exit $rc
  echo "$state/shots/$shot.png"
  ;;
reload)
  saved_checkout
  reload_shell
  ;;
watch) watch_tree ;;
lock)
  saved_checkout
  start_lock
  echo "started the lock screen in the nest (whether it came up: $state/lock.out); only the word nest-unlock opens it. Never type a password."
  ;;
status) status ;;
check)
  saved_checkout
  check_and_report "check"
  ;;
down) down ;;
*) usage ;;
esac
