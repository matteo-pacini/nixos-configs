# Auto-deploy handbook

Merges to `master` reach the machines without anyone running `nixos-rebuild` or `darwin-rebuild`. Each enrolled host runs [comin](https://github.com/nlewo/comin), which polls this (public) repository and deploys its own configuration.

## How it works

```
PR merged ─► master ─► build.yml builds all 5 configs, pushes closures to attic
                                 │ all green
                                 ▼
                        deploy job: git push $GITHUB_SHA → refs/heads/deploy
                                 │
          ┌──────────────────────┼──────────────────────┐
          ▼                      ▼                      ▼
   Nexus (comin)         BrightFalls (comin)    NightSprings (comin)
   poll every 60 s, evaluate own config, substitute from attic, activate
```

- Hosts track the **`deploy`** branch, never `master`. `deploy` only moves after every matrix entry in `.github/workflows/build.yml` is green, so a host only deploys a commit whose closure is already in attic. A failed build anywhere holds back every host.
- The deploy job uses a plain `git push`, which is fast-forward only. A slower, older run finishing last is rejected instead of rolling hosts back. If `master` is ever rewritten, the job fails and `deploy` must be moved by hand.
- comin is pinned to a release tag in `flake.nix` (`comin.url`), so the weekly flake update cannot pull in an unreleased comin. A broken comin cannot deploy its own fix; that has to be done with a manual rebuild.

## Per-host behaviour

| Host | Operation | When it takes effect | Notifications |
|---|---|---|---|
| Nexus | `boot` | Next reboot, which is always manual | Telegram: staged, failed, daily reminder after 7 days |
| BrightFalls | `boot` | Next reboot. A merge made while it is off is staged at the next power-on and runs from the one after. | Desktop: reboot required. Telegram: `[BrightFalls]` failures |
| NightSprings | `switch` | Immediately (Darwin has no `boot`) | Telegram: `[NightSprings]` failures |
| CauldronLake | not enrolled | Not in the SSH mesh yet | — |
| WorkLaptop | not enrolled | Company machine, kept manual | — |

`boot` means services, secrets (agenix decrypts at activation) and Home Manager changes all wait for the reboot. Kernel, NVIDIA module and userspace driver always change together, which is why Linux hosts use it.

## Notifications

All messages go to the Telegram group in `secrets/nexus/janitor.env.age` (`BOT_TOKEN`, `CHANNEL_ID`) through `telegram-notify` (`overlays/shared.nix`). Messages that need action mention `@matteopacini`. Nexus messages have no prefix; other hosts set `custom.autoDeploy.telegramPrefix`.

| Message | Sent when |
|---|---|
| `🚨 … deploy of <sha> failed (<subject>): <error>` | Activation of a built generation fails, on any enrolled host |
| `📦 … <sha> staged (<subject>), reboot pending` | Nexus only: a deployment succeeds and the staged system differs from the booted one. Commits that do not change Nexus stay silent. |
| `⏰ … staged for N days, reboot pending` | Nexus only: `comin-reboot-reminder.timer`, daily at 09:00, once the staged generation is 7+ days old |

The hook lives in `modules/shared/comin-hook.nix`. Text that comes from git or comin is escaped for Telegram's legacy Markdown (`_ * \` [`); an unescaped one makes Telegram reject the message, and `telegram-notify` does not report the error.

**Not covered:** comin only runs the hook after a deployment. An evaluation or build failure on the host itself (attic unreachable, timeout) produces no Telegram message. CI having built the same commit makes this rare. Check `comin status` when a host seems stuck.

## Day-to-day

```bash
# What comin has fetched, built and deployed, and whether a reboot is needed
comin status

# Nexus: apply a staged deployment
sudo systemctl reboot

# Logs
journalctl -u comin -f            # NixOS
tail -f /var/log/comin.log        # Darwin
```

**Trying a change on one host without merging:** push it to `testing-<Host>` (for example `testing-Nexus`). comin deploys it with `test`, so it is live until the next reboot and never becomes the boot default. Then merge it to `master` as usual and delete the branch.

**Manual rebuilds** still work, but `deploy` is the source of truth: the next commit comin deploys replaces whatever was activated by hand.

**Rolling back:** previous generations stay in the boot menu. comin keeps the last 3 boot entries it created, plus the booted generation, under the `comin` profile (`/nix/var/nix/profiles/system-profiles/comin`). On Nexus this needs the BMC console.

## Enrolling a host

1. Add the host's key to `"nexus/janitor.env.age".publicKeys` in `secrets/secrets.nix`, then re-encrypt that one file to the new recipient list. Only host keys can decrypt it, and `agenix --rekey` on Nexus would also try (and fail on) secrets Nexus cannot read, so pipe it through `age` on Nexus instead. Copy `janitor.env.age` and a `recipients.txt` (one public key per line, matching `secrets.nix`) to a private directory there and run:
   ```bash
   A=$(nix build nixpkgs#age --no-link --print-out-paths)/bin/age
   sudo $A -d -i /etc/ssh/ssh_host_ed25519_key janitor.env.age | $A -R recipients.txt -o janitor.env.age.new
   ```
   Check the result has one `-> ssh-ed25519` stanza per recipient, copy it back over `secrets/nexus/janitor.env.age`, and delete the copies on Nexus.
2. Declare `age.secrets."nexus/janitor.env"` for the host in `flake.nix`.
3. Enable the module in `hosts/<Host>/default.nix`:
   ```nix
   custom.autoDeploy = {
     enable = true;
     telegramEnvFile = config.age.secrets."nexus/janitor.env".path;
     telegramPrefix = "[<Host>] ";
   };
   ```
   Darwin hosts also need `services.comin.hostname = "<Host>";`, because `networking.hostName` is unset there and comin uses it to pick `darwinConfigurations.<Host>`.
4. The first activation has to be manual (`nixos-rebuild` / `darwin-rebuild switch`); comin takes over from then on.

## Files

| What | Where |
|---|---|
| NixOS module (`custom.autoDeploy`, reminder timer) | `modules/nixos/auto-deploy.nix` |
| Darwin module | `modules/darwin/auto-deploy.nix` |
| Post-deployment hook | `modules/shared/comin-hook.nix` |
| `telegram-notify` | `overlays/shared.nix` |
| CI gate (`deploy` job) | `.github/workflows/build.yml` |
