#!/usr/bin/env bash
# Refresh vendored RTK hook and awareness doc, pinned to the rtk binary
# version in ../../../packages/rtk/package.nix. The rtk binary embeds an
# integrity hash for rtk-rewrite.sh; pulling the hook from master while the
# binary lags behind upstream causes the runtime check to fail. Always
# fetch from the tag the binary was built from.
# Overwrites RTK.md and rtk-rewrite.sh — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

PACKAGE_NIX="../../../packages/rtk/package.nix"
VERSION=$(grep -m1 -E '^\s*version = "' "$PACKAGE_NIX" | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
  echo "error: could not parse rtk version from $PACKAGE_NIX" >&2
  exit 1
fi

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/v${VERSION}/hooks/claude"

curl -fsSL "$BASE_URL/rtk-awareness.md" --output RTK.md
curl -fsSL "$BASE_URL/rtk-rewrite.sh"   --output rtk-rewrite.sh
