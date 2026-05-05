#!/usr/bin/env bash
# Refresh vendored RTK hook and awareness doc from upstream.
# Overwrites RTK.md and rtk-rewrite.sh — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/master/hooks/claude"

curl -fsSL "$BASE_URL/rtk-awareness.md" --output RTK.md
curl -fsSL "$BASE_URL/rtk-rewrite.sh"   --output rtk-rewrite.sh
