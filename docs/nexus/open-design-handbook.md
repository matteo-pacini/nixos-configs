# Open Design Handbook

Initial (one-time) setup for the [open-design](https://github.com/nexu-io/open-design)
daemon on Nexus. The service itself is declarative — these are the manual steps
Nix can't do: the Claude Code login, the LAN DNS record, and verification.

## Quick Reference

| Item | Value |
|------|-------|
| Web UI | `https://design.matteopacini.me` (LAN-only) |
| Daemon | `127.0.0.1:7457` (loopback) |
| Bundled web Caddy | `127.0.0.1:5174` (loopback, plain HTTP) |
| Front TLS proxy | `services.caddy` vhost in `hosts/Nexus/services/caddy.nix` |
| Service config | `hosts/Nexus/services/open-design.nix` |
| Service user | `open-design` (system user) |
| Data dir / `$HOME` | `/var/lib/open-design` |
| Claude session | `/var/lib/open-design/.claude/.credentials.json` |
| systemd units | `open-design.service`, `open-design-web.service` |

---

## 1. Prerequisites

The config (`open-design.nix` + the Caddy vhost + the flake input) is merged and
switched:

```bash
nix build ".#nixosConfigurations.Nexus.config.system.build.toplevel"
sudo nixos-rebuild switch --flake .#Nexus
```

`claude` is on the system profile (`environment.systemPackages`), so the daemon
can find it on its `PATH`. The daemon's `PATH` does **not** include any per-user
Home Manager profile — matteo's own `claude` is invisible to it.

---

## 2. Add the LAN DNS record

There is **no public A record** for `design.matteopacini.me`. Add a local
override on the LAN resolver (router / Pi-hole / Blocky):

```
design.matteopacini.me  →  <Nexus LAN IP>
```

The cert is still minted via the Route53 DNS-01 challenge (the `_acme-challenge`
TXT record in the public `matteopacini.me` zone) — that is independent of the A
record, so the service stays unreachable and unresolvable from outside the LAN.

---

## 3. One-time Claude Code login (subscription, not API billing)

The daemon spawns the genuine `claude` binary, which authenticates with its own
`/login` session. Run the login **as the `open-design` user with the matching
`$HOME`** so the credentials land where the daemon reads them at runtime:

```bash
sudo -u open-design env HOME=/var/lib/open-design claude
# inside the TUI: /login → open the printed URL on another machine, paste the code
```

Leave `ANTHROPIC_API_KEY` **unset** (do not put it in an `environmentFile`). The
daemon strips that var when spawning the `claude` adapter so it falls back to the
subscription OAuth session — but keeping it unset avoids any ambiguity, and a set
key would be billed against pay-as-you-go API credits instead.

> Running the real `claude` binary on your own subscription is ordinary CLI use.
> Do **not** inject a subscription OAuth token into a third-party tool — that is
> the path Anthropic prohibits.

---

## 4. Verify

```bash
# Credentials written to the daemon's HOME
sudo -u open-design ls -l /var/lib/open-design/.claude/.credentials.json

# Services healthy
systemctl status open-design open-design-web

# Cert issued (DNS-01 via Route53)
journalctl -u caddy --since "10 min ago" | grep -i "design.matteopacini.me"

# From a LAN client
curl -I https://design.matteopacini.me
```

Restart the daemon after the first login so it picks up the new session:

```bash
sudo systemctl restart open-design
```

---

## 5. (Optional) OpenRouter / other BYOK keys

open-design has no first-class OpenRouter integration. Route through its generic
**OpenAI-compatible** provider in **Settings → Execution mode → "OpenAI API"**:

| Field | Value |
|-------|-------|
| Base URL | `https://openrouter.ai/api/v1` |
| API key | your OpenRouter key |
| Model ID | `vendor/slug`, e.g. `anthropic/claude-3.5-sonnet` |

For keys that must persist, store them in an agenix secret and point the module's
`services.open-design.environmentFile` at it (decrypted to `/run/agenix/...`),
`KEY=VALUE` per line. Never put keys directly in the Nix store (world-readable).

---

## Notes

- This is a NixOS system service (`nixosModules.open-design`), so it starts at
  boot — **no `users.users.<u>.linger`** is needed (that only applies to the
  Home Manager / `systemd --user` variant).
- The daemon and bundled Caddy both bind loopback; the front `services.caddy`
  vhost terminates TLS and gates access by source IP (`remote_ip` allowlist:
  LAN + tailnet). Do not set `OD_BIND_HOST` or `openFirewall` on the module.
- `webFrontend.allowedOrigins` must list `https://design.matteopacini.me`, or the
  daemon's origin check returns 403 on write actions.
- "No agents detected" in the UI → `claude` is not on the daemon's `PATH`.
  Confirm `environment.systemPackages` has `pkgs.claude-code`, then restart
  `open-design`.
- AWS Route53 credentials for the cert are shared with the DDNS service via the
  existing `nexus/route53-env` agenix secret — nothing new to provision.
- **Backups:** all state lives under `/var/lib/open-design` (the systemd sandbox
  confines writes there). The nightly `backupJob` stops `open-design` to quiesce
  `app.sqlite`, rsyncs the dir into `/diskpool/configuration/open-design`, and the
  restic `config` repo pushes it off-site to B2. If the generated `artifacts/` /
  `frames/` grow large, exclude them via `configExcludes` in `backup.nix`.
