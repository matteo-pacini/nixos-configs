#!/usr/bin/env bash
# Every command the shell can start is a desk-nest fake or stub, or harmless
# by ./allowlist; nest/dev.qml loads shell.qml's components
# (test-nest-commands.js says how commands are found). Then the same on
# copies with one fault planted each, which must fail naming it.
# Usage: run.sh <quickshell dir> <nest dir>   (needs node and coreutils)
set -euo pipefail

here=$(dirname "$(realpath "$0")")
qs=$(realpath "$1")
nest=$(realpath "$2")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0
node "$here/test-nest-commands.js" "$qs" "$nest" "$here/allowlist" || failed=1

n=0
plant() { # name, pattern, path in the copy (qs/… or nest/…), sed script or "rm"
  local dir=$work/plant$((n += 1)) out rc=0
  mkdir -p "$dir"
  cp -r "$qs" "$dir/qs"
  cp -r "$nest" "$dir/nest"
  chmod -R u+w "$dir"
  if [ "$4" = rm ]; then
    rm "$dir/$3"
  else
    sed -i "$4" "$dir/$3"
    if diff -rq --no-dereference "$qs" "$dir/qs" >/dev/null && diff -rq --no-dereference "$nest" "$dir/nest" >/dev/null; then
      echo "FAIL $1: the plant changed nothing"
      failed=1
      return
    fi
  fi
  out=$(node "$here/test-nest-commands.js" "$dir/qs" "$dir/nest" "$here/allowlist") || rc=$?
  if [ "$rc" != 0 ] && grep -qE -- "$2" <<<"$out"; then
    echo "ok   $1: $(grep -m1 -E -- "$2" <<<"$out")"
  else
    echo "FAIL $1 (exit $rc), expected /$2/ in:"
    sed 's/^/     /' <<<"$out"
    failed=1
  fi
}
plant "a new command in a Process" '^FAIL curl \(Cheatsheet.qml' qs/Cheatsheet.qml 's/command: \["hyprctl", "-j", "binds"\]/command: ["curl", "-j", "binds"]/'
plant "a new command in execDetached" '^FAIL firefox \(Bar.qml' qs/Bar.qml 's/execDetached(\["audio-output-cycle"\])/execDetached(["firefox"])/'
plant "a new command in a ternary arm" '^FAIL desk-mqtt-rw \(office/OfficeShared.qml' qs/office/OfficeShared.qml 's/: \["desk-mqtt"\]/: ["desk-mqtt-rw"]/'
plant "a new command in a sh -c script" '^FAIL curl \(Network.qml:[0-9]+ \(sh -c\)' qs/Network.qml 's/echo @route; ip -j/echo @route; curl -s x; ip -j/'
plant "a new command in a script property" '^FAIL sensors \(system/Sensors.qml' qs/system/Sensors.qml 's/do printf .freq/do sensors; printf '"'"'freq/'
plant "a new command from notify.js" '^FAIL notify-sender \(common/notify.js' qs/common/notify.js 's/return \["gdbus", "call"/return ["notify-sender", "call"/'
plant "a non-literal command site" 'Launcher.qml:[0-9]+: command from "cmd" is not a literal' qs/Launcher.qml 's/execDetached(command)/execDetached(cmd)/'
plant "a dispatch that execs" 'Bar.qml:[0-9]+: a Hyprland dispatch runs a command' qs/Bar.qml 's/hl\.dsp\.focus(/hl.dsp.exec_cmd(/'
plant "a fake removed from bin" '^FAIL nmcli \(Network.qml' nest/fakes/bin/nmcli rm
plant "a component missing from dev.qml" "dev.qml's loaders" nest/dev.qml '/root\.want("Weather")/,+1d'
plant "a component added to shell.qml" "is not shell.qml's components" qs/shell.qml 's/^    Weather {}$/    Weather {}\n    Clock {}/'

exit "$failed"
