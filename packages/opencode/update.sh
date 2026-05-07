#!/usr/bin/env bash
# Refresh the vendored opencode derivation from nixpkgs master.
# Overwrites package.nix — any local edits are lost.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/op/opencode"

curl -fsSL "$BASE_URL/package.nix" --output package.nix
