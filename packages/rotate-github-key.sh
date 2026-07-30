# Sourced by writeShellApplication (packages/rotate-github-key.nix), which
# provides the shebang, `set -euo pipefail`, and the runtime PATH.

usage() {
  cat <<'EOF'
rotate-github-key [--dry-run] [--host <FlakeHost>]

Rotates this host's GitHub SSH key (~/.ssh/github):
  1. generates a fresh ed25519 keypair (old key kept until verified)
  2. uploads the new public key to GitHub (authentication + signing)
  3. verifies SSH auth against github.com
  4. deletes this host's old GitHub-side keys (title: github-<host>)
  5. on signing hosts: updates allowedSignersContent in nixos-configs,
     commits, pushes, rebuilds

Options:
  --dry-run   run read-only checks, print mutating commands instead of running them
  --host      override host detection (BrightFalls|Nexus|NightSprings|WorkLaptop)

Requires a gh token with admin:public_key (plus admin:ssh_signing_key on
signing hosts):
  gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key
EOF
}

DRY_RUN=0
HOST_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --host)
      [ $# -ge 2 ] || { echo "--host needs a value" >&2; exit 1; }
      HOST_OVERRIDE="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@"
  fi
}

# Darwin hostnames are not managed by nix — if detection fails there, use --host.
name="${HOST_OVERRIDE:-$(uname -n)}"
name="${name%%.*}"
case "${name,,}" in
  brightfalls)
    FLAKE_HOST=BrightFalls
    NIXFILE="hosts/BrightFalls/users/matteo/git.nix"
    ;;
  nightsprings)
    FLAKE_HOST=NightSprings
    NIXFILE="hosts/NightSprings/users/matteo/git.nix"
    ;;
  worklaptop)
    FLAKE_HOST=WorkLaptop
    NIXFILE="hosts/WorkLaptop/users/matteo.pacini/git.nix"
    ;;
  nexus)
    FLAKE_HOST=Nexus
    NIXFILE="hosts/Nexus/users/matteo/git.nix"
    ;;
  *)
    if [ -n "$HOST_OVERRIDE" ]; then
      echo "unknown --host '$name' — valid values: BrightFalls | Nexus | NightSprings | WorkLaptop" >&2
    else
      echo "hostname '$name' (detected via uname -n) does not match a known host" >&2
      echo "recover with: rotate-github-key --host <BrightFalls|Nexus|NightSprings|WorkLaptop>" >&2
    fi
    exit 1
    ;;
esac

REPO="${NIXOS_CONFIGS_REPO:-$HOME/Repositories/nixos-configs}"
KEY="$HOME/.ssh/github"
TITLE="github-${FLAKE_HOST,,}"

echo "host: $FLAKE_HOST | key: $KEY | github key title: $TITLE"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN — no changes will be made"
fi

# Preflight: token scopes. Parses `gh auth status` text; the scope line format
# has shifted between gh versions — if this gate misfires, verify manually.
status="$(gh auth status 2>&1)" || {
  printf '%s\n' "$status" >&2
  echo "gh is not authenticated — run: gh auth login" >&2
  exit 1
}
scopes=(admin:public_key)
if [ -n "$NIXFILE" ]; then
  scopes+=(admin:ssh_signing_key)
fi
for scope in "${scopes[@]}"; do
  if ! grep -qF "$scope" <<<"$status"; then
    echo "gh token is missing scope '$scope'" >&2
    echo "run: gh auth refresh -h github.com -s admin:public_key,admin:ssh_signing_key" >&2
    exit 1
  fi
done

# Collect this host's current GitHub-side key ids (deleted only after the new
# key is uploaded and verified — no auth-less window).
old_auth_ids="$(gh api user/keys --jq ".[] | select(.title == \"$TITLE\") | .id")"
old_sign_ids=""
if [ -n "$NIXFILE" ]; then
  old_sign_ids="$(gh api user/ssh_signing_keys --jq ".[] | select(.title == \"$TITLE\") | .id")"
