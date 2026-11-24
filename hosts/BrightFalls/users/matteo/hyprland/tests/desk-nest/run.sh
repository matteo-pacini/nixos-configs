#!/usr/bin/env bash
# Tests for ../../desk-nest.sh against fake bwrap, systemctl, hyprctl,
# journalctl, nsenter, grim and qs, run with errexit, nounset and pipefail as
# writeShellApplication runs it. Nothing here starts a compositor.
# Usage: run.sh <desk-nest.sh> <nest/hypr/nest.lua> <nest/pam/check.sh>
#   <user/hypr/rules.lua> <lua>
#   (needs bash, coreutils, git, rsync, util-linux, gawk, diffutils,
#   findutils, grep, sed and python3 with google-re2 on PATH)
#
# The fakes share $FAKE: `env` is the user manager's environment, `units`
# one "<unit> <state>" per line, `instances` hyprctl's answer, `journal` the
# user journal after the snapshot's cursor; `nobus` makes systemctl fail as
# from a detached terminal; `bwrap-fail` makes the sandbox end at once.
# Every call is logged to $FAKE/log.
#
# The host's windows: the owner's terminal 0x1000 and another nested
# compositor's window 0x2000 (pid 1, so not the nest's) always, and one per
# running fake nest, `win.<pid>` = "<workspace> <floating> <w> <h>",
# address the pid in hex. `active` is the focused address. `rule` is how
# the window rule behaves: applies (the nest maps on special:nest without
# focus), missing (on workspace 6, tiled, focused), stuck (missing, and
# dispatches change nothing) or nowindow (the nest maps no window).
# `special` is the special workspace open on DP-1.
#
# The fake bwrap stands in for the sandbox: it writes the info fd's
# child-pid, the nested display's records and the shell's "Configuration
# Loaded", and its child is a copy of bash named as the nested Hyprland's
# executable, so the process `down` must find and signal is a real one.
set -euo pipefail

script=$(realpath "$1")
nest_lua=$(realpath "$2")
check_sh=$(realpath "$3")
rules_lua=$(realpath "$4")
lua=$5
work=$(mktemp -d)
pids=()
cleanup() {
  local p
  for p in "${pids[@]}"; do kill -9 "$p" 2>/dev/null || true; done
  pkill -9 -f "$work/" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
[ -z "${KEEP:-}" ] || trap - EXIT

export FAKE=$work/fake
bin=$work/bin
mkdir -p "$FAKE" "$bin"
# Paths with spaces throughout: the checkout, the state and the runtime dir.
hl_pkg="$work/hyprland pkg"
mkdir -p "$hl_pkg/bin" "$work/decoy/bin"
# Copies of bash, not of sleep: coreutils may be one program that picks
# its tool by name.
cp "$BASH" "$hl_pkg/bin/.Hyprland-wrapped"
cp "$BASH" "$work/decoy/bin/.Hyprland-wrapped"
idle='while :; do sleep 1; done'
export HOME="$work/home dir" XDG_STATE_HOME="$work/state dir" XDG_RUNTIME_DIR="$work/run time"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
python3 -I -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$XDG_RUNTIME_DIR/wayland-1"
# Present in the caller's environment, and never to reach the sandbox.
export DBUS_SESSION_BUS_ADDRESS=unix:path=/nowhere NOTIFY_SOCKET=/nowhere MANAGERPID=1 \
  HYPRLAND_INSTANCE_SIGNATURE=host-sig WAYLAND_DISPLAY=wayland-1

pam="$work/pam dir"
mkdir -p "$pam"
echo 'auth requisite pam_deny.so' >"$pam/desk-lock"

# Inside the "sandbox" (the fake nsenter runs the command here), the fakes
# first, then the tools this test was given.
inner=$bin:$PATH
dn=$work/desk-nest
{
  echo "#!$BASH"
  echo 'set -o errexit -o nounset -o pipefail'
  printf 'hyprland=%q\n' "$hl_pkg/bin/Hyprland"
  printf 'qs=%q\n' "$bin/qs"
  printf 'nest_lua=%q\n' "$nest_lua"
  printf 'nest_pam=%q\n' "$pam"
  printf 'inner_path=%q\n' "$inner"
  cat "$script"
} >"$dn"
chmod +x "$dn"

fake() { # name, body
  {
    echo "#!$BASH"
    echo 'set -euo pipefail'
    echo 'printf "%s\n" "$(basename "$0") $*" >>"$FAKE/log"'
    echo "$2"
  } >"$bin/$1"
  chmod +x "$bin/$1"
}
fake systemctl '
[ ! -e "$FAKE/nobus" ] || { echo "Failed to connect to user scope bus via local transport: No medium found" >&2; exit 1; }
case "$1 $2" in
"--user show-environment") cat "$FAKE/env" ;;
"--user is-active")
  s=$(awk -v u="$3" "\$1 == u { print \$2 }" "$FAKE/units")
  echo "${s:-inactive}"
  [ "$s" = active ] ;;
