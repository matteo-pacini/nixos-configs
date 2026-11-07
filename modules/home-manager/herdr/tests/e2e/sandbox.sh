#!/usr/bin/env bash
# An isolated herdr-app and herdr-core for driving mods end to end: its own
# hc session (here and on each machine added), its own app home, on a virtual
# X display. The person's window, terminals and spaces are never touched.
#
#   sandbox.sh up <mods dir> <layout.json> [machine...]
#   . /run/user/$UID/herdr-e2e/env      # then herdr-app/hc/xdotool talk to the sandbox
#   sandbox.sh down [machine...]        # the same machines as `up`
#
# <mods dir>: built mods, e.g. the herdr-mods store path in a home-manager
# generation's `activate` (they carry lib/hosts.js). <layout.json>: the built
# workbench layout from the same file.
#
# After `. env`: `herdr-app do <command>`, `herdr-app status`, `herdr-app shot
# <png>`; `click X Y [button]` clicks at window coordinates as a shot shows
# them (button 3: right-click). See ../../AGENTS.md › Testing.
set -euo pipefail

# Under /run/user: hc's and herdr-app's sockets live in these folders, and a
# socket path is limited to 107 bytes.
root="/run/user/$(id -u)/herdr-e2e"
session=herdr-e2e
display=:99
here=$(cd "$(dirname "$0")" && pwd)

env_file() {
  cat <<EOF
export HC_SESSION=$session XDG_RUNTIME_DIR=$root XDG_STATE_HOME=$root/state XDG_DATA_HOME=$root/data XDG_CACHE_HOME=$root/cache
export HERDR_APP_HOME=$root/app DISPLAY=$display
unset WAYLAND_DISPLAY
XDO=$(nix build --no-link --print-out-paths nixpkgs#xdotool)/bin/xdotool
click() { local g; g=\$(\$XDO search --name Herdr | head -n1); eval "\$(\$XDO getwindowgeometry --shell "\$g")"; \$XDO mousemove \$((X + \$1)) \$((Y + \$2)) sleep 0.3 click "\${3:-1}"; }
EOF
}

up() {
  local mods=$1 layout=$2
  shift 2
  [ ! -e "$root" ] || { echo "already up: $root (sandbox.sh down first)" >&2; exit 1; }
  mkdir -p "$root"/{app/layouts,app/mods,app/themes,state,data,cache}
  chmod 700 "$root"
  env_file >"$root/env"
  # shellcheck source=/dev/null
  . "$root/env"
  hc server start >/dev/null
  for m in "$@"; do hc machine add "$m" --session "$session" --json >/dev/null; done
  cp -r --no-preserve=mode "$mods"/. "$HERDR_APP_HOME/mods/"
  install -m644 "$layout" "$HERDR_APP_HOME/layouts/workbench.json"
  cp "$here/../../themes/dracula.json" "$HERDR_APP_HOME/themes/"
  echo '{"layout":"workbench"}' >"$HERDR_APP_HOME/shared.json"
  Xvfb "$display" -screen 0 1600x1000x24 -nolisten tcp >"$root/xvfb.log" 2>&1 &
  echo $! >"$root/xvfb.pid"
  sleep 1
  setsid herdr-app >"$root/app.log" 2>&1 &
  echo $! >"$root/app.pid"
  for _ in $(seq 30); do herdr-app status >/dev/null 2>&1 && break; sleep 1; done
  # A new app home opens on the welcome frame, which overlay.close leaves
  # open: its × (where a 1280x820 window draws it).
  sleep 3
  click 945 137
  sleep 1
  herdr-app status | jq -c '{errors, layout}'
  echo "up: . $root/env"
}

down() {
  [ -e "$root/env" ] || { echo "not up" >&2; return 0; }
  # shellcheck source=/dev/null
  . "$root/env"
  for f in app xvfb; do [ -f "$root/$f.pid" ] && kill "$(cat "$root/$f.pid")" 2>/dev/null || true; done
  hc server stop >/dev/null 2>&1 || true
  for m in "$@"; do ssh -o BatchMode=yes "$m" "HC_SESSION=$session hc server stop" >/dev/null 2>&1 || true; done
  rm -rf "$root"
  echo down
}

case "${1:-}" in
  up) shift; up "$@" ;;
  down) shift; down "$@" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
