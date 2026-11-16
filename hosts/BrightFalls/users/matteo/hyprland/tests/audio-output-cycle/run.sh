#!/usr/bin/env bash
# Tests for audio-output-cycle (../../../audio-output-cycle.nix, Super+Shift+O)
# built against fake pw-dump, wpctl and notify-send. The fakes read $FAKE:
# `sinks` holds "<id> <node.name> <description>" lines (the Audio/Sink nodes
# pw-dump lists), `default` the default sink's node.name; wpctl set-default
# and notify-send log to $FAKE/log, and notify-send prints the id 7.
# Usage: run.sh <audio-output-cycle>   (needs bash, coreutils, grep, jq)
set -euo pipefail

cycle=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export FAKE=$work/fake XDG_RUNTIME_DIR=$work/run
mkdir -p "$FAKE" "$XDG_RUNTIME_DIR"

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
stereo=alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo
atmos=effect_input.virtual-surround-atmos
dtshx=effect_input.virtual-surround-dtshx
setup() { # default node.name, then sink lines
  rm -rf "${FAKE:?}"/* "$XDG_RUNTIME_DIR"/*
  echo "$1" >"$FAKE/default"
  shift
  printf '%s\n' "$@" >"$FAKE/sinks"
  : >"$FAKE/log"
}
run() { # output in $out, status in $rc
  rc=0
  out=$("$cycle" 2>&1) || rc=$?
}
all=("41 $stereo Test DAC" "52 $atmos Test surround A" "53 $dtshx Test surround B"
  "60 alsa_output.pci-0000_00_1f.3.hdmi-stereo Test HDMI")

setup "$stereo" "${all[@]}"
run
check "stereo -> the first surround sink" "0 wpctl set-default 52
notify-send --transient --app-name=Sound --icon=audio-headphones --replace-id=0 --print-id Audio output Test surround A" \
  "$rc $(cat "$FAKE/log")"
check "the notification's id is kept" 7 "$(cat "$XDG_RUNTIME_DIR/audio-output-cycle.id")"

echo "$atmos" >"$FAKE/default"
: >"$FAKE/log"
run
check "surround A -> surround B, replacing the last notification" "wpctl set-default 53
notify-send --transient --app-name=Sound --icon=audio-headphones --replace-id=7 --print-id Audio output Test surround B" \
  "$(cat "$FAKE/log")"

setup "$dtshx" "${all[@]}"
run
check "the last one wraps to stereo" "wpctl set-default 41" "$(head -1 "$FAKE/log")"

setup alsa_output.pci-0000_00_1f.3.hdmi-stereo "${all[@]}"
run
check "a default outside the cycle -> stereo" "wpctl set-default 41" "$(head -1 "$FAKE/log")"

setup "$stereo" "41 $stereo Test DAC" "53 $dtshx Test surround B"
run
check "a missing surround sink is skipped" "wpctl set-default 53" "$(head -1 "$FAKE/log")"

setup "$stereo" "41 $stereo Test DAC"
run
check "only stereo: set again, no error" "0 wpctl set-default 41" "$rc $(head -1 "$FAKE/log")"

setup alsa_output.pci-0000_00_1f.3.hdmi-stereo "52 $atmos Test surround A" \
  "60 alsa_output.pci-0000_00_1f.3.hdmi-stereo Test HDMI"
run
check "no DAC: says so, changes nothing" "0 notify-send --transient --app-name=Sound --icon=audio-headphones --replace-id=0 --print-id Audio output Modi 2 isn't connected" \
  "$rc $(cat "$FAKE/log")"

exit "$failed"
