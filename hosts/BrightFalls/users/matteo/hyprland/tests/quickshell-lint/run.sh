#!/usr/bin/env bash
# The shell's QML through qmllint, and its IPC calls against its IpcHandlers
# (ipc.js), then the same on copies with one fault planted each, which must
# fail with a message naming the fault.
# Usage: run.sh <quickshell dir> <bindings.lua> <rescue.lua> <qml import dir>...
#   (needs qmllint, jq, node and coreutils on PATH; ipc.js and allowlist are
#   read from this script's directory)
#
# qmllint sees the tree as Quickshell's scanner does (src/core/scan.cpp): a
# qmldir per directory, "module qs" plus the path with dots, and one line per
# file whose name starts with a capital, "singleton" when its header (the
# lines before the first "{") has the line "pragma Singleton". lock.qml, the
# lock's own entry point, sits in the same directory as shell.qml, so it gets
# the same root module; like every lowercase file it is not in a qmldir.
#
# Paths given to qmllint must be absolute: it reads the qmldir of a file's
# directory under the canonical path, and a file named by a relative path is
# a different type to it, so every singleton was reported as "not declared as
# singleton in qmldir".
#
# One category is off: id-shadows-member (an id named like a member of the
# object where it is used, `content` and `left` here; QML resolves the id
# first, so it is a readability warning, not a fault). Every other warning
# fails unless it matches a line of ./allowlist; that is where the hundreds
# of "Unqualified access" warnings for ids read inside delegates are
# accepted, by qmllint's own suggestion, so that a name that exists nowhere
# still fails.
set -euo pipefail

here=$(dirname "$(realpath "$0")")
src=$(realpath "$1")
bindings=$(realpath "$2")
rescue=$(realpath "$3")
shift 3
imports=()
for dir in "$@"; do imports+=(-I "$dir"); done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

