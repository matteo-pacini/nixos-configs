#!/usr/bin/env bash
# Tests for hosts/BrightFalls/display-layout.sh (single-monitor and the
# restore behind Super+Shift+D) against a fake hyprctl, run with errexit,
# nounset and pipefail as writeShellApplication runs it.
# Usage: run.sh <display-layout.sh> <monitors.lua>
#   (needs bash, coreutils, jq, grep and sed on PATH)
#
# The fake keeps the active monitors in $fake/monitors, one
# "<name> <workspace> <focused>" line each, applies hl.monitor rules from
# `eval` at once, logs every call to $fake/log, and does on `reload` what
# $fake/reload says: "good" (monitors.lua: DP-1 and DP-2) or "noop" (a
# config that does not parse).
set -euo pipefail

script=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fake=$work/fake
bin=$work/bin
mkdir -p "$fake" "$bin" "$work/run"
export XDG_RUNTIME_DIR=$work/run FAKE=$fake
state=$XDG_RUNTIME_DIR/display-layout/single.json

{
  echo "#!$BASH"
  cat <<'EOF'
set -euo pipefail
[ "$1" = --instance ] && [ "$2" = 0 ] || { echo "fake hyprctl: no --instance 0" >&2; exit 9; }
shift 2
[ -e "$FAKE/running" ] || { echo "HYPRLAND_INSTANCE_SIGNATURE not set" >&2; exit 1; }
case "$1" in
version) echo "Hyprland 0.57.2" ;;
-j)
  [ "$2" = monitors ] || exit 9
  first=1
  printf '['
  while read -r name ws focused; do
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"name":"%s","focused":%s,"activeWorkspace":{"id":%s,"name":"%s"}}' \
      "$name" "$focused" "$ws" "$ws"
  done <"$FAKE/monitors"
  printf ']\n'
  ;;
eval)
  printf 'eval %s\n' "$2" >>"$FAKE/log"
  if [ -e "$FAKE/eval-error" ]; then
    cat "$FAKE/eval-error"
    exit 0
  fi
  if [ ! -e "$FAKE/frozen" ]; then
    grep -o 'output = "[^"]*", disabled = [a-z]*' <<<"$2" |
      sed 's/output = "\([^"]*\)", disabled = \(.*\)/\1 \2/' |
      while read -r out disabled; do
        grep -v "^$out " "$FAKE/monitors" >"$FAKE/m.tmp" || true
        if [ "$disabled" = false ]; then
          ws=1
          [ "$out" = DP-2 ] && ws=6
          echo "$out $ws false" >>"$FAKE/m.tmp"
        fi
        mv "$FAKE/m.tmp" "$FAKE/monitors"
      done
  fi
  echo ok
  ;;
reload)
  echo reload >>"$FAKE/log"
  if [ "$(cat "$FAKE/reload")" = good ] && [ ! -e "$FAKE/frozen" ]; then
    grep -E '^DP-1 ' "$FAKE/monitors" >"$FAKE/m.tmp" || echo "DP-1 1 true" >"$FAKE/m.tmp"
    grep -q '^DP-2 ' "$FAKE/monitors" && grep -E '^DP-2 ' "$FAKE/monitors" >>"$FAKE/m.tmp" ||
      echo "DP-2 6 false" >>"$FAKE/m.tmp"
    mv "$FAKE/m.tmp" "$FAKE/monitors"
  fi
  echo ok
  ;;
