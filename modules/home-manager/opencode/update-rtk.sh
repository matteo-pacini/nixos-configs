#!/usr/bin/env bash
# Refresh vendored RTK OpenCode plugin, pinned to the rtk binary version in
# ../../../packages/rtk/package.nix. Pinning keeps plugin behavior in sync
# with the binary it talks to (same reasoning as the claude-code hook,
# though OpenCode's plugin has no runtime integrity check).
# Overwrites rtk.ts — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

PACKAGE_NIX="../../../packages/rtk/package.nix"
VERSION=$(grep -m1 -E '^\s*version = "' "$PACKAGE_NIX" | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$VERSION" ]; then
  echo "error: could not parse rtk version from $PACKAGE_NIX" >&2
  exit 1
fi

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/v${VERSION}/hooks/opencode"

curl -fsSL "$BASE_URL/rtk.ts" --output rtk.ts
