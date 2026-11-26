#!/usr/bin/env bash
# Tests for ../../desk-reload.sh against a fake `qs`, run with errexit,
# nounset and pipefail as writeShellApplication runs it.
# Usage: run.sh <desk-reload.sh>   (needs bash and coreutils on PATH)
set -euo pipefail

script=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cfg=$work/config/quickshell

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
realtimeout=$(command -v timeout)
# Bounded, so a script that waits on a hung qs fails here (status 124)
# rather than hanging the check.
dr() { # args...; output (stdout and stderr) in $out, status in $rc
  rc=0
  out=$("$realtimeout" 30 bash -euo pipefail "$script" "$@" 2>&1) || rc=$?
}

# A stand-in for Quickshell's `qs`: logs its arguments to $work/qs.log. It
# hangs, saying nothing, when $work/qs-hang exists, and fails with qs's
# message when $work/qs-down exists. While $work/qs-refuse
# holds a number above 0 it counts it down and refuses the call as a shell in
# the middle of a reload does: the message on stderr, exit status 0.
# Otherwise it answers as shell.qml's reload() does.
mkdir -p "$work/bin"
cat >"$work/bin/qs" <<EOF
#!$BASH
echo "qs \$*" >>"$work/qs.log"
if [ -e "$work/qs-hang" ]; then
  # exec, and no pipe kept open: timeout's signal ends the call itself.
  exec sleep 60 >/dev/null 2>&1
fi
if [ -e "$work/qs-down" ]; then
  echo 'No running instances for "x"'
  echo 'second line'
  exit 255
fi
refuse=\$(cat "$work/qs-refuse" 2>/dev/null || echo 0)
if [ "\$refuse" -gt 0 ]; then
  echo \$((refuse - 1)) >"$work/qs-refuse"
  echo 'Not ready to accept queries yet.' >&2
  exit 0
fi
echo reloaded
EOF
chmod +x "$work/bin/qs"
# desk-reload's 10 s limit cut to 1 s, so the hang case is quick.
cat >"$work/bin/timeout" <<EOF
#!$BASH
shift
exec $realtimeout 1 "\$@"
EOF
chmod +x "$work/bin/timeout"
export PATH="$work/bin:$PATH"
qslog() { # the log since the last call, then emptied
  cat "$work/qs.log" 2>/dev/null || true
  rm -f "$work/qs.log"
}
calls() { grep -c '^qs ' "$work/qs.log" || true; }

dr
check "no argument: usage, exit 2, qs not called" "2 usage: desk-reload <quickshell-config-dir> " "$rc $out $(qslog)"

dr "$cfg"
check "answered at once: one call, the exact argv" "0 desk-reload: quickshell: reloaded
qs ipc --any-display -p $cfg call shell reload" "$rc $out
$(qslog)"

touch "$work/qs-down"
dr "$cfg"
rm "$work/qs-down"
check "no shell: said after one call, exit 0" "0 desk-reload: quickshell: not reloaded: No running instances for \"x\" second line  1" \
  "$rc $out $(calls)"
qslog >/dev/null

touch "$work/qs-hang"
dr "$cfg"
rm "$work/qs-hang"
check "hung shell: cut off by the timeout after one call, said, exit 0" \
  "0 desk-reload: quickshell: not reloaded:   1" "$rc $out $(calls)"
qslog >/dev/null

# A shell busy with a reload of its own refuses the call and qs still exits
# 0: asked again until the reload answers.
echo 2 >"$work/qs-refuse"
dr "$cfg"
check "refused twice, exit 0: asked again, reloaded on the third call" "0 desk-reload: quickshell: reloaded 3" \
  "$rc $out $(calls)"
qslog >/dev/null

echo 99 >"$work/qs-refuse"
dr "$cfg"
check "refused throughout: not reloaded after 20 calls, exit 0" \
  "0 desk-reload: quickshell: not reloaded: Not ready to accept queries yet.  20" "$rc $out $(calls)"
rm "$work/qs-refuse"
qslog >/dev/null

exit "$failed"
