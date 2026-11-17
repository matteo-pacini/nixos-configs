#!/usr/bin/env bash
# The Hyprland config as Home Manager installs it: user/hypr under
# $XDG_CONFIG_HOME/hypr, defaults/hypr under $XDG_DATA_HOME/desk/hypr,
# theme.json under $XDG_CONFIG_HOME/desk.
#   verify: Hyprland --verify-config must accept the entry point and the two
#     read-only files on their own, and the entry point must reach those two
#     at their installed paths: it loads them through pcall, so a missing one
#     is not an error.
#   theme: theme.lua's reading of theme.json, run under the Lua Hyprland
#     embeds; needs no Hyprland.
# Usage: run.sh verify <Hyprland> <user dir> <defaults dir>
#        run.sh theme <lua> <user dir> <defaults dir>
#   (needs bash, coreutils, grep and sed on PATH, and jq for theme)
set -euo pipefail

mode=$1 user=$3 defaults=$4
case $mode in
verify) hyprland=$2 ;;
theme) lua=$2 ;;
*) echo "unknown mode: $mode" >&2 && exit 2 ;;
esac
work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/share \
  XDG_RUNTIME_DIR=$work/run
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/desk" "$XDG_RUNTIME_DIR"
cp -r "$user/hypr" "$user/desk" "$XDG_CONFIG_HOME/"
cp -r "$defaults/hypr" "$XDG_DATA_HOME/desk/"
chmod -R u+w "$work"

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
verify() { # config file; the parsing result in $out, status in $rc
  rc=0
  out=$("$hyprland" --verify-config -c "$1" 2>&1) || rc=$?
  out=$(sed -n '/Config parsing result:/,$p' <<<"$out" | grep -v 'Config parsing result:\|^$' || true)
}

if [ "$mode" = verify ]; then
  verify "$XDG_CONFIG_HOME/hypr/hyprland.lua"
  check "hyprland.lua (with everything it requires)" "0 config ok" "$rc $out"
  verify "$XDG_DATA_HOME/desk/hypr/rescue.lua"
  check "rescue.lua on its own" "0 config ok" "$rc $out"
  verify "$XDG_DATA_HOME/desk/hypr/theme.lua"
  check "theme.lua on its own" "0 config ok" "$rc $out"

  # The checker itself: a config error must fail it.
  cp "$XDG_CONFIG_HOME/hypr/input.lua" "$work/input.lua"
  echo 'hl.config({ input = { no_such_option = 1 } })' >>"$XDG_CONFIG_HOME/hypr/input.lua"
  verify "$XDG_CONFIG_HOME/hypr/hyprland.lua"
  check "an unknown option fails the check" 1 "$rc"
  cp "$work/input.lua" "$XDG_CONFIG_HOME/hypr/input.lua"
  echo 'hl.bind("SUPER + Retrun", hl.dsp.exec_cmd("true"))' >>"$XDG_CONFIG_HOME/hypr/input.lua"
  verify "$XDG_CONFIG_HOME/hypr/hyprland.lua"
  check "a misspelt key name fails the check" "1 1" "$rc $(grep -c 'Unknown key: Retrun' <<<"$out")"
  cp "$work/input.lua" "$XDG_CONFIG_HOME/hypr/input.lua"

  # An error planted in each read-only file shows that hyprland.lua loads it.
  for f in rescue theme; do
    cp "$XDG_DATA_HOME/desk/hypr/$f.lua" "$work/$f.lua"
    sed -i '1i error("planted")' "$XDG_DATA_HOME/desk/hypr/$f.lua"
    verify "$XDG_CONFIG_HOME/hypr/hyprland.lua"
    check "hyprland.lua loads $f.lua from \$XDG_DATA_HOME/desk/hypr" "1 1" \
      "$rc $(grep -c "$f.lua:[0-9]*: planted" <<<"$out")"
    cp "$work/$f.lua" "$XDG_DATA_HOME/desk/hypr/$f.lua"
  done
  exit "$failed"
fi

# ---- theme.lua ----
cat >"$work/print.lua" <<'LUA'
local t = dofile(arg[1])
local keys = {}
for key in pairs(t) do keys[#keys + 1] = key end
table.sort(keys)
for _, key in ipairs(keys) do print(key .. "=" .. t[key]) end
LUA
theme() { # prints the palette theme.lua returns, sorted "key=value" lines
  "$lua" "$work/print.lua" "$XDG_DATA_HOME/desk/hypr/theme.lua"
}
json="$XDG_CONFIG_HOME/desk/theme.json"
shipped=$(jq -r 'to_entries | sort_by(.key) | .[] | "\(.key)=\(.value)"' "$user/desk/theme.json")
check "the shipped theme.json: every key read as written" "$shipped" "$(theme)"

dracula=$(mv "$json" "$work/theme.json" && theme)
check "no theme.json: the built-in palette, every key" 13 "$(wc -l <<<"$dracula")"
check "no theme.json: Dracula's purple" "purple=#bd93f9" "$(grep '^purple=' <<<"$dracula")"
mv "$work/theme.json" "$json"

with() { # theme.json content; prints the palette's lines that differ from Dracula
  printf '%s' "$1" >"$json"
  comm -13 <(printf '%s\n' "$dracula") <(theme)
}
check "a valid colour and font are taken" "font_ui=Some Sans
purple=#123abc" "$(with '{"purple": "#123abc", "font_ui": "Some Sans"}')"
check "alpha, short or named colours fall back" "" \
  "$(with '{"purple": "#123abcff", "pink": "#fff", "red": "red", "cyan": "123abc"}')"
check "a blank font falls back" "" "$(with '{"font_ui": "  ", "font_mono": ""}')"
check "unknown keys are not added" "" "$(with '{"accent": "#123456"}')"
check "an escaped quote skips that pair only" "green=#00ff00" \
  "$(with '{"font_ui": "A \"B\" C", "green": "#00ff00"}')"
check "a truncated file keeps what came before the cut" "cyan=#00ffff" \
  "$(with '{"cyan": "#00ffff", "green": "#00ff')"
check "not JSON at all: the built-in palette" "" "$(with 'not json')"
check "a non-string value falls back" "" "$(with '{"red": 16711680}')"
rm "$json"
mkdir -p "$HOME/.config/desk"
printf '{"orange": "#ff8800"}' >"$HOME/.config/desk/theme.json"
check "no XDG_CONFIG_HOME: ~/.config/desk/theme.json" "orange=#ff8800" \
  "$(XDG_CONFIG_HOME='' theme | comm -13 <(printf '%s\n' "$dracula") -)"

exit "$failed"
