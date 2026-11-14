# desk-sync: installs the files under user/ as writable files and keeps live
# edits to them. See README.md beside this file.
#
# The Nix wrapper sets, before this text:
#   manifest     store copy of user/; each file in it lives at the same path
#                under config_home
#   config_home  ~/.config
#   state        ~/.local/state/desk, holding hashes/<path> (sha256 of the
#                store copy last installed at <path>) and incoming/<path> (a
#                newer store copy that a live edit kept from being installed)

usage() {
  cat >&2 <<'EOF'
usage: desk-sync status [-v]          clean / edited / incoming-pending / missing; -v diffs
       desk-sync reset <path>|--all   put the store copy back
       desk-sync pull <checkout-dir>  copy edited files into a nixos-configs checkout
       desk-sync activate             run by Home Manager activation
<path> is relative to ~/.config (hypr/bindings.lua) or the live path itself.
EOF
  exit 2
}

die() {
  echo "desk-sync: $*" >&2
  exit 1
}

files() {
  find "$manifest" -type f -printf '%P\n' | LC_ALL=C sort
}

hash() {
  sha256sum <"$1" | cut -d' ' -f1
}

# Each of these returns non-zero on failure rather than relying on errexit:
# activate calls them from an `||` list, where bash ignores errexit.
install_store() { # rel
  local live="$config_home/$1"
  mkdir -p "$(dirname "$live")" || return 1
  # Written beside the live file and renamed over it, so a reader never sees
  # half a file and a store symlink is replaced rather than followed.
  install -m 0644 "$manifest/$1" "$live.desk-new" || return 1
  mv -fT "$live.desk-new" "$live"
}

record() { # rel
  mkdir -p "$(dirname "$state/hashes/$1")" || return 1
  hash "$manifest/$1" >"$state/hashes/$1"
}

clear_incoming() { # rel
  rm -f "$state/incoming/$1"
}

restore() { # rel: live file, recorded hash and incoming copy all match the store
  install_store "$1" || return 1
  record "$1" || return 1
  clear_incoming "$1"
}

