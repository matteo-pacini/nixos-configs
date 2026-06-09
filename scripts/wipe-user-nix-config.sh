#!/bin/sh
# Wipe stale per-user nix/attic config that shadows the system
# (flake-managed) nix configuration — leftovers from `attic use` in the
# fly.dev era. A plain `substituters =` / `netrc-file =` in
# ~/.config/nix/nix.conf silently overrides the flake-provided cache
# settings for that user (and for root, all sudo rebuilds).
#
# Run once per host as your login user:
#   ./scripts/wipe-user-nix-config.sh
# Or remotely:
#   ssh -t <host> 'sh -s' < scripts/wipe-user-nix-config.sh
set -eu

case "$(uname -s)" in
  Darwin) ROOT_HOME=/var/root ;;
  *) ROOT_HOME=/root ;;
esac

echo "== user: $HOME =="
rm -rfv "$HOME/.config/nix/nix.conf" "$HOME/.config/nix/netrc" "$HOME/.config/attic"

echo "== root: $ROOT_HOME =="
# explicit root home: $HOME under sudo is unreliable on macOS
sudo rm -rfv "$ROOT_HOME/.config/nix/nix.conf" "$ROOT_HOME/.config/nix/netrc" "$ROOT_HOME/.config/attic"

echo "verify: nix config show | grep -E '^substituters|^netrc'"