fi
if [ -z "$old_auth_ids$old_sign_ids" ]; then
  echo "note: no GitHub keys titled '$TITLE' — keys predating this tool must be deleted manually:"
  echo "  gh api user/keys --jq '.[] | [.id, .title] | @tsv'"
  echo "  gh api user/ssh_signing_keys --jq '.[] | [.id, .title] | @tsv'"
fi

restore_old_key() {
  if [ -f "$KEY.old" ]; then
    mv "$KEY.old" "$KEY"
    [ ! -f "$KEY.old.pub" ] || mv "$KEY.old.pub" "$KEY.pub"
  fi
}

run mkdir -p -m 700 "$HOME/.ssh"
if [ -f "$KEY" ]; then
  run mv "$KEY" "$KEY.old"
fi
if [ -f "$KEY.pub" ]; then
  run mv "$KEY.pub" "$KEY.old.pub"
fi
run ssh-keygen -t ed25519 -N "" -C "$TITLE" -f "$KEY"

if [ "$DRY_RUN" -eq 1 ]; then
  new_pub="ssh-ed25519 <NEW-PUBLIC-KEY>"
else
  new_pub="$(cut -d' ' -f1,2 "$KEY.pub")"
fi

# Auth and signing are separate GitHub-side resources; the same public key
# must be uploaded once per type.
run gh ssh-key add "$KEY.pub" --title "$TITLE" --type authentication
if [ -n "$NIXFILE" ]; then
  run gh ssh-key add "$KEY.pub" --title "$TITLE" --type signing
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] ssh -T -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new git@github.com"
else
  # ssh -T exits 1 against github.com even on success — match the banner.
  # accept-new: don't hang on fresh installs with an empty known_hosts.
  ssh_out="$(ssh -T -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)"
  if ! grep -q "successfully authenticated" <<<"$ssh_out"; then
    printf '%s\n' "$ssh_out" >&2
    echo "verification FAILED — restoring previous key. The new key was left on GitHub for inspection." >&2
    restore_old_key
    exit 1
  fi
  echo "new key verified against github.com"
fi

while IFS= read -r id; do
  [ -n "$id" ] || continue
  run gh api -X DELETE "user/keys/$id"
done <<<"$old_auth_ids"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  run gh api -X DELETE "user/ssh_signing_keys/$id"
done <<<"$old_sign_ids"
run rm -f "$KEY.old" "$KEY.old.pub"

if [ -n "$NIXFILE" ]; then
  if [ ! -d "$REPO/.git" ]; then
    echo "nixos-configs repo not found at $REPO (set NIXOS_CONFIGS_REPO)" >&2
    exit 1
  fi
  cd "$REPO" || exit 1
  # --autostash: tolerate a dirty tree (unrelated WIP); only $NIXFILE is committed
  run git pull --rebase --autostash
  # allowedSignersContent holds a single '* ssh-ed25519 <base64>' line.
  # sed -i.bak: BSD sed (darwin) requires the suffix argument.
  run sed -i.bak "s|\\* ssh-ed25519 [A-Za-z0-9+/=]*|* $new_pub|" "$NIXFILE"
  run rm "$NIXFILE.bak"
  if [ "$DRY_RUN" -eq 0 ] && git diff --quiet -- "$NIXFILE"; then
    echo "expected $NIXFILE to change but it did not — aborting before commit" >&2
    exit 1
  fi
  run git add "$NIXFILE"
  run git commit -m "chore(${FLAKE_HOST,,}): rotate github ssh key"
  run git push
  # Rebuild only refreshes the local allowed_signers file (verification);
  # signing itself already uses the new key via the unchanged ~/.ssh paths.
  if [ "$(uname)" = "Darwin" ]; then
    run sudo darwin-rebuild switch --flake ".#$FLAKE_HOST"
  else
    run sudo nixos-rebuild switch --flake ".#$FLAKE_HOST"
  fi
fi