activate_one() { # rel
  local rel=$1 live="$config_home/$1" recorded=""
  if [ -f "$state/hashes/$rel" ]; then
    recorded=$(cat "$state/hashes/$rel") || return 1
  fi

  if [ -L "$live" ] && [[ $(readlink "$live") == /nix/store/* ]]; then
    restore "$rel" || return 1
    echo "desk-sync: $rel: replaced the store link with a writable copy"
  elif [ ! -e "$live" ] && [ ! -L "$live" ]; then
    restore "$rel" || return 1
    echo "desk-sync: $rel: installed"
  elif [ -f "$live" ] && cmp -s "$live" "$manifest/$rel"; then
    record "$rel" || return 1
    clear_incoming "$rel"
  elif [ -f "$live" ] && [ ! -L "$live" ] && [ -n "$recorded" ] &&
    [ "$(hash "$live")" = "$recorded" ]; then
    restore "$rel" || return 1
    echo "desk-sync: $rel: updated"
  elif [ "$(hash "$manifest/$rel")" = "$recorded" ]; then
    # Edited live, and the store copy is the one already installed under the
    # edit: nothing is incoming. Clears a copy left by a generation since
    # rolled back.
    clear_incoming "$rel"
  elif ! cmp -s "$state/incoming/$rel" "$manifest/$rel"; then
    mkdir -p "$(dirname "$state/incoming/$rel")" || return 1
    install -m 0644 "$manifest/$rel" "$state/incoming/$rel" || return 1
    echo "desk-sync: $rel: kept the live edit; the new version is in $state/incoming/$rel"
  fi
}

activate() {
  local rel failed=0
  while IFS= read -r rel; do
    activate_one "$rel" || {
      echo "desk-sync: $rel: failed, left as it was" >&2
      failed=1
    }
  done < <(files)

  # A path with a recorded hash that is not in the manifest any more.
  if [ -d "$state/hashes" ]; then
    while IFS= read -r rel; do
      [ -f "$manifest/$rel" ] && continue
      echo "desk-sync: $rel: no longer in the manifest; left $config_home/$rel alone"
      rm -f "$state/hashes/$rel" "$state/incoming/$rel"
    done < <(find "$state/hashes" -type f -printf '%P\n' | LC_ALL=C sort)
  fi
  return "$failed"
}

file_status() { # rel
  local live="$config_home/$1"
  if [ ! -e "$live" ]; then
    echo missing
  elif [ -e "$state/incoming/$1" ]; then
    echo incoming-pending
  elif cmp -s "$live" "$manifest/$1"; then
    echo clean
  else
    echo edited
  fi
}

status() {
  local verbose=0 rel st
  case "${1-}" in
  -v) verbose=1 ;;
  "") ;;
  *) usage ;;
  esac
  while IFS= read -r rel; do
    st=$(file_status "$rel")
    printf '%-16s %s\n' "$st" "$rel"
    if [ "$verbose" = 1 ] && [[ $st == edited || $st == incoming-pending ]]; then
      diff -u --label "store/$rel" --label "live/$rel" \
        "$manifest/$rel" "$config_home/$rel" || true
    fi
  done < <(files)
}

reset() {
  [ $# -eq 1 ] || usage
  local rel rels=() hints=()
  if [ "$1" = --all ]; then
    mapfile -t rels < <(files)
  else
    rel=${1#"$config_home"/}
    [ -f "$manifest/$rel" ] || die "$1: not in the manifest (see desk-sync status)"
    rels=("$rel")
  fi
  for rel in "${rels[@]}"; do
    restore "$rel" || die "$rel: could not reset"
    echo "reset $rel"
  done
  for rel in "${rels[@]}"; do
    case $rel in
    hypr/*) hints+=("hyprctl reload") ;;
    mako/*) hints+=("makoctl reload") ;;
    quickshell/*) hints+=("nothing for quickshell (it reloads on file change)") ;;
    esac
  done
  if [ ${#hints[@]} -gt 0 ]; then
    echo "To apply: $(printf '%s\n' "${hints[@]}" | sort -u | paste -sd ';' - | sed 's/;/; /g')"
  fi
}

# Line numbers of $1 that look like a secret, one per line; fails if none.
secret_lines() {
  {
    grep -n -e '-----BEGIN \([A-Z0-9]* \)*PRIVATE KEY' "$1" || true
    grep -niE '(password|passwd|secret|token|api[_-]?key)[a-z0-9_]*["'\'']?[[:space:]]*[:=]' "$1" || true
    grep -niE 'bearer[[:space:]]+[A-Za-z0-9._~+/=-]{16,}' "$1" || true
    # Long runs with a letter and a digit: API keys, not identifiers.
    grep -noE '[A-Za-z0-9_+=]{40,}' "$1" | grep -E '^[0-9]+:[^:]*[0-9]' |
      grep -E '^[0-9]+:[^:]*[A-Za-z]' || true
  } | cut -d: -f1 | sort -un | grep .
}

pull() {
  [ $# -eq 1 ] || usage
  local subtree=hosts/BrightFalls/users/matteo/hyprland/user rel live lines refused=0
  [ -d "$1/$subtree" ] || die "$1/$subtree: no such directory; pass the root of a nixos-configs checkout"
  while IFS= read -r rel; do
    live="$config_home/$rel"
    [ -f "$live" ] || continue
    cmp -s "$live" "$manifest/$rel" && continue
    if lines=$(secret_lines "$live"); then
      echo "desk-sync: not copying $rel: line $(paste -sd, - <<<"$lines" | sed 's/,/, /g') of $live looks like a secret" >&2
      refused=1
      continue
    fi
    install -Dm644 "$live" "$1/$subtree/$rel"
    echo "copied $rel"
  done < <(files)
  git -C "$1" status --short -- "$subtree"
  return "$refused"
}

case "${1-}" in
activate) activate ;;
status)
  shift
  status "$@"
  ;;
reset)
  shift
  reset "$@"
  ;;
pull)
  shift
  pull "$@"
  ;;
*) usage ;;
esac
