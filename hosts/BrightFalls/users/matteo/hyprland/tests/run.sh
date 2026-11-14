#!/usr/bin/env bash
# Tests for ../desk-sync.sh against a temporary HOME, run with errexit,
# nounset and pipefail as writeShellApplication runs it. Two manifests stand
# in for two generations' store copies of user/.
# Usage: run.sh <desk-sync.sh>   (needs bash, coreutils, diffutils, findutils,
# grep, sed and git on PATH)
set -euo pipefail

script=$(realpath "$1")
work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT
export HOME="$work/home"
mkdir -p "$HOME"
cfg=$HOME/.config
state=$HOME/.local/state/desk

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
ds() { # manifest, args...; output (stdout and stderr) in $out, status in $rc
  local m=$1
  shift
  rc=0
  out=$(manifest=$m config_home=$cfg state=$state \
    bash -euo pipefail "$script" "$@" 2>&1) || rc=$?
}
manifest() { # dir, then path=content pairs
  local dir=$work/$1 kv
  shift
  for kv in "$@"; do
    mkdir -p "$(dirname "$dir/${kv%%=*}")"
    printf '%s\n' "${kv#*=}" >"$dir/${kv%%=*}"
  done
  chmod -R a-w "$dir"
}
sha() { sha256sum <"$1" | cut -d' ' -f1; }

manifest gen1 hypr/a.lua=a1 hypr/b.lua=b1 hypr/c.lua=c1 hypr/d.lua=d1 \
  hypr/gone.lua=g1 mako/config=m1
manifest gen2 hypr/a.lua=a2 hypr/b.lua=b2 hypr/c.lua=c1 hypr/d.lua=d2 \
  mako/config=m2 hypr/new.lua=n2

# ---- activate ----
# d.lua starts life as a phase-1 Home Manager link into the store; c.lua
# already holds the store content without a recorded hash.
mkdir -p "$cfg/hypr"
ln -s /nix/store/00000000000000000000000000000000-home-manager-files/.config/hypr/d.lua "$cfg/hypr/d.lua"
printf 'c1\n' >"$cfg/hypr/c.lua"
ds "$work/gen1" activate
check "activate gen1 exits 0" 0 "$rc"
check "activate gen1 output" "desk-sync: hypr/a.lua: installed
desk-sync: hypr/b.lua: installed
desk-sync: hypr/d.lua: replaced the store link with a writable copy
desk-sync: hypr/gone.lua: installed
desk-sync: mako/config: installed" "$out"
check "absent: installed as a regular 0644 file" "regular file 644 a1" \
  "$(stat -c '%F %a' "$cfg/hypr/a.lua") $(cat "$cfg/hypr/a.lua")"
check "absent: hash recorded" "$(sha "$work/gen1/hypr/a.lua")" "$(cat "$state/hashes/hypr/a.lua")"
check "store link: now a regular file" "regular file 644 d1" \
  "$(stat -c '%F %a' "$cfg/hypr/d.lua") $(cat "$cfg/hypr/d.lua")"
check "identical to store: hash recorded" "$(sha "$work/gen1/hypr/c.lua")" "$(cat "$state/hashes/hypr/c.lua")"

ds "$work/gen1" activate
check "activate again: silent" "0 " "$rc $out"

# a.lua untouched, b.lua edited live, d.lua edited live, gone.lua edited live.
printf 'b1 edited\n' >"$cfg/hypr/b.lua"
printf 'd1 edited\n' >"$cfg/hypr/d.lua"
printf 'g1 edited\n' >"$cfg/hypr/gone.lua"
ds "$work/gen1" activate
check "edited, store unchanged: nothing incoming" "0  absent" \
  "$rc $out $([ -e "$state/incoming/hypr/b.lua" ] && echo present || echo absent)"

# mako/ unwritable: that one file fails, the others still go through.
chmod a-w "$cfg/mako"
ds "$work/gen2" activate
chmod u+w "$cfg/mako"
check "activate gen2 exits 1 (one file failed)" 1 "$rc"
check "activate gen2 output" "desk-sync: hypr/a.lua: updated
desk-sync: hypr/b.lua: kept the live edit; the new version is in $state/incoming/hypr/b.lua
desk-sync: hypr/d.lua: kept the live edit; the new version is in $state/incoming/hypr/d.lua
desk-sync: hypr/new.lua: installed
desk-sync: mako/config: failed, left as it was
desk-sync: hypr/gone.lua: no longer in the manifest; left $cfg/hypr/gone.lua alone" \
  "$(grep -v '^install:\|^mv:' <<<"$out")"
