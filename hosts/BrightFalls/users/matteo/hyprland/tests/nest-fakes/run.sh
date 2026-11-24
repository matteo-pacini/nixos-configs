#!/usr/bin/env bash
# desk-nest's fakes against the panels' libraries (test-nest-fakes.js), on a
# copy laid out as in the checkout: <work>/hl/nest beside <work>/hl/tests,
# fakes.py's first line pointed at the python3 on PATH (a Nix builder has no
# /usr/bin/env), and a `gdbus` that records its arguments after bin/ on PATH.
# Usage: run.sh <nest dir> <tests dir> <quickshell dir>
#   (needs python3, node and coreutils on PATH)
set -euo pipefail

here=$(dirname "$(realpath "$0")")
nest=$(realpath "$1")
tests=$(realpath "$2")
qs=$(realpath "$3")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/hl" "$work/realbin"
cp -r "$nest" "$work/hl/nest"
chmod -R u+w "$work/hl/nest"
ln -s "$tests" "$work/hl/tests"
sed -i "1s|.*|#!$(command -v python3)|" "$work/hl/nest/fakes/fakes.py"
cat >"$work/realbin/gdbus" <<EOF
#!$(command -v bash)
echo "\$*" >>"$work/gdbus-calls"
EOF
chmod +x "$work/realbin/gdbus"

PATH=$work/hl/nest/fakes/bin:$work/realbin:$PATH TZ=${TZ:-Europe/London} \
  node "$here/test-nest-fakes.js" "$work/hl" "$qs" "$work"
