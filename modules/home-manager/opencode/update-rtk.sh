#!/usr/bin/env bash
# Refresh vendored RTK OpenCode plugin from upstream.
# Overwrites rtk.ts — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://raw.githubusercontent.com/rtk-ai/rtk/master/hooks/opencode"

curl -fsSL "$BASE_URL/rtk.ts" --output rtk.ts