check "unedited: replaced" a2 "$(cat "$cfg/hypr/a.lua")"
check "unedited: hash recorded" "$(sha "$work/gen2/hypr/a.lua")" "$(cat "$state/hashes/hypr/a.lua")"
check "edited: live kept" "b1 edited" "$(cat "$cfg/hypr/b.lua")"
check "edited: store copy in incoming" b2 "$(cat "$state/incoming/hypr/b.lua")"
check "edited: hash not recorded" "$(sha "$work/gen1/hypr/b.lua")" "$(cat "$state/hashes/hypr/b.lua")"
check "removed from manifest: live left alone" "g1 edited" "$(cat "$cfg/hypr/gone.lua")"
check "removed from manifest: record dropped" absent \
  "$([ -e "$state/hashes/hypr/gone.lua" ] && echo present || echo absent)"
check "failed file: untouched" m1 "$(cat "$cfg/mako/config")"

ds "$work/gen2" activate
check "retry: failed file now updated" "0 desk-sync: mako/config: updated" "$rc $out"

# ---- status ----
rm "$cfg/hypr/new.lua"
printf 'a2 edited\n' >"$cfg/hypr/a.lua"
ds "$work/gen2" status
check "status" "edited           hypr/a.lua
incoming-pending hypr/b.lua
clean            hypr/c.lua
incoming-pending hypr/d.lua
missing          hypr/new.lua
clean            mako/config" "$out"
ds "$work/gen2" status -v
check "status -v diffs edited files" "edited           hypr/a.lua
--- store/hypr/a.lua
+++ live/hypr/a.lua
@@ -1 +1 @@
-a2
+a2 edited" "$(head -6 <<<"$out")"

# ---- reset ----
ds "$work/gen2" reset hypr/b.lua
check "reset one" "0 reset hypr/b.lua
To apply: hyprctl reload" "$rc $out"
check "reset: store copy back" b2 "$(cat "$cfg/hypr/b.lua")"
check "reset: hash recorded" "$(sha "$work/gen2/hypr/b.lua")" "$(cat "$state/hashes/hypr/b.lua")"
check "reset: incoming cleared" absent \
  "$([ -e "$state/incoming/hypr/b.lua" ] && echo present || echo absent)"
ds "$work/gen2" reset "$cfg/hypr/a.lua"
check "reset by live path" "0 a2" "$rc $(cat "$cfg/hypr/a.lua")"
manifest shell quickshell/shell.qml=q1
ds "$work/shell" reset quickshell/shell.qml
check "reset: quickshell needs no reload" "0 reset quickshell/shell.qml
To apply: nothing for quickshell (it reloads on file change)" "$rc $out"
ds "$work/gen2" reset hypr/nope.lua
check "reset outside the manifest" "1 desk-sync: hypr/nope.lua: not in the manifest (see desk-sync status)" "$rc $out"

# ---- pull ----
repo=$work/repo
sub=hosts/BrightFalls/users/matteo/hyprland/user
mkdir -p "$repo/$sub/hypr"
cp "$work/gen2/hypr/c.lua" "$repo/$sub/hypr/c.lua"
cp "$work/gen2/hypr/d.lua" "$repo/$sub/hypr/d.lua"
git -C "$repo" init -q
git -C "$repo" add .
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init

ds "$work/gen2" pull
check "pull needs a directory" 2 "$rc"
ds "$work/gen2" pull "$work"
check "pull refuses a non-checkout" 1 "$rc"

printf 'c1\n-- launcher\napi_key = "abc"\n' >"$cfg/hypr/c.lua"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n' >"$cfg/hypr/b.lua"
printf 'k = "%s"\n' "AbCdEf0123456789AbCdEf0123456789AbCdEf0123" >"$cfg/mako/config"
ds "$work/gen2" pull "$repo"
check "pull refuses secrets, copies the rest" "1 desk-sync: not copying hypr/b.lua: line 1 of $cfg/hypr/b.lua looks like a secret
desk-sync: not copying hypr/c.lua: line 3 of $cfg/hypr/c.lua looks like a secret
copied hypr/d.lua
desk-sync: not copying mako/config: line 1 of $cfg/mako/config looks like a secret
 M $sub/hypr/d.lua" "$rc $out"
check "pull: copied content" "d1 edited" "$(cat "$repo/$sub/hypr/d.lua")"

printf 'bearer abcdefghijklmnopqrstuvwxyz\n' >"$cfg/hypr/c.lua"
printf 'm2\n' >"$cfg/mako/config"
ds "$work/gen2" reset hypr/b.lua
ds "$work/gen2" pull "$repo"
check "pull refuses a bearer string" "1 desk-sync: not copying hypr/c.lua: line 1 of $cfg/hypr/c.lua looks like a secret
copied hypr/d.lua
 M $sub/hypr/d.lua" "$rc $out"

printf 'local x = "/nix/store/0qnwcm4i62lj90fx9mc7vwjk3s1qrisz-hyprland-0.57.2"\n' >"$cfg/hypr/c.lua"
ds "$work/gen2" pull "$repo"
check "pull: a store path is not a secret" "0 copied hypr/c.lua
copied hypr/d.lua
 M $sub/hypr/c.lua
 M $sub/hypr/d.lua" "$rc $out"

exit "$failed"
