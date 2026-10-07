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
2. Re-encrypt: `cd secrets && agenix -e nexus/ssh-mesh-ca.age`, then paste the new private key. Update the 1Password backup.
3. Set `caPublicKey` in `lib/ssh-mesh.nix` to the contents of `mesh_ca.pub`.
4. Rebuild **all** mesh hosts. Every existing certificate stops working at that point, so bootstrap each host again.

To rotate without a gap, first deploy both CA public keys (`TrustedUserCAKeys` accepts several), re-sign every host with the new CA, then drop the old key.

## Adding a host

1. Add it to `hosts` in `lib/ssh-mesh.nix`. Include `lan`, `tailscale`, `port` and `user` only if it runs sshd. On macOS the port is 22, because launchd owns the socket.
2. Add it to `allow`.
3. Set `custom.sshMesh = { enable = true; host = "<Host>"; }` at system level and `custom.ssh.mesh = { enable = true; host = "<Host>"; }` in Home Manager.
4. Rebuild Nexus, then the new host, then bootstrap it.
