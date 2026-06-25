#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq gnused
# Bump the POE2 tool derivations to their latest GitHub releases.
#   ./scripts/update-poe2-tools.sh

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

# Exiled Exchange 2 (AppImage, fetchurl -> file hash)
EE2_FILE="packages/exiled-exchange-2.nix"
EE2_LATEST_VER="$(curl --fail -s ${GITHUB_TOKEN:+-u ":$GITHUB_TOKEN"} "https://api.github.com/repos/Kvan7/Exiled-Exchange-2/releases/latest" | jq -r '.tag_name' | sed 's/^v//')"
EE2_CURRENT_VER="$(grep -oP 'version = "\K[^"]+' "$EE2_FILE")"

if [[ "$EE2_LATEST_VER" == "$EE2_CURRENT_VER" ]]; then
    echo "exiled-exchange-2 is up-to-date ($EE2_CURRENT_VER)"
else
    echo "Updating exiled-exchange-2 from $EE2_CURRENT_VER to $EE2_LATEST_VER"
    EE2_URL="https://github.com/Kvan7/Exiled-Exchange-2/releases/download/v${EE2_LATEST_VER}/Exiled-Exchange-2-${EE2_LATEST_VER}.AppImage"
    EE2_HASH="$(nix-hash --to-sri --type sha256 "$(nix-prefetch-url --type sha256 "$EE2_URL")")"
    sed -i "s#version = \".*\";#version = \"$EE2_LATEST_VER\";#g" "$EE2_FILE"
    sed -i "s#hash = \".*\"#hash = \"$EE2_HASH\"#g" "$EE2_FILE"
    echo "Updated exiled-exchange-2 to $EE2_LATEST_VER"
fi

# Path of Building (PoE2) (portable zip, fetchzip -> unpacked hash)
POB2_FILE="packages/path-of-building-poe2.nix"
POB2_LATEST_VER="$(curl --fail -s ${GITHUB_TOKEN:+-u ":$GITHUB_TOKEN"} "https://api.github.com/repos/PathOfBuildingCommunity/PathOfBuilding-PoE2/releases/latest" | jq -r '.tag_name' | sed 's/^v//')"
POB2_CURRENT_VER="$(grep -oP 'version = "\K[^"]+' "$POB2_FILE")"

if [[ "$POB2_LATEST_VER" == "$POB2_CURRENT_VER" ]]; then
    echo "path-of-building-poe2 is up-to-date ($POB2_CURRENT_VER)"
else
    echo "Updating path-of-building-poe2 from $POB2_CURRENT_VER to $POB2_LATEST_VER"
    POB2_URL="https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2/releases/download/v${POB2_LATEST_VER}/PathOfBuildingCommunity-PoE2-Portable.zip"
    POB2_HASH="$(nix-hash --to-sri --type sha256 "$(nix-prefetch-url --unpack --type sha256 "$POB2_URL")")"
    sed -i "s#version = \".*\";#version = \"$POB2_LATEST_VER\";#g" "$POB2_FILE"
    sed -i "s#hash = \".*\"#hash = \"$POB2_HASH\"#g" "$POB2_FILE"
    echo "Updated path-of-building-poe2 to $POB2_LATEST_VER"
fi
