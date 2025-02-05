#! /usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq gnused coreutils

# Script to update Passbolt Firefox extension version and hash in firefox.nix

cd "$(dirname "$0")" || exit 1

# Constants
ADDON_ID="passbolt@passbolt.com"
FIREFOX_NIX_PATH="../hosts/WorkLaptop/users/admin/firefox.nix"

# Fetch latest version and file ID from Mozilla Add-ons API
LATEST_INFO=$(curl -s "https://addons.mozilla.org/api/v5/addons/addon/${ADDON_ID}/")
LATEST_VERSION=$(echo "$LATEST_INFO" | jq -r '.current_version.version')

DOWNLOAD_URL=$(echo "$LATEST_INFO" | jq -r '.current_version.file.url')

# Fetch new hash using nix-hash for SRI format
NEW_HASH=$(nix-hash --to-sri --type sha256 "$(nix-prefetch-url --type sha256 "$DOWNLOAD_URL")")

# Update firefox.nix with new version and hash
sed -i \
    -e "s/version = \".*\";/version = \"${LATEST_VERSION}\";/" \
    -e "s/hash = \".*\";/hash = \"${NEW_HASH}\";/" \
    "$FIREFOX_NIX_PATH"

echo "Updated firefox.nix with version ${LATEST_VERSION} and hash ${NEW_HASH}."
