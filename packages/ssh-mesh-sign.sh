# Sourced by writeShellApplication (hosts/Nexus/services/ssh-ca.nix), which
# provides the shebang, `set -euo pipefail`, the runtime PATH and
# MESH_CA_KEY / MESH_CA_PUB / MESH_PRINCIPALS.

usage() {
  cat <<'EOF'
ssh-mesh-sign [--host <principal>]

Reads one ed25519 public key on stdin and writes a mesh user certificate
to stdout.

Over SSH (ForceCommand for the sshca user): the source host is the key ID
of the certificate the caller authenticated with. Arguments are ignored.

Locally (bootstrap, run as sshca): --host names the source host.
  sudo -u sshca ssh-mesh-sign --host worklaptop < mesh.pub > mesh-cert.pub
EOF
}

die() {
  echo "ssh-mesh-sign: $*" >&2
  logger -t ssh-mesh-sign "refused: $*" || true
  exit 1
}

if [ -n "${SSH_USER_AUTH:-}" ]; then
  # sshd already checked the cert against TrustedUserCAKeys; re-checking the
  # CA here keeps the signer correct even if sshca ever accepts other keys.
  auth="$(grep -m1 -E '^publickey [a-z0-9-]+-cert-v01@openssh\.com ' "$SSH_USER_AUTH")" ||
    die "caller did not authenticate with a certificate"
  info="$(cut -d' ' -f2,3 <<<"$auth" | ssh-keygen -L -f -)"
  key_id="$(sed -n 's/^ *Key ID: "\(.*\)"$/\1/p' <<<"$info")"
  signing_ca="$(sed -n 's/^ *Signing CA: [A-Z0-9-]* \(SHA256:[^ ]*\).*/\1/p' <<<"$info")"
  [ "$signing_ca" = "$(ssh-keygen -l -f "$MESH_CA_PUB" | cut -d' ' -f2)" ] ||
    die "caller cert not signed by the mesh CA"
else
  case "${1:-}" in
    --host)
      [ $# -eq 2 ] || { usage >&2; exit 1; }
      key_id="$2"
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
fi

principals="$(jq -r --arg id "$key_id" '.[$id] // empty | join(",")' "$MESH_PRINCIPALS")"
[ -n "$principals" ] || die "unknown host '$key_id'"

pub="$(head -c 4096 | head -n1)"
[[ "$pub" =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*(\ .*)?$ ]] || die "stdin is not an ed25519 public key"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$pub" >"$tmp/key.pub"
ssh-keygen -l -f "$tmp/key.pub" >/dev/null || die "stdin is not a valid public key"

serial="$(date +%s)"
# -5m: tolerate client clocks slightly behind Nexus.
ssh-keygen -q -s "$MESH_CA_KEY" -I "$key_id" -n "$principals" -V -5m:+30d -z "$serial" "$tmp/key.pub"
cat "$tmp/key-cert.pub"
logger -t ssh-mesh-sign "signed key_id=$key_id serial=$serial principals=$principals" || true