*) exit 9 ;;
esac'
fake hyprctl '
addr() { printf "0x%x" "$1"; }
window() { # address class pid floating w h workspace
  printf ", {\"address\": \"%s\", \"class\": \"%s\", \"pid\": %s, \"floating\": %s, \"size\": [%s, %s], \"workspace\": {\"name\": \"%s\"}}" "$@"
}
case "$1 ${2:-}" in
"instances ") cat "$FAKE/instances" ;;
"-j clients")
  printf "[{\"address\": \"0x1000\", \"class\": \"foot\", \"pid\": 1, \"floating\": false, \"size\": [800, 600], \"workspace\": {\"name\": \"6\"}}"
  window 0x2000 aquamarine 1 false 800 600 3
  for f in "$FAKE"/win.*; do
    [ -f "$f" ] && kill -0 "${f##*.}" 2>/dev/null || continue
    read -r ws fl w h <"$f"
    window "$(addr "${f##*.}")" aquamarine "${f##*.}" "$fl" "$w" "$h" "$ws"
  done
  echo "]" ;;
"-j activewindow")
  a=$(cat "$FAKE/active")
  if [ -n "$a" ]; then printf "{\"address\": \"%s\"}\n" "$a"; else echo "{}"; fi ;;
"-j monitors")
  printf "[{\"name\": \"DP-1\", \"specialWorkspace\": {\"name\": \"%s\"}}, {\"name\": \"DP-2\", \"specialWorkspace\": {\"name\": \"\"}}]\n" "$(cat "$FAKE/special")" ;;
"dispatch "*)
  [ "$(cat "$FAKE/rule")" != stuck ] || exit 0
  case $2 in
  "hl.dsp.workspace.toggle_special(\"nest\")")
    if [ "$(cat "$FAKE/special")" = special:nest ]; then : >"$FAKE/special"; else echo special:nest >"$FAKE/special"; fi ;;
  "hl.dsp.window.move({ window = \"address:"*"\", workspace = \"special:nest\", follow = false })")
    a=${2#*address:}
    a=${a%%\"*}
    for f in "$FAKE"/win.*; do
      [ -f "$f" ] && [ "$(addr "${f##*.}")" = "$a" ] || continue
      read -r ws rest <"$f"
      echo "special:nest $rest" >"$f"
      [ "$(cat "$FAKE/active")" != "$a" ] || : >"$FAKE/active"
    done ;;
  "hl.dsp.focus({ window = \"address:"*"\" })")
    a=${2#*address:}
    echo "${a%%\"*}" >"$FAKE/active" ;;
  *) exit 9 ;;
  esac ;;
*) exit 9 ;;
esac'
fake journalctl '
case "$*" in
"--user -n 0 --show-cursor --no-pager") echo "-- cursor: s=fake" ;;
"--user --after-cursor s=fake --no-pager") cat "$FAKE/journal" ;;
*) exit 9 ;;
esac'
fake nsenter '
want="--target $(cut -d" " -f1 "$FAKE/expect-target" 2>/dev/null) --user --mount --pid --net --ipc --uts --preserve-credentials --"
[ "${*:1:10}" = "$want" ] || { echo "nsenter: unexpected arguments" >&2; exit 9; }
shift 10
# The command is env -i, the environment of the nest, then the command;
# the fakes run inside still need $FAKE.
[ "$1 $2" = "env -i" ] || exit 9
shift 2
exec env -i FAKE="$FAKE" "$@"'
fake grim 'echo png >"$1"'
fake qs '
case "$*" in
ipc*" call shell reload") echo reloaded ;;
ipc*) echo "ipc answered" ;;
esac'
fake bwrap '
printf "%s\n" "$@" >"$FAKE/bwrap.args.$$"
mv "$FAKE/bwrap.args.$$" "$FAKE/bwrap.args"
exec 9>&-
state=
fd=
while [ $# -gt 0 ]; do
  case $1 in
  --info-fd) fd=$2; shift ;;
  --setenv) [ "$2" = NEST_STATE ] && state=$3; shift 2 ;;
  esac
  shift
