#!/usr/bin/env bash
# Refresh vendored RTK artifacts for Claude Code and OpenCode, pinned to the rtk
# binary version from the flake's nixpkgs-master pin. The rtk binary embeds an
# integrity hash for the Claude hook (rtk-rewrite.sh); pulling a hook from
# master while the binary lags behind upstream causes the runtime check to
# fail, so always fetch from the tag the binary was built from. OpenCode's
# rtk.ts plugin has no integrity check but is pinned for the same consistency.
# Overwrites claude-code/{RTK.md,rtk-rewrite.sh} and opencode/rtk.ts — any local
# edits are lost.
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

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/v${VERSION}/hooks"

curl -fsSL "$BASE_URL/claude/rtk-awareness.md" --output claude-code/RTK.md
curl -fsSL "$BASE_URL/claude/rtk-rewrite.sh"   --output claude-code/rtk-rewrite.sh
curl -fsSL "$BASE_URL/opencode/rtk.ts"         --output opencode/rtk.ts
