# SSH mesh handbook

Host-to-host SSH is authorized by an OpenSSH **user certificate authority**, not by per-host `authorized_keys`. The access matrix, addresses and host keys live in `lib/ssh-mesh.nix`.

## How it works

- Each host has one client key, `~/.ssh/mesh`, and a certificate, `~/.ssh/mesh-cert.pub`. ssh loads the certificate automatically next to the key.
- The certificate's **key ID** is the source host (`worklaptop`). Its **principals** are the destinations that host may reach, plus `renew`.
- Each destination's sshd trusts the CA (`TrustedUserCAKeys`). It accepts only its own principal for `matteo` (`/etc/ssh/authorized_principals.d/matteo`).
- Certificates are valid for 30 days. `ssh-mesh-renew` runs daily: a systemd user timer on Linux, a launchd agent on macOS. It rotates the key once fewer than 23 days remain, so in practice the key changes about weekly.
- Renewal logs in as `sshca@nexus` (ssh alias `mesh-ca`, fallback `mesh-ca-ts`) with the current certificate. The `sshca` user is locked to `ForceCommand ssh-mesh-sign`. The signer reads the caller's key ID from the certificate it authenticated with (`ExposeAuthInfo`). It looks up that host's principals in the matrix and signs the new public key piped on stdin. Callers cannot choose their own principals, and any command they send is ignored.

| Source | May reach |
|---|---|
| Nexus | BrightFalls, NightSprings |
| BrightFalls | Nexus, NightSprings |
| NightSprings | Nexus, BrightFalls |
| WorkLaptop | Nexus, BrightFalls (runs no sshd) |

Aliases: `nexus`, `brightfalls` and `nightsprings` (LAN), plus `-ts` variants (Tailscale). Each source host gets only the aliases it may use.

Outside the mesh:
- The BrightFalls initrd unlock (`brightfalls-stage1`, `~/.ssh/brightfalls`) keeps static keys.
- Pixel and CauldronLake (debora's sshfs) keep static `authorized_keys` on Nexus.

## Changing who can reach what

1. Edit `allow` in `lib/ssh-mesh.nix`.
2. Rebuild **Nexus**. The signer's principal table is baked in at build time.
3. On each affected source host, run `ssh-mesh-renew --force` to pick up the new principals.

Destinations don't need a rebuild, unless a host becomes a destination for the first time (it needs sshd and a principals file).

## Bootstrap a host (first certificate, or after expiry)

1. On the host, run `ssh-mesh-renew`. It creates `~/.ssh/mesh` if missing and prints these steps.
2. Copy the public key to Nexus. Use any working access: an old key, or LAN password login for `matteo`.
   ```bash
   scp ~/.ssh/mesh.pub nexus:/tmp/mesh-<host>.pub
   ```
3. On Nexus, sign it:
   ```bash
   sudo -u sshca ssh-mesh-sign --host <principal> < /tmp/mesh-<host>.pub > /tmp/mesh-<host>-cert.pub
   ```
4. Copy the certificate back:
   ```bash
   scp nexus:/tmp/mesh-<host>-cert.pub ~/.ssh/mesh-cert.pub
   ```
5. Run `ssh-mesh-renew --force` once. That proves self-renewal works.

`--host` is accepted only outside SSH (when `SSH_USER_AUTH` is unset), so remote callers can't use it.

Check a certificate with `ssh-mesh-renew --status`. On Nexus, `journalctl -t ssh-mesh-sign` shows each signing, and `journalctl -u sshd` shows the key ID of every login.

## Rotating the CA

The private key is `secrets/nexus/ssh-mesh-ca.age` (recipient: Nexus host key). A backup is kept in 1Password.

1. `ssh-keygen -t ed25519 -N "" -C ssh-mesh-ca -f mesh_ca`
2. Re-encrypt: `cd secrets && EDITOR="cp /path/to/mesh_ca" nix run --inputs-from .. agenix -- -e nexus/ssh-mesh-ca.age`. Update the 1Password backup.
3. Set `caPublicKey` in `lib/ssh-mesh.nix` to the contents of `mesh_ca.pub`.
4. Rebuild **all** mesh hosts. Every existing certificate stops working at that point, so bootstrap each host again.

To rotate without a gap, first deploy both CA public keys (`TrustedUserCAKeys` accepts several), re-sign every host with the new CA, then drop the old key.

## Adding a host

1. Add it to `hosts` in `lib/ssh-mesh.nix`:
   - `principal`: lowercase host name. It's both the cert key ID when the host connects out and the principal other hosts need to log into it.
   - `hostKey`: the contents of `/etc/ssh/ssh_host_ed25519_key.pub` on the new host. Mesh hosts pin it in `known_hosts`, and `secrets/secrets.nix` uses it as the host's agenix recipient.
   - `user`, `lan`, `tailscale`, `port`: only if the host runs sshd (accepts mesh logins). On macOS the port is 22, because launchd owns the socket and ignores `Port`.
2. Add it to `allow`: as a source with its destinations, and/or in other hosts' destination lists.
3. Set `custom.sshMesh = { enable = true; host = "<Host>"; }` at system level and `custom.ssh.mesh = { enable = true; host = "<Host>"; }` in Home Manager.
4. Rebuild **Nexus** first, so the signer knows the new key ID.
5. Rebuild the new host, then bootstrap it (see above, with `--host <principal>`).
6. Rebuild every other mesh host. They pick up the new host's pinned key, and destinations it may reach start accepting its principal. Sources that may reach it also need `ssh-mesh-renew --force` to get the new principal in their cert.

If the principal was revoked before (see below), remove it from `revokedKeyIds` first, or every cert issued under it is refused.

## Removing a host

Planned removal, such as a retired machine:

1. Delete it from `hosts`, from every `allow` list (as source and as destination), and from any `custom.sshMesh` / `custom.ssh.mesh` settings.
2. Rebuild **Nexus**. From then on the signer refuses that key ID, so the host can't renew.
3. Rebuild the other mesh hosts. That drops its pinned host key, its `Host` aliases, and, if it was a destination, the principal other certs carried for it. Run `ssh-mesh-renew --force` on the sources to get certs without it.
4. If it held agenix secrets, remove it from `secrets/secrets.nix` and re-key.

Its current cert stays valid until it expires (up to 30 days). If that's not acceptable, also revoke it.

## Revoking a host (lost or stolen device)

Every destination loads a key revocation list (`RevokedKeys`), built from `revokedKeyIds` in `lib/ssh-mesh.nix` by `lib/ssh-mesh-krl.nix`. Revoking a key ID rejects **every** cert ever issued under it, including the one the device holds now and any renewal it might get.

1. Add the principal to `revokedKeyIds`, e.g. `revokedKeyIds = [ "worklaptop" ];`.
2. Rebuild **Nexus first**. Its sshd then refuses the device's renewal logins as `sshca`, as well as normal logins.
3. Rebuild every other destination (BrightFalls, NightSprings). The KRL only protects hosts that have been rebuilt with it.
4. Also do the "Removing a host" steps, so the signer stops issuing certs for it.

Check that a cert is refused (NixOS hosts): `ssh-keygen -Q -f $(grep -oP 'RevokedKeys \K\S+' /etc/ssh/sshd_config) <cert>` prints `REVOKED`. sshd logs `revoked by file` when it rejects one.

To bring the device back later (recovered laptop, reinstall), remove it from `revokedKeyIds`, rebuild, and bootstrap it again with a fresh key.

Revocation covers mesh certs only. Static keys still in `authorized_keys` (Pixel, debora's sshfs key) are removed by editing those lists.
