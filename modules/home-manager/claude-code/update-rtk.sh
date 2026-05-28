#!/usr/bin/env bash
# Refresh vendored RTK hook and awareness doc, pinned to the rtk binary
# version from the flake's nixpkgs-master pin. The rtk binary embeds an
# integrity hash for rtk-rewrite.sh; pulling the hook from master while the
# binary lags behind upstream causes the runtime check to fail. Always
# fetch from the tag the binary was built from.
# Overwrites RTK.md and rtk-rewrite.sh — any local edits are lost.
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

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/v${VERSION}/hooks/claude"

curl -fsSL "$BASE_URL/rtk-awareness.md" --output RTK.md
curl -fsSL "$BASE_URL/rtk-rewrite.sh"   --output rtk-rewrite.sh