prepare() { # dir: a copy of the tree at <dir>/qs with its qmldir files
  mkdir -p "$1"
  cp -r "$src" "$1/qs"
  chmod -R u+w "$1/qs"
  local d rel f name
  while read -r d; do
    rel=${d#"$1"/}
    {
      [[ $rel =~ ^[A-Za-z0-9_/]+$ ]] && echo "module ${rel//\//.}"
      for f in "$d"/[A-Z]*.qml; do
        [ -e "$f" ] || continue
        name=$(basename "$f" .qml)
        awk '{ gsub(/^[ \t\r]+|[ \t\r]+$/, "") } $0 == "pragma Singleton" { s = 1 } /\{/ { exit }
          END { exit !s }' "$f" &&
          name="singleton $name"
        echo "$name 1.0 $(basename "$f")"
      done
    } >"$d/qmldir"
  done < <(find "$1/qs" -type d)
}

lint() { # dir, full (1: also report unused allowlist lines), files...
  local dir=$1 full=$2
  shift 2
  qmllint "${imports[@]}" -I "$dir" --id-shadows-member disable \
    --json "$dir/lint.json" "$@" >/dev/null 2>&1 || true
  if [ "$(jq '.files | length' "$dir/lint.json")" != $# ]; then
    echo "qmllint reported on $(jq '.files | length' "$dir/lint.json") of $# files"
    return 1
  fi
  jq -Rn 'reduce inputs as $l ({}; .[input_filename] += [$l])' "$@" >"$dir/sources.json"
  # A warning is "file: message [category]", plus the first line of
  # qmllint's first suggestion if it has one, when matched against the
  # allowlist, so a line there does not depend on line numbers. "Unqualified
  # access" names no identifier, so the one at its position is added.
  jq -r --arg root "$dir/qs/" --arg full "$full" --rawfile allow "$here/allowlist" \
    --slurpfile src "$dir/sources.json" '
    [$allow | split("\n") | to_entries[] | select(.value | test("^\\s*(#.*)?$") | not)
      | {n: (.key + 1), re: .value}] as $pats
    | [.files[] | .filename as $path | ($path | ltrimstr($root)) as $f | .warnings[] | select(.type != "info")
      | (if .id == "unqualified"
         then " \"\($src[0][$path][.line - 1][.column - 1:.column - 1 + .length])\"" else "" end) as $name
      | (.suggestions | if length > 0 then " " + (.[0].message | split("\n")[0]) else "" end) as $hint
      | {key: "\($f): \(.message)\($name) [\(.id)]\($hint)",
         show: "\($f):\(.line):\(.column): \(.message)\($name) [\(.id)]\(.suggestions | map(" " + (.message | split("\n")[0])) | join(""))"}] as $ws
    | [$ws[] | select(.key as $k | any($pats[]; .re as $r | $k | test($r)) | not) | .show]
      + if $full == "1" then
          [$pats[] | select(.re as $r | any($ws[]; .key | test($r)) | not)
            | "allowlist line \(.n) matches no warning (remove it): \(.re)"]
        else [] end
    | .[]' "$dir/lint.json" >"$dir/failures"
  [ -s "$dir/failures" ] || return 0
  sort -t: -k1,1 -k2,2n "$dir/failures"
  return 1
}

ipc() { # dir, lua files...
  local dir=$1
  shift
  node "$here/ipc.js" "$dir/qs" "$@"
}

failed=0
prepare "$work/tree"
mapfile -t files < <(find "$work/tree/qs" -name '*.qml' | sort)
if lint "$work/tree" 1 "${files[@]}"; then
  echo "qmllint: ${#files[@]} files, no warnings outside the allowlist"
else
  failed=1
fi
ipc "$work/tree" "$bindings" "$rescue" || failed=1

# Each fault, planted in a fresh copy, must fail with output matching the
# pattern (grep -E).
n=0
plant() { # name, pattern, file in the tree (or bindings.lua), sed script
  local dir=$work/plant$((n += 1)) out rc=0
  prepare "$dir"
  if [ "$3" = bindings.lua ]; then
    cp "$bindings" "$dir/bindings.lua"
    sed -i "$4" "$dir/bindings.lua"
    out=$(ipc "$dir" "$dir/bindings.lua" "$rescue") || rc=$?
  else
    sed -i "$4" "$dir/qs/$3"
    cmp -s "$src/$3" "$dir/qs/$3" && { echo "FAIL $1: the plant changed nothing"; failed=1; return; }
    out=$(lint "$dir" 0 "$dir/qs/$3" && ipc "$dir" "$bindings" "$rescue") || rc=$?
  fi
  if [ "$rc" != 0 ] && grep -qE -- "$2" <<<"$out"; then
    echo "ok   $1: $(grep -m1 -E -- "$2" <<<"$out")"
  else
    echo "FAIL $1 (exit $rc), expected /$2/ in:"
    sed 's/^/     /' <<<"$out"
    failed=1
  fi
}
plant "stray brace" '^common/DropCard.qml:60:.*\[syntax\]' common/DropCard.qml '$a }'
plant "unknown qs module" 'Failed to import qs\.nosuch' common/DropCard.qml '/^import qs$/a import qs.nosuch'
plant "unknown component" 'NoSuchCard' common/DropCard.qml '/^        MouseArea {$/i NoSuchCard {}'
plant "misspelt id" 'Unqualified access "cadr"' common/DropCard.qml 's/radius: card\.radius/radius: cadr.radius/'
plant "misspelt id in a delegate" 'Tailscale.qml:[0-9]+:[0-9]+: Unqualified access "contnet"' Tailscale.qml 's/width: content\.width$/width: contnet.width/'
plant "misspelt Qt property" '"widht"' common/DropCard.qml 's/border\.width: 1/border.widht: 1/'
plant "misspelt Quickshell property" '"printErrrors"' common/LockedList.qml 's/printErrors:/printErrrors:/'
plant "misspelt singleton member" '"surfaec" not found on type "Style"' common/DropCard.qml 's/Style\.surface/Style.surfaec/'
plant "missing .js import" 'devicez\.js' bluetooth/BluetoothShared.qml 's/"devices\.js"/"devicez.js"/'
plant "bind to a missing target" 'no IpcHandler has target "launchr"' bindings.lua 's/qs ipc call launcher toggle/qs ipc call launchr toggle/'
plant "bind to a missing function" 'IpcHandler "launcher" .* has no function "toogle"' bindings.lua 's/qs ipc call launcher toggle/qs ipc call launcher toogle/'
plant "QML call to a missing function" 'Bar.qml:[0-9]+: .*has no function "toogle"' Bar.qml 's/"call", "launcher", "toggle"/"call", "launcher", "toogle"/'
plant "bind with an argument too many" 'launcher.toggle .* takes 0 argument\(s\), the call passes 1' bindings.lua 's/qs ipc call launcher toggle/qs ipc call launcher toggle 1/'
plant "IPC function with an untyped parameter" 'lockscreen.hold: parameter "pid" needs one of the types' Lockscreen.qml 's/function hold(pid: int)/function hold(pid)/'
plant "two handlers on one target" 'target "launcher" is also declared' Cheatsheet.qml 's/target: "cheatsheet"/target: "launcher"/'

echo "quickshell-lint: ${SECONDS}s"
exit "$failed"
