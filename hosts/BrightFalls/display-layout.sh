# Monitor layout for single-monitor, in Hyprland or GNOME. gaming.nix
# prepends gdctl: mutter's gdctl, empty without GNOME.
#
#   display-layout single CMD...  run CMD with DP-2 off, then restore
#   display-layout restore        DP-1 and DP-2 as declared; safe at any time

state="${XDG_RUNTIME_DIR:?}/display-layout/single.json"

# The layout of users/matteo/hyprland/user/hypr/monitors.lua, repeated here
# so a restore does not depend on that live file loading. hl.monitor starts
# from the output's existing rule and changes only the fields given, so
# every rule here states `disabled`.
dp1='hl.monitor({ output = "DP-1", disabled = false, mode = "2560x1440@144", position = "0x0", scale = 1 })'
dp2='hl.monitor({ output = "DP-2", disabled = false, mode = "2560x1440@60", position = "2560x0", scale = 1 })'
gnome_normal=(
  --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998
  --logical-monitor --monitor DP-2 --right-of DP-1 --mode 2560x1440@59.951
)

usage() {
  echo "usage: display-layout single CMD... | restore" >&2
  exit 2
}

# Instance 0 rather than HYPRLAND_INSTANCE_SIGNATURE, which a text console
# or SSH does not have.
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

# Sets monitor rules ($1, hl.monitor calls) and shows $2 as a Hyprland
# notification. Hyprland applies new monitor rules only when a monitor next
# renders, which an idle desktop may not do for a long time; the
# notification schedules a frame on every monitor.
set_rules() {
  lua "$1 hl.notification.create({ text = \"$2\", duration = 2000 })"
}

active() {
  hypr -j monitors | jq -e --arg name "$1" 'any(.[]; .name == $name)' >/dev/null
}

normal() {
  active DP-1 && active DP-2 && ! active HDMI-A-1
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

# Puts back the workspace each monitor showed before, the focused monitor's
# last so it keeps the focus.
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

  # After single-monitor, even when the layout looks right, its rule must go.
  if [ -e "$state" ] || ! normal; then
    # The real monitors first, then a reload, which drops every rule set
    # here and applies monitors.lua.
    set_rules "$dp1 $dp2" "Restoring monitors" || true
    wait_until active DP-2 || true
    hypr reload >/dev/null || true
    # A reload that cannot parse the config changes nothing; one that fails
    # inside monitors.lua leaves its rules half applied.
    if ! wait_until normal; then
      set_rules "$dp1 $dp2 hl.monitor({ output = \"HDMI-A-1\", disabled = true })" \
        "Config reload failed: monitors set directly" || true
      if ! wait_until normal; then
        echo "display-layout: DP-1 and DP-2 did not come back" >&2
        return 1
      fi
    fi
    refocus
  fi
  rm -f "$state"
}

single() {
  [ $# -gt 0 ] || usage
  # Another single-monitor owns the layout and restores it when it ends.
  if [ -e "$state" ]; then
    exec "$@"
  fi
  case $(desktop) in
    hyprland)
      mkdir -p "${state%/*}"
      hypr -j monitors >"$state" || true
      set_rules 'hl.monitor({ output = "DP-2", disabled = true })' "single-monitor: DP-2 off" || true
      ;;
    gnome)
      "$gdctl" set --logical-monitor --primary --monitor DP-1 --mode 2560x1440@143.998 || true
      ;;
    *) exec "$@" ;;
  esac
  trap 'restore || true' EXIT
  "$@"
}

[ $# -gt 0 ] || usage
command=$1
shift
case $command in
  single) single "$@" ;;
  restore) restore ;;
  *) usage ;;
esac
