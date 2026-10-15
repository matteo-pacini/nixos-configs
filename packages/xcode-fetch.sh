# Sourced by writeShellApplication (packages/xcode-fetch.nix), which
# provides the shebang, `set -euo pipefail`, and the runtime PATH.

usage() {
  cat <<'EOF'
xcode-fetch <version>

Run from a nixos-configs checkout. Makes Xcode <version> installable by
custom.xcode:
  1. downloads the .xip with xcodes (Apple ID login + 2FA)
  2. adds it to the Nix store as Xcode-<version>.xip
  3. pushes it to the attic `main` cache (sudo attic-push-closure)
  4. records its hash in modules/darwin/xcode-versions.json
EOF
}

if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 64
fi
version=$1

repo=$(git rev-parse --show-toplevel)
versions_file="$repo/modules/darwin/xcode-versions.json"
if [ ! -f "$versions_file" ]; then
  echo "not a nixos-configs checkout: $versions_file missing" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xcodes download "$version" --directory "$tmp"
shopt -s nullglob
xips=("$tmp"/*.xip)
if [ ${#xips[@]} -ne 1 ]; then
  echo "expected one .xip in $tmp, found ${#xips[@]}" >&2
  exit 1
fi

# The store path name must match the requireFile name in modules/darwin/xcode.nix.
xip="$tmp/Xcode-$version.xip"
mv "${xips[0]}" "$xip"
hash=$(nix hash file "$xip")
path=$(nix-store --add-fixed sha256 "$xip")
echo "added $path"

sudo attic-push-closure main "$path"

jq --arg v "$version" --arg h "$hash" '.[$v] = $h' "$versions_file" >"$tmp/versions.json"
mv "$tmp/versions.json" "$versions_file"
echo "recorded Xcode $version ($hash) in $versions_file"
