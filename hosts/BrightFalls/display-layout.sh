# Monitor layout for Sunshine streams and single-monitor, in Hyprland or
# GNOME. gaming.nix prepends: gdctl (mutter's gdctl, empty without GNOME) and
# video_port (Sunshine's video UDP port, bound only while a stream runs).
#
#   display-layout stream-on      the dummy 4K output alone (Sunshine's do)
#   display-layout restore        DP-1 and DP-2 as declared (Sunshine's undo;
#                                 safe to run at any time)
#   display-layout watch          restore once no stream runs (stream-on
#                                 starts it as the display-layout-watch unit)
#   display-layout single CMD...  run CMD with DP-2 off, then restore

state="${XDG_RUNTIME_DIR:?}/display-layout/stream.json"
unit=display-layout-watch
# The watchdog restores after this long with no stream: long enough for a
# client to reconnect after Sunshine's own ping timeout ends the session.
grace=60
tick=5

# The layout of users/matteo/hyprland/user/hypr/monitors.lua, repeated here
# so a restore does not depend on that live file loading.
dp1='hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })'
dp2='hl.monitor({ output = "DP-2", mode = "2560x1440@60", position = "2560x0", scale = 1 })'
gnome_normal=(
  --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998
  --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951
)

usage() {
  echo "usage: display-layout stream-on | restore | watch | single CMD..." >&2
  exit 2
}

# Instance 0 rather than HYPRLAND_INSTANCE_SIGNATURE, which a text console,
# SSH or a service started before the session does not have.
hypr() {
  hyprctl --instance 0 "$@"
}

desktop() {
  if hypr version >/dev/null 2>&1; then
    echo hyprland
  elif [ -n "$gdctl" ]; then
    echo gnome
  else
    echo none
  fi
}

lua() {
  local out
  out=$(hypr eval "$1") || return 1
  if [ "$out" != ok ]; then
    echo "display-layout: hyprctl eval: $out" >&2
    return 1
  fi
}

active() {
  hypr -j monitors | jq -e --arg name "$1" 'any(.[]; .name == $name)' >/dev/null
}

normal() {
  active DP-1 && active DP-2 && ! active HDMI-A-1
}

streaming() {
  active HDMI-A-1 && ! active DP-1 && ! active DP-2
}

# Up to 10 s.
wait_until() {
  local _
  for _ in $(seq 20); do
    "$@" && return 0
    sleep 0.5
  done
  return 1
}

# Puts back the workspace each monitor showed before the stream, the focused
# monitor's last so it keeps the focus.
refocus() {
  local ws
  [ -s "$state" ] || return 0
  jq -r 'sort_by(.focused) | .[] | .activeWorkspace.id | select(. > 0)' "$state" |
    while read -r ws; do
      lua "hl.dispatch(hl.dsp.focus({ workspace = $ws }))" || true
    done
}

restore() {
  case $(desktop) in
    gnome)
      "$gdctl" set "${gnome_normal[@]}" || return 1
      rm -f "$state"
      return
      ;;
    none)
      echo "display-layout: no Hyprland or GNOME session" >&2
      return 1
      ;;
  esac

  # After a prepare, even one that changed nothing visible, its rules must go.
  if [ -e "$state" ] || ! normal; then
    # The real monitors first, so nothing is ever left without one; then a
    # reload, which drops every rule set here and applies monitors.lua.
    lua "$dp1 $dp2" || true
    wait_until active DP-1 || true
    hypr reload >/dev/null || true
    # A reload that cannot parse the config changes nothing; one that fails
    # inside monitors.lua leaves its rules half applied.
    if ! wait_until normal; then
      lua "$dp1 $dp2 hl.monitor({ output = \"HDMI-A-1\", disabled = true })" || true
      if ! wait_until normal; then
        echo "display-layout: DP-1 and DP-2 did not come back" >&2
        return 1
      fi
    fi
    refocus
  fi
  rm -f "$state"
}

stream_on() {
  local d
  d=$(desktop)
  mkdir -p "${state%/*}"
  case $d in
    hyprland) hypr -j monitors >"$state" ;;
    gnome) echo '[]' >"$state" ;;
    *)
      echo "display-layout: no Hyprland or GNOME session" >&2
      exit 1
      ;;
  esac

  # The watchdog is armed before anything changes, so a prepare killed
  # half-way is still undone.
  systemctl --user stop "$unit.service" 2>/dev/null || true
  if ! systemd-run --user --unit="$unit" --collect --quiet \
    --property=PartOf=graphical-session.target "$0" watch; then
    rm -f "$state"
    exit 1
  fi

  # Sunshine runs no undo for a prepare that fails, so it undoes itself.
  trap 'restore || true' EXIT
  if [ "$d" = gnome ]; then
    "$gdctl" set --logical-monitor --primary --monitor HDMI-1 --mode 3840x2160@59.940
  else
    # Right of DP-2 so it overlaps nothing while all three are on. The real
    # monitors go off only once the dummy is up. Off, not merely secondary:
    # with no output_name, Sunshine's KMS capture takes the first lit plane.
    lua 'hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "5120x0", scale = 1 })'
    wait_until active HDMI-A-1
    lua 'hl.monitor({ output = "DP-1", disabled = true }) hl.monitor({ output = "DP-2", disabled = true })'
    wait_until streaming
  fi
  trap - EXIT
}

watch() {
  local idle=0 reason
  while [ -e "$state" ]; do
    sleep "$tick"
    [ "$(desktop)" != none ] || exit 0
    if ! systemctl --user --quiet is-active sunshine.service; then
      reason="Sunshine is not running"
    elif [ -n "$(ss -Hlun "sport = :$video_port")" ]; then
      idle=0
      continue
    else
      idle=$((idle + tick))
      [ "$idle" -ge "$grace" ] || continue
      reason="no stream for $idle s"
    fi
    echo "display-layout: $reason, restoring"
    restore || true
  done
}

single() {
  [ $# -gt 0 ] || usage
  # A stream owns the layout; restoring at the end would end it.
  if [ -e "$state" ]; then
    exec "$@"
  fi
  case $(desktop) in
    hyprland) lua 'hl.monitor({ output = "DP-2", disabled = true })' || true ;;
    gnome) "$gdctl" set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 || true ;;
    *) exec "$@" ;;
  esac
  trap '[ -e "$state" ] || restore || true' EXIT
  "$@"
}

[ $# -gt 0 ] || usage
command=$1
shift
case $command in
  stream-on) stream_on ;;
  restore) restore ;;
  watch) watch ;;
  single) single "$@" ;;
  *) usage ;;
esac
