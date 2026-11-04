# Auto-deploy handbook

Merges to `master` reach the machines without anyone running `nixos-rebuild` or `darwin-rebuild`. Each enrolled host runs [comin](https://github.com/nlewo/comin), which polls this (public) repository and deploys its own configuration.

## How it works

```
PR merged ─► master ─► build.yml builds all 5 configs, pushes closures to attic
                                 │ all green
                                 ▼
                        deploy job: git push $GITHUB_SHA → refs/heads/deploy
                                 │
       ┌───────────────┬─────────┴─────┬───────────────┬───────────────┐
       ▼               ▼               ▼               ▼               ▼
     Nexus      BrightFalls    NightSprings   CauldronLake     WorkLaptop   (each runs comin)
   poll every 60 s, evaluate own config, substitute from attic, activate
```

- Hosts track the **`deploy`** branch, never `master`. `deploy` only moves after every matrix entry in `.github/workflows/build.yml` is green, so a host only deploys a commit whose closure is already in attic. A failed build anywhere holds back every host.
- The deploy job uses a plain `git push`, which is fast-forward only. A slower, older run finishing last is rejected instead of rolling hosts back. If `master` is ever rewritten, the job fails and `deploy` must be moved by hand.
- comin is pinned to a release tag in `flake.nix` (`comin.url`), so the weekly flake update cannot pull in an unreleased comin. A broken comin cannot deploy its own fix; that has to be done with a manual rebuild.

## Per-host behaviour

| Host | Operation | Confirmed | When it takes effect | Notifications |
|---|---|---|---|---|
| Nexus | `boot` | yes | As the mode says (below); a staged one at the next reboot, which is always manual | None |
| BrightFalls | `boot` | yes | As the mode says (below) | Desktop: reboot required |
| NightSprings | `switch` | yes | As the mode says (below); Darwin has no `boot` | None |
| CauldronLake | `boot` | no | Next reboot. A merge made while it is off or asleep is staged once it is back online. | Desktop: reboot required |
| WorkLaptop | `switch` | yes | As the mode says (below); Darwin has no `boot` | None |

Deploys send no messages: the herdr Deploy panel shows each host's state (held, staged, reboot pending, failed). Elsewhere, `comin status` on the host.

### Confirmed deployments

With `custom.autoDeploy.confirm`, comin fetches and builds each new `deploy` commit (from attic), then holds it: `comin status` shows a deploy confirmation waiting. Nothing is activated until `comin-deploy` releases it. This also holds `testing-<Host>` pushes.

```bash
comin-deploy boot       # stage the held generation for the next boot (NixOS only)
comin-deploy switch     # make the newest system live: the held generation, or with
                        # nothing held, the one staged for boot. On NixOS it is staged
                        # with boot first, then comin resubmits it with switch
comin-deploy mode       # print the mode
comin-deploy mode boot  # manual | boot | switch (Darwin: manual | switch)
```

If the new system changes a switch-inhibitor, comin stages it for boot instead of switching; `comin-deploy` reports that and never forces it. Every comin call has a timeout and survives comin restarting itself, which it does after a deployment that changes its own unit.

The mode (`/var/lib/comin-deploy/mode`, writable by `wheel` / `admin`) decides what happens without anyone: `manual` (the default, also when the file is missing) waits; `boot` and `switch` are released that way by `comin-deploy auto`, which a timer (systemd on NixOS, launchd on Darwin, log in `/var/log/comin-deploy.log`) runs every minute. In every mode, `auto` also releases a held system that equals the staged one: comin holds commits that leave a host alone, and the same commit again after a restart. No sudo is needed: comin's socket is world-writable and the root daemon does the activation.

The herdr Deploy panel shows a held host as **pending**. Right-click its row for Switch now (asks first), Schedule for next boot (both hidden while comin is busy or suspended), Check diff (`dix diff` of `/run/current-system` against the newest system comin has for the host, held, built or staged; any enrolled host) and the three modes. A host with a boot deployment that is not running yet also gets Switch now. After a live switch that changed the kernel, the row shows **Reboot (kernel)**.


`boot` means services, secrets (agenix decrypts at activation) and Home Manager changes all wait for the reboot. Kernel, NVIDIA module and userspace driver always change together, which is why Linux hosts use it.

## Day-to-day

```bash
# What comin has fetched, built and deployed, and whether a reboot is needed
comin status

# Confirmed hosts: release what comin is holding
comin-deploy switch

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

1. Enable the module in `hosts/<Host>/default.nix`:
   ```nix
   custom.autoDeploy = {
     enable = true;
     confirm = true; # hold each commit for comin-deploy / the herdr panel
   };
   ```
   Darwin hosts also need `services.comin.hostname = "<Host>";`, because `networking.hostName` is unset there and comin uses it to pick `darwinConfigurations.<Host>`.
2. The first activation has to be manual (`nixos-rebuild` / `darwin-rebuild switch`); comin takes over from then on.

## Files

| What | Where |
|---|---|
| NixOS module (`custom.autoDeploy`) | `modules/nixos/auto-deploy.nix` |
| Darwin module | `modules/darwin/auto-deploy.nix` |
| `comin-deploy` (confirmed deployments, modes) | `modules/shared/comin-deploy.nix` |
| CI gate (`deploy` job) | `.github/workflows/build.yml` |