done
[ ! -e "$FAKE/bwrap-fail" ] || { echo "bwrap: fake failure" >&2; exit 1; }
"$HYPR_EXE" -c "while :; do sleep 1; done" &
child=$!
echo "$child" >"$FAKE/expect-target"
case $(cat "$FAKE/rule") in
applies) echo "special:nest true 1600 900" >"$FAKE/win.$child" ;;
missing | stuck)
  echo "6 false 1264 1380" >"$FAKE/win.$child"
  printf "0x%x\n" "$child" >"$FAKE/active" ;;
esac
printf "{\n    \"child-pid\": %s\n}\n" "$child" >&"$fd"
eval "exec $fd>&-"
printf "NESTED_WAYLAND=wayland-1\nNESTED_SIG=nested-sig\n" >"$state/nested.env"
echo "  INFO: Configuration Loaded" >"$state/qs.out"
wait $child || true'
export HYPR_EXE=$hl_pkg/bin/.Hyprland-wrapped
export PATH="$bin:$PATH"

# A checkout of the shell with the harness, at a path with a space.
co="$work/check out"
hl=$co/hosts/BrightFalls/users/matteo/hyprland
mkdir -p "$hl/user/quickshell/common" "$hl/tests/x" "$hl/nest/fakes/bin" "$hl/nest/fixtures/home/config/desk"
echo 'ShellRoot {}' >"$hl/user/quickshell/shell.qml"
echo 'Item {}' >"$hl/user/quickshell/common/Style.qml"
printf 'PamContext {\n        config: root.pamService\n}\n' >"$hl/user/quickshell/lock.qml"
echo '// harness root' >"$hl/nest/dev.qml"
echo '{}' >"$hl/user/theme.json"
ln -s ../../../../../user/theme.json "$hl/nest/fixtures/home/config/desk/theme.json"
cat >"$hl/nest/fixtures/index" <<'EOF'
# panel name words
weather 01-rain-dusk+07-warnings the default, not placed nor inside
weather 02-snow-night
calendar fixture place
calendar none place
notifications sample inside
EOF
for f in nest-place nest-notify; do
  {
    echo "#!$BASH"
    echo 'printf "%s\n" "$(basename "$0") $* NEST_STATE=${NEST_STATE:-}" >>"$FAKE/log"'
  } >"$hl/nest/fakes/bin/$f"
  chmod +x "$hl/nest/fakes/bin/$f"
done
git -C "$co" init -q
listing() { find "$co" -path "$co/.git" -prune -o -print | sort; }
listing >"$work/co.before"

state="$XDG_STATE_HOME/desk-nest/nest"
healthy() {
  printf '%s\n' "HOME=/home/someone" "WAYLAND_DISPLAY=wayland-1" "HYPRLAND_INSTANCE_SIGNATURE=host-sig" >"$FAKE/env"
  printf '%s\n' "graphical-session.target active" "wayland-wm@hyprland.desktop.service active" \
    "wayland-session@hyprland.desktop.target active" "hyprland-session.target active" \
    "quickshell.service active" >"$FAKE/units"
  echo "instance host-sig: pid 100" >"$FAKE/instances"
  : >"$FAKE/journal"
  echo applies >"$FAKE/rule"
  echo 0x1000 >"$FAKE/active"
  : >"$FAKE/special"
  rm -f "$FAKE/nobus" "$FAKE/bwrap-fail"
}
healthy

