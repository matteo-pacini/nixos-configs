#!/usr/bin/env bash
# Refresh the vendored claude-code derivation from nixpkgs master.
# Overwrites both package.nix and manifest.json — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/cl/claude-code"

curl -fsSL "$BASE_URL/package.nix"   --output package.nix
curl -fsSL "$BASE_URL/manifest.json" --output manifest.json
