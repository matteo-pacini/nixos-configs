#!/usr/bin/env bash
# Refresh vendored RTK OpenCode plugin, pinned to the rtk binary version from
# the flake's nixpkgs-master pin. Pinning keeps plugin behavior in sync with
# the binary it talks to (same reasoning as the claude-code hook, though
# OpenCode's plugin has no runtime integrity check).
# Overwrites rtk.ts — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

REPO_ROOT=$(git rev-parse --show-toplevel)
SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
VERSION=$(nix eval --raw --impure \
  --expr "(builtins.getFlake \"${REPO_ROOT}\").inputs.nixpkgs-master.legacyPackages.${SYSTEM}.rtk.version")
if [ -z "$VERSION" ]; then
  echo "error: could not resolve rtk version from the nixpkgs-master pin" >&2
  exit 1
fi

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/v${VERSION}/hooks/opencode"

curl -fsSL "$BASE_URL/rtk.ts" --output rtk.ts
