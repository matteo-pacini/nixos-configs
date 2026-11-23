#!/usr/bin/env bash
# The tunes-helper check: desk-tunes' pure functions, then the service built
# with testing = true against fakes (test-desk-tunes.py says which).
# Usage: run.sh <desk-tunes built for testing> <desk-tunes.py>
#               <genres.json> <config json> <work dir>
# Needs python3, ffmpeg (with ffprobe), mpv, dbus-daemon and playerctl on
# PATH, and MPV_MPRIS set to the path of mpv's mpris.so.
set -euo pipefail
here=$(dirname "$(realpath "$0")")
: "${MPV_MPRIS:?MPV_MPRIS must name mpris.so}"
mkdir -p "$5"
exec python3 -I "$here/test-desk-tunes.py" "$(realpath "$1")" "$(realpath "$2")" \
  "$(realpath "$3")" "$(realpath "$4")" "$(realpath "$5")"