*) echo "fake hyprctl: unexpected $*" >&2; exit 9 ;;
esac
EOF
} >"$bin/hyprctl"
# wait_until polls with sleep 0.5 for up to 10 s; the fake changes nothing
# between polls, so the waits need not be real.
realsleep=$(command -v sleep)
printf '#!%s\n' "$BASH" >"$bin/sleep"
chmod +x "$bin/hyprctl" "$bin/sleep"
export PATH="$bin:$PATH"

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
dl() { # args...; output (stdout and stderr) in $out, status in $rc
  rc=0
  out=$(bash -euo pipefail "$script" "$@" 2>&1) || rc=$?
}
setup() { # running|stopped, reload behaviour, monitor lines...
  rm -rf "${fake:?}"/* "$XDG_RUNTIME_DIR/display-layout"
  [ "$1" = running ] && touch "$fake/running"
  echo "$2" >"$fake/reload"
  shift 2
  printf '%s\n' "$@" >"$fake/monitors"
  : >"$fake/log"
}
monitors() { sort "$fake/monitors" | cut -d' ' -f1 | tr '\n' ' '; }
log() { cat "$fake/log"; }
present() { [ -e "$1" ] && echo present || echo absent; }

dp1='hl.monitor({ output = "DP-1", disabled = false, mode = "2560x1440@144", position = "0x0", scale = 1 })'
dp2='hl.monitor({ output = "DP-2", disabled = false, mode = "2560x1440@60", position = "2560x0", scale = 1 })'

# ---- usage ----
setup running good "DP-1 3 true" "DP-2 7 false"
dl
check "no command: usage, 2" "2 usage: display-layout single CMD... | restore" "$rc $out"
dl frobnicate
check "unknown command: usage, 2" 2 "$rc"
dl single
check "single without a command: usage, 2" 2 "$rc"
check "usage touches nothing" "" "$(log)"

# ---- the monitors' rules match monitors.lua ----
lua=$2
for o in DP-1 DP-2; do
  want=$(grep -o "hl.monitor({ output = \"$o\", mode = [^)]*)" "$lua" | sed 's/, mode/, disabled = false, mode/')
  got=$(grep -o "hl.monitor({ output = \"$o\", disabled = false, [^)]*)" "$script")
  check "$o rule as in monitors.lua" "$want" "$got"
done

# ---- restore ----
setup stopped good
dl restore
check "restore without Hyprland: 1" "1 display-layout: no Hyprland session" "$rc $out"

setup running good "DP-1 3 true" "DP-2 7 false"
dl restore
check "restore when normal: nothing done" "0  " "$rc $out $(log)"

setup running good "DP-1 3 true"
dl restore
check "restore with DP-2 off: exits 0" "0 " "$rc $out"
check "restore with DP-2 off: rules, then reload" "eval $dp1 $dp2 hl.notification.create({ text = \"Restoring monitors\", duration = 2000 })
reload" "$(log)"
check "restore with DP-2 off: both back" "DP-1 DP-2 " "$(monitors)"

setup running good "DP-1 3 true" "DP-2 7 false" "HDMI-A-1 9 false"
dl restore
check "the capture card on counts as not normal" "0 DP-1 DP-2 " "$rc $(monitors)"

# A reload that cannot parse leaves the capture card on; the rules are then
# set directly, HDMI-A-1 off included.
setup running noop "DP-1 3 true" "HDMI-A-1 9 false"
dl restore
check "broken reload: falls back to direct rules, exits 0" "0 " "$rc $out"
check "broken reload: second eval disables HDMI-A-1" \
  "eval $dp1 $dp2 hl.monitor({ output = \"HDMI-A-1\", disabled = true }) hl.notification.create({ text = \"Config reload failed: monitors set directly\", duration = 2000 })" \
  "$(sed -n 3p "$fake/log")"
check "broken reload: normal layout" "DP-1 DP-2 " "$(monitors)"

# Nothing applies (frozen): reports, exits 1, keeps the saved layout so a
# later restore still knows what to put back.
setup running noop "DP-1 3 true"
mkdir -p "${state%/*}"
echo '[]' >"$state"
touch "$fake/frozen"
dl restore
check "monitors never come back: 1 with a message" \
  "1 display-layout: DP-1 and DP-2 did not come back" "$rc $out"
check "monitors never come back: state kept" present "$(present "$state")"

setup running good "DP-1 3 true" "DP-2 7 false"
echo 'lua: attempt to call a nil value' >"$fake/eval-error"
mkdir -p "${state%/*}"
echo '[]' >"$state"
dl restore
check "an eval error is reported, not taken for ok" \
  "display-layout: hyprctl eval: lua: attempt to call a nil value" "$(head -1 <<<"$out")"

# ---- single ----
setup running good "DP-1 3 true" "DP-2 7 false"
probe=$work/probe
dl single bash -c 'echo "$*" >"$0"; cut -d" " -f1 "$FAKE/monitors" | tr "\n" " " >>"$0"; exit 3' "$probe" "a b" c
check "single: the command's status comes through" 3 "$rc"
check "single: the command gets its arguments, with DP-2 off" "a b c
DP-1 " "$(cat "$probe")"
check "single: DP-2 off, then restored on exit, workspaces back focused last" \
  "eval hl.monitor({ output = \"DP-2\", disabled = true }) hl.notification.create({ text = \"single-monitor: DP-2 off\", duration = 2000 })
eval $dp1 $dp2 hl.notification.create({ text = \"Restoring monitors\", duration = 2000 })
reload
eval hl.dispatch(hl.dsp.focus({ workspace = 7 }))
eval hl.dispatch(hl.dsp.focus({ workspace = 3 }))" "$(log)"
check "single: both monitors back" "DP-1 DP-2 " "$(monitors)"
check "single: state removed" absent "$(present "$state")"

# A special workspace (negative id) is not refocused.
setup running good "DP-1 -98 true" "DP-2 7 false"
dl single true
check "single: special workspace skipped" "eval hl.dispatch(hl.dsp.focus({ workspace = 7 }))" \
  "$(grep focus "$fake/log")"

# Another single-monitor owns the layout: run the command, change nothing.
setup running good "DP-1 3 true"
mkdir -p "${state%/*}"
echo '[{"name":"DP-1","focused":true,"activeWorkspace":{"id":3}}]' >"$state"
dl single bash -c 'echo inner; exit 4'
check "nested single: command runs, status kept, nothing touched" "4 inner " "$rc $out $(log)"
check "nested single: the outer one's state is left" present "$(present "$state")"

setup stopped good
dl single bash -c 'echo plain'
check "single without Hyprland: just runs the command" "0 plain" "$rc $out"
check "single without Hyprland: no state" absent "$(present "$state")"

# The command killed: restore still runs.
setup running good "DP-1 3 true" "DP-2 7 false"
dl single bash -c 'kill -TERM $$'
check "single: command killed, monitors restored" "DP-1 DP-2 " "$(monitors)"
check "single: command killed, state removed" absent "$(present "$state")"

# single-monitor itself terminated with its game (as a process group is, by
# a launcher or a logout): the trap still restores.
setup running good "DP-1 3 true" "DP-2 7 false"
bash -euo pipefail "$script" single bash -c 'echo $$ >"$0"; exec "$1" 30' "$work/child" "$realsleep" \
  >"$work/killed.out" 2>&1 &
pid=$!
for _ in $(seq 100); do [ -s "$work/child" ] && break; "$realsleep" 0.05; done
kill -TERM "$pid" "$(cat "$work/child")"
rc=0
wait "$pid" || rc=$?
check "single terminated: exits 143, monitors restored" "143 DP-1 DP-2 " "$rc $(monitors)"
check "single terminated: state removed" absent "$(present "$state")"

exit "$failed"