failed=0
check() { # name expected actual
  if [ "$2" == "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/     /' || true
    failed=1
  fi
}
contains() { # name needle haystack
  if [[ $3 == *"$2"* ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: no '$2' in:"
    printf '%s\n' "$3" | sed 's/^/     /'
    failed=1
  fi
}
nest() { # output (stdout and stderr) in $out, status in $rc
  rc=0
  out=$(cd "$co" && "$dn" "$@" 2>&1) || rc=$?
}
calls() { grep -c "^$1 " "$FAKE/log" || true; }
# Whether the bwrap arguments hold this sequence, consecutively.
has_args() {
  python3 -I -c '
import sys
a = open(sys.argv[1]).read().split("\n")[:-1]
s = sys.argv[2:]
sys.exit(0 if any(a[i:i + len(s)] == s for i in range(len(a))) else 1)' "$FAKE/bwrap.args" "$@"
}
running() { [ -e "$state/lock" ] && ! flock -n "$state/lock" true; }
wait_down() { for _ in $(seq 100); do running || return 0; sleep 0.1; done; }

# --- refusals before anything starts ---------------------------------------

touch "$FAKE/nobus"
nest up
check "detached terminal: refused" 1 "$rc"
contains "detached terminal: says why" "a detached terminal" "$out"
healthy

sed -i '/^WAYLAND_DISPLAY=/d' "$FAKE/env"
nest up
check "no Wayland session: refused" "1 desk-nest: no Wayland session: the user environment has no WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE" "$rc $out"
healthy
sed -i 's/^wayland-wm@hyprland.desktop.service active/wayland-wm@hyprland.desktop.service inactive/' "$FAKE/units"
nest up
check "Hyprland session not active: refused" "1 desk-nest: the Hyprland session (wayland-wm@hyprland.desktop.service) is not active" "$rc $out"
healthy

mkdir -p "$work/plain"
rc=0
out=$(cd "$work/plain" && "$dn" up 2>&1) || rc=$?
contains "outside a checkout: refused" "is not inside a git checkout" "$rc $out"
git -C "$work/plain" init -q
rc=0
out=$(cd "$work/plain" && "$dn" up 2>&1) || rc=$?
contains "another repository: refused" "is not a checkout of the BrightFalls shell" "$rc $out"

mv "$hl/nest/dev.qml" "$work/dev.qml"
nest up
contains "harness missing: refused" "the harness is missing from $co: no $hl/nest/dev.qml" "$rc $out"
mv "$work/dev.qml" "$hl/nest/dev.qml"

: >"$FAKE/instances"
nest up
check "no hyprctl instances: no snapshot, no start" "1 0" "$rc $(calls bwrap)"
contains "no hyprctl instances: says why" "could not read the host session's state" "$out"
healthy

nest up Weathr
check "unknown component: refused before start" "1 0" "$rc $(calls bwrap)"
nest up --fixtures notifications=sample
check "inside fixture at up: refused before start" "1 0" "$rc $(calls bwrap)"
nest up --fixtures weather=nope
contains "unknown fixture at up: refused" "no fixture 'weather nope'" "$out"
check "unknown fixture at up: no start" 0 "$(calls bwrap)"

# --- a failed start ---------------------------------------------------------

touch "$FAKE/bwrap-fail"
nest up
check "sandbox ends at once: reported, rc 1" 1 "$rc"
contains "sandbox ends at once: says so" "the nest ended while starting" "$out"
check "sandbox ends at once: lock released" no "$(running && echo yes || echo no)"
healthy

# --- up -----------------------------------------------------------------------

: >"$FAKE/log"
nest up Bar Weather
check "up: rc" 0 "$rc"
contains "up: loaded" "nest nest up: Configuration Loaded" "$out"
contains "up: host checked" "host unchanged (the nest running)" "$out"
check "up: not shown without --visible" 0 "$(grep -c '^hyprctl dispatch' "$FAKE/log" || true)"
contains "up: the window read from the host, on special:nest and unfocused" \
  "the window is on the special workspace 'nest', without focus (floating, 1600x900)" "$out"
contains "up: no monitor shows it" "no monitor shows the special workspace 'nest': the window is hidden" "$out"
read -r sup _ <"$state/supervisor"
read -r child _ <"$state/sandbox"
echo "$child" >"$FAKE/expect-target"

# The seal, exactly.
seal() {
  if has_args "$@"; then echo "ok   seal: $*"; else
    echo "FAIL seal: $* missing"
    failed=1
  fi
}
for a in --die-with-parent --new-session --unshare-pid --unshare-ipc --unshare-net --unshare-uts --clearenv; do
  seal "$a"
done
seal --ro-bind / /
seal --dev /dev
seal --dev-bind /dev/dri /dev/dri
seal --proc /proc
seal --tmpfs /tmp
seal --tmpfs /run/dbus
seal --tmpfs /run/systemd
seal --tmpfs "$XDG_RUNTIME_DIR"
seal --chmod 0700 "$XDG_RUNTIME_DIR"
seal --bind "$XDG_RUNTIME_DIR/wayland-1" "$XDG_RUNTIME_DIR/host-wayland"
seal --ro-bind "$hl/nest" "$hl/nest"
seal --ro-bind "$hl/tests" "$hl/tests"
seal --bind "$state" "$state"
seal --ro-bind "$state/tree" "$state/tree"
seal --bind "$state/home/runtime/desk" "$XDG_RUNTIME_DIR/desk"
seal --setenv HYPRLAND_NO_SD_VARS 1
seal --setenv HYPRLAND_NO_SD_TARGET 1
seal --setenv HYPRLAND_NO_SD_NOTIFY 1
seal --setenv LIBSEAT_BACKEND desk-nest-none
seal --setenv FONTCONFIG_FILE /etc/fonts/fonts.conf
seal --setenv WAYLAND_DISPLAY host-wayland
seal --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
seal --setenv XDG_CONFIG_HOME "$state/home/config"
seal --setenv NEST_STATE "$state"
seal --setenv NEST_TREE "$state/tree"
seal --setenv NEST_FIXTURES "$hl/nest/fixtures"
seal --setenv PATH "$hl/nest/fakes/bin:$inner"
seal --info-fd 3 dbus-run-session -- sh -c
names=$(awk 'prev == "--setenv" { print } { prev = $0 }' "$FAKE/bwrap.args" | sort | paste -sd' ')
check "seal: only these variables inside" \
  "FONTCONFIG_FILE HOME HYPRLAND_NO_SD_NOTIFY HYPRLAND_NO_SD_TARGET HYPRLAND_NO_SD_VARS LANG LIBSEAT_BACKEND LOCALE_ARCHIVE NEST_FIXTURES NEST_STATE NEST_TREE PATH TERM TZ USER WAYLAND_DISPLAY XDG_CACHE_HOME XDG_CONFIG_DIRS XDG_CONFIG_HOME XDG_CURRENT_DESKTOP XDG_DATA_DIRS XDG_DATA_HOME XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_STATE_HOME" \
  "$names"
check "seal: no bind is writable but the state, the socket and the runtime desk dir" \
  "--bind --bind --bind" "$(grep -xE -- '--(bind|dev-bind|bind-try|rw-bind)' "$FAKE/bwrap.args" | grep -vx -- --dev-bind | paste -sd' ')"
check "seal: nothing shares a namespace back" "" "$(grep -xE -- '--share-net|--userns|--userns2|--pidns' "$FAKE/bwrap.args" || true)"
check "seal: the compositor's config turns XWayland and the popups off" 3 \
  "$(grep -cE 'xwayland = \{ enabled = false \}|no_update_news = true|disable_hyprland_guiutils_check = true' "$nest_lua")"

# The shown tree: a copy with the harness root and the lock stand-in; the
# checkout itself gains nothing.
check "tree: harness root copied in" "// harness root" "$(cat "$state/tree/dev.qml")"
check "tree: lock with one line more" '>         configDirectory: "pam"' \
  "$(diff "$state/tree/lock.qml" "$state/tree/lock-nest.qml" | grep '^>')"
check "tree: stand-in PAM stack" "auth requisite pam_deny.so" "$(cat "$state/tree/pam/desk-lock")"
listing >"$work/co.after"
check "tree: the checkout gained no file" "" "$(diff "$work/co.before" "$work/co.after" || true)"
check "seed: fixture home copied, links followed" "{} no" \
  "$(cat "$state/home/config/desk/theme.json") $([ -L "$state/home/config/desk/theme.json" ] && echo yes || echo no)"
check "seed: each panel's default, none for an inside line" "calendar=fixture weather=01-rain-dusk+07-warnings" \
  "$(cd "$state/control" && for f in *; do printf '%s=%s ' "$f" "$(cat "$f")"; done | sed 's/ $//')"
contains "seed: the place panel's file placed" "nest-place calendar fixture NEST_STATE=$state" "$(cat "$FAKE/log")"
check "components written" '{"components": ["Bar","Weather"]}' "$(cat "$state/harness.json")"

# --- one nest per name --------------------------------------------------------

: >"$FAKE/log"
nest up
check "second nest: refused" 1 "$rc"
contains "second nest: says how" "desk-nest --name <other> up" "$out"
check "second nest: no sandbox started" 0 "$(calls bwrap)"
check "second nest: the first is untouched" "$sup" "$(cut -d' ' -f1 "$state/supervisor")"

# --- commands against the running nest -----------------------------------------

: >"$FAKE/log"
nest set Bogus
check "set: unknown component refused" 1 "$rc"
nest set Bar System
check "set: written" '0 {"components": ["Bar","System"]}' "$rc $(cat "$state/harness.json")"
nest set
check "set: none named is the default set" "0 gone" "$rc $([ -e "$state/harness.json" ] && echo there || echo gone)"

nest fixture weather 02-snow-night
check "fixture: switched" "0 02-snow-night" "$rc $(cat "$state/control/weather")"
nest fixture weather 99-none
check "fixture: one not in the index refused" "1 02-snow-night" "$rc $(cat "$state/control/weather")"
nest fixture 'weather;' x
check "fixture: a malformed panel refused" 1 "$rc"
nest fixture calendar none
check "fixture: a place fixture placed on the host" "nest-place calendar none NEST_STATE=$state" "$(grep '^nest-place' "$FAKE/log")"
nest fixture notifications sample
check "fixture: an inside fixture runs inside" "0 nest-notify sample NEST_STATE=$state" "$rc $(grep '^nest-notify' "$FAKE/log")"
check "fixture: an inside fixture writes no control" no "$([ -e "$state/control/notifications" ] && echo yes || echo no)"
nest fixtures
contains "fixtures: the index" "weather 02-snow-night" "$out"

: >"$FAKE/log"
nest ipc show
check "ipc: through nsenter into the sandbox, to the harness root" "0 ipc answered" "$rc $out"
check "ipc: qs run with the nested display" "qs ipc -p $state/tree/dev.qml show" "$(grep '^qs ' "$FAKE/log")"
nest reload
check "reload: answered" "0 reloaded" "$rc $out"
echo 'Item { id: x }' >"$hl/user/quickshell/common/Style.qml"
nest reload
check "reload: copies the checkout first" "Item { id: x }" "$(cat "$state/tree/common/Style.qml")"
check "reload: keeps the harness root" "// harness root" "$(cat "$state/tree/dev.qml")"

nest shot 'bad name'
check "shot: a bad name refused" 1 "$rc"
nest shot first
check "shot: prints the path" "0 $state/shots/first.png" "$rc $out"
check "shot: written" png "$(cat "$state/shots/first.png")"

: >"$FAKE/log"
nest lock
for _ in $(seq 50); do grep -q '^qs ' "$FAKE/log" && break; sleep 0.1; done
check "lock: the stand-in lock started inside" "qs -n -p $state/tree/lock-nest.qml" "$(grep '^qs ' "$FAKE/log")"
contains "lock: names the word, warns off passwords" "only the word nest-unlock opens it. Never type a password" "$out"

nest status
contains "status: running" "nest nest: running (sandbox pid $child" "$out"
contains "status: where the window is" "window: workspace special:nest, unfocused, floating, 1600x900" "$out"

# --- a reused pid is never touched ----------------------------------------------

cp "$state/sandbox" "$work/sandbox.real"
sleep 1000 &
stranger=$!
pids+=("$stranger")
start=$(awk '{ sub(/.*\) /, ""); print $20 }' "/proc/$stranger/stat")
printf '%s %s\n' "$stranger" "$start" >"$state/sandbox"
echo "$stranger" >"$FAKE/expect-target"
: >"$FAKE/log"
nest ipc show
check "reused pid, right start time, not the nest's child: refused" "1 0" "$rc $(calls nsenter)"
contains "reused pid: says why" "is not inside the nest's bwrap" "$out"
printf '%s %s\n' "$child" 1 >"$state/sandbox"
echo "$child" >"$FAKE/expect-target"
nest shot x
check "the nest's pid with another start time: refused" "1 0" "$rc $(calls nsenter)"
nest down
check "down with a doubtful pid: nothing signalled" "1 0 alive" \
  "$rc $(calls nsenter) $(kill -0 "$child" 2>/dev/null && echo alive || echo gone)"
cp "$work/sandbox.real" "$state/sandbox"

# --- the host check -----------------------------------------------------------

nest check
check "check: unchanged" "0 host unchanged (check)" "$rc $out"

echo "WAYLAND_DISPLAY=wayland-9" >>"$FAKE/env"
sed -i '/^WAYLAND_DISPLAY=wayland-1$/d' "$FAKE/env"
echo "NESTED_LEAK=1" >>"$FAKE/env"
nest check
check "env changed: rc 1" 1 "$rc"
contains "env changed: the line" "+WAYLAND_DISPLAY=wayland-9" "$out"
contains "env changed: recovery restores it" "systemctl --user set-environment WAYLAND_DISPLAY=wayland-1" "$out"
contains "env changed: recovery unsets the new one" "systemctl --user unset-environment NESTED_LEAK" "$out"
contains "env changed: recovery is kill -9 of the supervisor" "kill -9 $sup" "$out"
: >"$FAKE/log"
nest down
check "down with the env changed: refused, nothing signalled" "1 0 alive" \
  "$rc $(calls nsenter) $(kill -0 "$child" 2>/dev/null && echo alive || echo gone)"
contains "down with the env changed: says not to exit cleanly" "Do not end the nest cleanly" "$out"
healthy

sed -i 's/^quickshell.service active/quickshell.service inactive/' "$FAKE/units"
nest check
contains "unit changed: named" "+quickshell.service inactive" "$rc $out"
healthy
echo "instance nested-sig: pid 200" >>"$FAKE/instances"
nest check
contains "instances changed: named" "+instance nested-sig: pid 200" "$rc $out"
healthy
echo "Nov 24 10:00:00 host systemd[1]: Stopped target Graphical Interface." >"$FAKE/journal"
nest check
check "journal: a stopped target is a change" 1 "$rc"
contains "journal: the line shown" "Stopped target Graphical Interface." "$out"
healthy

cp "$state/before.units" "$work/units.real"
: >"$state/before.units"
nest check
check "empty snapshot: not 'unchanged'" 2 "$rc"
contains "empty snapshot: says it cannot compare" "cannot compare" "$out"
nest down
check "down with no snapshot: refused, nothing signalled" "1 alive" "$rc $(kill -0 "$child" 2>/dev/null && echo alive || echo gone)"
cp "$work/units.real" "$state/before.units"

# --- down -----------------------------------------------------------------------

"$work/decoy/bin/.Hyprland-wrapped" -c "$idle" &
decoy=$!
pids+=("$decoy")
: >"$FAKE/log"
nest down
check "down: rc" 0 "$rc"
contains "down: host checked after" "host unchanged (after down)" "$out"
contains "down: says it ended" "nest nest ended" "$out"
wait_down
check "down: the nested compositor ended, the lock is free" "gone no" \
  "$(kill -0 "$child" 2>/dev/null && echo alive || echo gone) $(running && echo yes || echo no)"
check "down: another Hyprland executable untouched" alive "$(kill -0 "$decoy" 2>/dev/null && echo alive || echo gone)"
check "down: no records left" "" "$(cd "$state" && ls bwrap.info sandbox supervisor nested.env 2>/dev/null || true)"
nest ipc show
check "after down: ipc says nothing runs" "1 desk-nest: no nest named nest is running" "$rc $out"

# --- a crash: the supervisor killed, records left behind ------------------------

nest --name two up --visible
check "a second name runs" 0 "$rc"
check "--visible shows the special workspace" 'hyprctl dispatch hl.dsp.workspace.toggle_special("nest")' \
  "$(grep '^hyprctl dispatch' "$FAKE/log")"
check "--visible: reads that it is shown, and where" "--visible: the special workspace 'nest' is open on DP-1" "$(grep -- '^--visible' <<<"$out")"
contains "--visible: the window was hidden and unfocused first" \
  "the window is on the special workspace 'nest', without focus" "$out"
state2="$XDG_STATE_HOME/desk-nest/two"
read -r sup2 _ <"$state2/supervisor"
read -r child2 _ <"$state2/sandbox"
bw2=$(awk '{ sub(/.*\) /, ""); print $2 }' "/proc/$child2/stat")
kill -9 "$sup2"
# bwrap's --die-with-parent, which the fake does not do.
kill -9 "$bw2" "$child2"
for _ in $(seq 50); do kill -0 "$child2" 2>/dev/null || break; sleep 0.1; done
check "crash: records left behind" "nested.env sandbox supervisor" "$(cd "$state2" && ls nested.env sandbox supervisor 2>/dev/null | paste -sd' ')"
: >"$FAKE/log"
nest --name two shot y
check "crash: stale records are not a running nest" "1 0" "$rc $(calls nsenter)"
nest --name two up
check "crash: up again starts" 0 "$rc"
check "crash: the records are the new nest's" "no no" \
  "$([ "$(cut -d' ' -f1 "$state2/supervisor")" = "$sup2" ] && echo yes || echo no) $([ "$(cut -d' ' -f1 "$state2/sandbox")" = "$child2" ] && echo yes || echo no)"
echo "$(cut -d' ' -f1 "$state2/sandbox")" >"$FAKE/expect-target"
nest --name two down
check "crash: down after" 0 "$rc"

# --- the window rule missed: the window is put right, or the nest taken down -------

healthy
echo missing >"$FAKE/rule"
: >"$FAKE/log"
nest up
check "rule missed: up succeeds" 0 "$rc"
contains "rule missed: says where the window was" \
  "the window rule did not apply: the window was on workspace 6, focused (tiled, 1264x1380)" "$out"
contains "rule missed: says it moved it" "moved it to the special workspace 'nest', without focus (tiled, 1264x1380)" "$out"
contains "rule missed: hidden" "no monitor shows the special workspace 'nest': the window is hidden" "$out"
contains "rule missed: says focus went back" "focus is back on the window that had it before up (0x1000)" "$out"
check "rule missed: the host's focus is back" 0x1000 "$(cat "$FAKE/active")"
win=$(printf '0x%x' "$(cut -d' ' -f1 "$state/sandbox")")
check "rule missed: moved by its address, silently" \
  "hyprctl dispatch hl.dsp.window.move({ window = \"address:$win\", workspace = \"special:nest\", follow = false })" \
  "$(grep '^hyprctl dispatch' "$FAKE/log" | grep -F 'window.move')"
check "rule missed: the other aquamarine window untouched" 0 "$(grep -c 'address:0x2000' "$FAKE/log" || true)"
nest status
contains "rule missed: status after" "window: workspace special:nest, unfocused, tiled, 1264x1380" "$out"
nest down
check "rule missed: down" 0 "$rc"

healthy
echo special:nest >"$FAKE/special"
nest up
contains "special workspace already open: says the window is on screen" \
  "the special workspace 'nest' is open on DP-1: the window is on screen" "$out"
nest down

healthy
echo stuck >"$FAKE/rule"
nest up
check "cannot be put right: up fails" 1 "$rc"
contains "cannot be put right: says what it saw" "moving it did not work: it is on workspace 6, focused" "$out"
contains "cannot be put right: says it takes the nest down" "taking the nest down" "$out"
contains "cannot be put right: down ran" "nest nest ended" "$out"
contains "cannot be put right: the host checked" "host unchanged (after down)" "$out"
check "cannot be put right: nothing left running" no "$(running && echo yes || echo no)"

healthy
echo nowindow >"$FAKE/rule"
nest up
check "no window found: up fails" 1 "$rc"
contains "no window found: says so" "could not find the nest's window among the host's windows" "$out"
contains "no window found: lists what it saw" "aquamarine windows on the host: 0x2000 other" "$out"
contains "no window found: taken down" "nest nest ended" "$out"
check "no window found: nothing left running" no "$(running && echo yes || echo no)"
healthy

# --- the window rule, matched as Hyprland matches it --------------------------------

# Hyprland 0.57 matches each pattern against the whole string, with RE2's
# FullMatch (src/desktop/rule/matchEngine/RegexMatchEngine.cpp); the same
# library here. The values are those aquamarine's Wayland backend sets
# (src/backend/Wayland.cpp: app id "aquamarine", title "aquamarine - <output>")
# for the nest's first output and the one it is replaced with.
cat >"$work/rules.lua" <<'LUA'
local found
hl = {
  window_rule = function(r) if r.name == "desk-nest" then found = r end end,
  layer_rule = function() end,
}
dofile(arg[1])
assert(found, "no window rule named desk-nest")
for k, v in pairs(found.match) do print("match", k, v) end
print("workspace=" .. tostring(found.workspace))
print("no_initial_focus=" .. tostring(found.no_initial_focus))
LUA
rule=$("$lua" "$work/rules.lua" "$rules_lua")
matched=$(grep '^match' <<<"$rule" | python3 -I -c '
import re2, sys
values = {"class": ["aquamarine"], "initial_class": ["aquamarine"],
          "title": ["aquamarine - DP-1", "aquamarine - WAYLAND-1"],
          "initial_title": ["aquamarine - DP-1", "aquamarine - WAYLAND-1"]}
for line in sys.stdin:
    _, key, pattern = line.rstrip("\n").split("\t", 2)
    negative = pattern.startswith("negative:")
    if negative:
        pattern = pattern[len("negative:"):]
    for v in values.get(key, [None]):
        if v is None:
            print("%s: not a key this test knows" % key)
        elif (re2.fullmatch(pattern, v) is None) != negative:
            print("%s %r does not match %r" % (key, pattern, v))
')
check "rule: a match key" yes "$(grep -q '^match' <<<"$rule" && echo yes || echo no)"
check "rule: every pattern matches the nest's window" "" "$matched"
check "rule: the workspace desk-nest checks for" "workspace=special:nest silent" "$(grep '^workspace=' <<<"$rule")"
check "rule: no focus at map" "no_initial_focus=true" "$(grep '^no_initial_focus=' <<<"$rule")"

# --- the stand-in PAM check -----------------------------------------------------

pw() { printf '%s' "$1" | bash "$check_sh" && echo accept || echo reject; }
check "pam check: the fixture word" accept "$(pw nest-unlock)"
check "pam check: anything else" "reject reject reject" "$(pw wrong) $(pw '') $(pw 'nest-unlock
')"

exit "$failed"
