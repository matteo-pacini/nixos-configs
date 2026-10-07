# Sourced by writeShellApplication (packages/ssh-mesh-renew.nix), which
# provides the shebang, `set -euo pipefail`, and the runtime PATH.

usage() {
  cat <<'EOF'
ssh-mesh-renew [--force | --status]

Rotates this host's SSH mesh key (~/.ssh/mesh) and certificate
(~/.ssh/mesh-cert.pub) by sending a fresh public key to the signer
(ssh aliases mesh-ca, then mesh-ca-ts), authenticated by the current cert.

Does nothing while the current cert has more than 23 days left, so it is
safe to run daily and at login.

Options:
  --force    renew regardless of remaining validity
  --status   print the current certificate
EOF
}

KEY="$HOME/.ssh/mesh"
CERT="$KEY-cert.pub"
RENEW_BELOW_DAYS=23

FORCE=0
case "${1:-}" in
  "") ;;
  --force) FORCE=1 ;;
  --status)
    ssh-keygen -L -f "$CERT"
    exit 0
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ ! -f "$CERT" ]; then
  if [ ! -f "$KEY" ]; then
    install -d -m 700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N "" -C "mesh" -f "$KEY"
  fi
  cat >&2 <<EOF
no mesh certificate yet ($CERT). Bootstrap it once from Nexus:
  1. copy $KEY.pub to Nexus
  2. on Nexus: sudo -u sshca ssh-mesh-sign --host <principal> < mesh.pub > mesh-cert.pub
  3. copy mesh-cert.pub back to $CERT
See docs/ssh-mesh-handbook.md.
EOF
  exit 1
fi

# "Valid: from 2026-10-07T08:28:00 to 2026-11-06T08:33:00", local time.
valid_to="$(ssh-keygen -L -f "$CERT" | sed -n 's/^ *Valid: from [^ ]* to \(.*\)$/\1/p')"
expires="$(date -d "$valid_to" +%s)"
now="$(date +%s)"
if [ "$expires" -le "$now" ]; then
  echo "mesh certificate expired at $valid_to — bootstrap again (see --help)" >&2
  exit 1
fi
if [ "$FORCE" -eq 0 ] && [ $((expires - now)) -gt $((RENEW_BELOW_DAYS * 86400)) ]; then
  echo "mesh certificate valid until $valid_to — nothing to do"
  exit 0
fi

rm -f "$KEY.new" "$KEY.new.pub" "$KEY.new-cert.pub"
trap 'rm -f "$KEY.new" "$KEY.new.pub" "$KEY.new-cert.pub"' EXIT
ssh-keygen -q -t ed25519 -N "" -C "mesh" -f "$KEY.new"

signed=0
for alias in mesh-ca mesh-ca-ts; do
  if ssh -T -o BatchMode=yes -o ConnectTimeout=10 "$alias" <"$KEY.new.pub" >"$KEY.new-cert.pub"; then
    signed=1
    break
  fi
done
[ "$signed" -eq 1 ] || { echo "could not reach the signer via mesh-ca or mesh-ca-ts" >&2; exit 1; }

# The cert must certify the key just generated, not something else.
cert_fp="$(ssh-keygen -L -f "$KEY.new-cert.pub" | sed -n 's/^ *Public key: [A-Z0-9-]* \(SHA256:[^ ]*\).*/\1/p')"
key_fp="$(ssh-keygen -l -f "$KEY.new.pub" | cut -d' ' -f2)"
[ -n "$cert_fp" ] && [ "$cert_fp" = "$key_fp" ] || { echo "signer returned an invalid certificate" >&2; exit 1; }

mv "$KEY.new" "$KEY"
mv "$KEY.new.pub" "$KEY.pub"
mv "$KEY.new-cert.pub" "$CERT"
trap - EXIT
ssh-keygen -L -f "$CERT" | grep -E 'Key ID|Valid'
