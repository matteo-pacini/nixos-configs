#!/usr/bin/env bash
# Tests for ../../desk-unlock.sh, the recovery from a text console when the
# lock screen dies, against fake hyprctl, systemctl and pkill, run with
# errexit, nounset and pipefail as writeShellApplication runs it.
# Usage: run.sh <desk-unlock.sh>   (needs bash, coreutils and grep on PATH)
#
# The fakes share $FAKE: `locked` holds Hyprland's answer, `refuse` the
# number of clear_crashed_lockscreen calls still to be refused, `procs` one
# command line per running process (pkill -f matches it as procps does, an
# extended regular expression against the whole line). Every call is
# logged to $FAKE/log.
set -euo pipefail

script=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export FAKE=$work/fake
bin=$work/bin
mkdir -p "$FAKE" "$bin"

fake() { # name, body
  {
    echo "#!$BASH"
    echo 'set -euo pipefail'
    echo 'echo "$(basename "$0") $*" >>"$FAKE/log"'
    echo "$2"
  } >"$bin/$1"
  chmod +x "$bin/$1"
}
fake hyprctl '
[ -e "$FAKE/running" ] || { echo "Couldnt connect to /run/user/1000/hypr/. (3)"; exit 3; }
[ "$1 $2" = "--instance 0" ] || exit 9
case "$3" in
locked) cat "$FAKE/locked" ;;
eval)
  [ "$4" = "hl.clear_crashed_lockscreen()" ] || exit 9
  n=$(cat "$FAKE/refuse")
  if [ "$n" -gt 0 ]; then
    echo $((n - 1)) >"$FAKE/refuse"
    echo "refusing: the lock client is still alive"
  else
    echo false >"$FAKE/locked"
    echo ok
  fi
  ;;
*) exit 9 ;;
esac'
fake systemctl '
case "$*" in
"--user stop desk-lock")
  [ -e "$FAKE/unit" ] || { echo "Failed to stop desk-lock.service: Unit desk-lock.service not loaded."; exit 5; }
  # A hung client ignores the stop (and its SIGTERM).
  [ -e "$FAKE/hung" ] || { rm "$FAKE/unit"; : >"$FAKE/procs.lock"; } ;;
"--user kill -s KILL desk-lock")
  [ -e "$FAKE/unit" ] || { echo "Failed to kill unit desk-lock.service: Unit desk-lock.service not loaded."; exit 5; }
  [ -e "$FAKE/unkillable" ] || { rm "$FAKE/unit"; echo 0 >"$FAKE/refuse"; } ;;
*) exit 9 ;;
esac'
fake pkill '
[ "$1 $2" = "-KILL -f" ] || exit 9
if grep -E -- "$3" "$FAKE/procs" >"$FAKE/killed"; then
  echo 0 >"$FAKE/refuse"
else
  exit 1
fi'
fake sleep ''
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
unlock() { # output (stdout and stderr) in $out, status in $rc
  rc=0
  out=$(bash -euo pipefail "$script" 2>&1) || rc=$?
}
setup() { # flags to touch...
  rm -rf "${FAKE:?}"/*
  echo true >"$FAKE/locked"
  echo 0 >"$FAKE/refuse"
  : >"$FAKE/log"
  printf '%s\n' \
    "/nix/store/00000000000000000000000000000000-quickshell-0.3.2/bin/quickshell" \
    "/nix/store/00000000000000000000000000000000-quickshell-0.3.2/bin/quickshell -n -p /home/someone/.config/quickshell/lock.qml" \
    "nvim /home/someone/.config/quickshell/lock.qml" \
    "/nix/store/00000000000000000000000000000000-quickshell-0.3.2/bin/quickshell -p /home/someone/.config/quickshell/shell.qml" \
    >"$FAKE/procs"
  local f
  for f in running "$@"; do touch "$FAKE/$f"; done
}
last_line="If that says false: type exit, then press Ctrl+Alt+F1."

# The lock client crashed: no unit left, Hyprland clears the lock.
setup
unlock
check "crashed lock: cleared at the first try" "0 Hyprland says locked: true
Failed to stop desk-lock.service: Unit desk-lock.service not loaded.
unlock: ok
Hyprland says locked: false
$last_line" "$rc $out"

# The lock process is alive but stuck; stopping its unit is enough.
setup unit
unlock
check "stuck lock, stops: cleared" "0 unlock: ok|Hyprland says locked: false" \
  "$rc $(grep -E '^(unlock|Hyprland says locked: false)' <<<"$out" | paste -sd'|')"
check "stuck lock, stops: no kill" "" "$(grep -E 'kill' "$FAKE/log" || true)"

# The unit ignores the stop: refused, then killed, then cleared.
setup unit hung
echo 1 >"$FAKE/refuse"
unlock
check "hung lock: refused, killed, cleared on the second try" "0 Hyprland says locked: true
unlock: refusing: the lock client is still alive
unlock, second try: ok
Hyprland says locked: false
$last_line" "$rc $out"
check "hung lock: the unit is killed with SIGKILL first" "systemctl --user kill -s KILL desk-lock" \
  "$(grep -m1 kill "$FAKE/log")"

# The unit cannot be killed (the client was started some other way): pkill
# by command line, which must match the lock alone.
setup unit hung unkillable
echo 1 >"$FAKE/refuse"
unlock
check "lock outside its unit: cleared after pkill" "0 unlock, second try: ok" \
  "$rc $(grep '^unlock, second try' <<<"$out")"
check "pkill matches only the lock process" \
  "/nix/store/00000000000000000000000000000000-quickshell-0.3.2/bin/quickshell -n -p /home/someone/.config/quickshell/lock.qml" \
  "$(cat "$FAKE/killed")"

# Nothing frees it: the second answer is shown, and the user is not told
# it worked.
setup unit hung unkillable
echo 5 >"$FAKE/refuse"
: >"$FAKE/procs"
unlock
check "still refused: reported, still locked, exits 0" "0 unlock, second try: refusing: the lock client is still alive|Hyprland says locked: true" \
  "$rc $(grep -E '^(unlock, second try|Hyprland says locked)' <<<"$out" | tail -2 | paste -sd'|')"

# No Hyprland on instance 0: every step still runs and reports.
setup
rm "$FAKE/running"
unlock
check "no Hyprland: reports and exits 0" "0 Hyprland says locked: Couldnt connect to /run/user/1000/hypr/. (3)
Failed to stop desk-lock.service: Unit desk-lock.service not loaded.
unlock: Couldnt connect to /run/user/1000/hypr/. (3)
Hyprland says locked: Couldnt connect to /run/user/1000/hypr/. (3)
$last_line" "$rc $out"

exit "$failed"
