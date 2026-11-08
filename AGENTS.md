# Agent Instructions

Multi-host NixOS/nix-darwin flake managing 6 build configurations (5 hosts + InstallerISO) across 5 physical hosts. Read `flake.nix` for host wiring and `README.md` for hardware details.

## Verification

```bash
# Build a NixOS configuration
nix build ".#nixosConfigurations.<Host>.config.system.build.toplevel"

# Build a Darwin configuration (requires macOS)
nix build ".#darwinConfigurations.<Host>.config.system.build.toplevel"

# Evaluate a foreign-platform configuration on your current machine
# Catches eval errors without needing the target platform's builder
# e.g. on Darwin, eval Linux configs; on Linux, eval Darwin configs
nix eval ".#nixosConfigurations.<Host>.config.system.build.toplevel" --raw 2>&1 | head -5
nix eval ".#darwinConfigurations.<Host>.config.system.build.toplevel" --raw 2>&1 | head -5

# Format
nix fmt
# Or manually:
nix run nixpkgs#nixfmt -- file.nix
```

Apply:
```bash
# NixOS
sudo nixos-rebuild switch --flake .#<Host>
# macOS
nix run nix-darwin -- switch --flake .#<Host>
```

## Workflow Gotchas

- **New `.nix` files must be `git add`ed before `nix build`.** The flake reads from the git store; untracked files are invisible.
- **Don't use `nix flake check` as a blanket validation.** It tries to build every output and fails on cross-platform configs from your current host. Use the targeted `nix build` (local platform) + `nix eval` (foreign platform) commands above instead.
- **`InstallerISO` fails pure eval by design.** It bakes the attic netrc token at build time and needs `--impure` + `ATTIC_NETRC_FILE=<decrypted netrc>`. Never add it to CI. See `hosts/InstallerISO/default.nix`.
- Commit style: semantic with host scope, e.g. `feat(nexus):`, `fix(brightfalls):`, `chore:`.
- CI builds all 5 configs on push to `master`. PRs run eval + diff against base. See `.github/workflows/`.
- **Nexus disk layout changes require doc updates.** If you add, remove, or renumber data disks in the Nexus pool, update `docs/nexus/diskpool-handbook.md` (inventory, diagram, totals, and append a row to the Changelog at the bottom) and `docs/nexus/disk-failure-handbook.md` (worked-example commands reference specific disk numbers).
- **Workarounds waiting on upstream carry a tag** in their comment, one per line: `WAIT-FOR <condition>: <ref>`. Conditions: `unstable` (PR or commit is in nixos-unstable), `merged` (PR/MR merged), `closed` (issue closed), `green` (Hydra job passing), `version` (`<attr> >= <ver>` in nixos-unstable), `manual` (`<url or none> (checked <date>)`). `WATCH: <url>` marks an upstream issue with no workaround here. Tag the code that has to change, not patch headers (editing a patch rebuilds its package). List them with `git grep -nE 'WAIT-FOR|WATCH:'`.
- **No closing keywords before upstream refs** in commit messages or PR bodies. GitHub closes the target when a commit reaches `master`, or a PR whose body has one is merged: `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved` (any case, optional colon) followed by `#N`, `owner/repo#N` or an issue/PR URL. The owner can write to NixOS/nixpkgs, so "the hash fix NixOS/nixpkgs#582675" closed that nixpkgs PR. Write "waits on NixOS/nixpkgs#582675, the hash fix" instead, or put the ref in backticks.

## Hosts

| Host | Platform | User | Notes |
|------|----------|------|-------|
| BrightFalls | x86_64-linux | matteo | Gaming PC |
| Nexus | x86_64-linux | matteo | Headless server |
| CauldronLake | x86_64-linux | **debora** | Razer laptop |
| NightSprings | aarch64-darwin | matteo | MacBook Pro M1 Max |
| WorkLaptop | aarch64-darwin | **matteo.pacini** | Work MacBook M4 |

## Architecture

- **Custom modules** use the `custom.X = { enable = true; }` convention: `mkEnableOption` + `mkIf` + `mkMerge`.
- **Per-host CPU overlays** in `overlays/<host>.nix` (e.g. `znver4`, `apple-m4`). Shared overlays live in `overlays/shared.nix`.
- **Darwin hosts** get extra modules NixOS hosts do not: `mac-app-util`, `custom.xcode` (Xcode from attic-cached `.xip` archives), and `nix-homebrew`.
- **Shared Home Manager modules** are loaded on all hosts via `homeManagerModules.default` in `flake.nix`.
- **Kernel:** `modules/nixos/kernel.nix` sets `linuxPackages_7_1`.

## Secrets

All hosts use agenix secrets: Nexus holds the bulk (services, disk keyfiles), and every host except CauldronLake has an attic netrc.

- Definitions: `secrets/secrets.nix`
- Encrypted files: `secrets/<host>/*.age`
- Re-key after changing `secrets.nix`:
  ```bash
  cd secrets && agenix --rekey -i /path/to/valid/identity
  ```

## Home Assistant (Nexus)

Read this before touching Home Assistant (https://home.matteopacini.me, `services.home-assistant` on Nexus). Half of it lives in this repo; the other half lives only in HA's state directory. Work out which half a change belongs to before you start.

**In this repo, under `hosts/Nexus/services/home-assistant/`.** These need a commit and a deploy:
- `default.nix`:
  - Integrations: `extraComponents`, and `customComponents` for anything packaged here.
  - Frontend modules: `customLovelaceModules`.
  - YAML config under `config`: command_line sensors, template helpers, YAML automations, and the YAML-mode Overview dashboard.
  - Blueprints, and the `www` symlinks.
- `themes/`: the Nocturne theme (`nocturne.yaml`) and its motion script. The header links the design system artifact.
- `cards/`: custom cards written for this HA, including the house floorplan on Home > Home. See `cards/README.md` for where the floorplan's layout lives and how to add sensors to it.
- `blueprints/automation/`, `patches/`.

**Only in HA (`/var/lib/hass/.storage` and `/var/lib/hass/*.yaml`).** These are edited live in the UI or over the websocket API. They are not in git and need no deploy:
- Every UI dashboard and its cards, including the floorplan card's YAML.
- UI automations (`automations.yaml`), plus scenes, scripts and UI helpers.
- Integration config entries.
- The sidebar order and the default theme.

**Gotchas:**
- **Public repo.** Keep house-specific data in HA, not here. This covers the floorplan layout and the budget figures.
- **Frontend changes and the cache.** After a deploy, a change to a theme, card or module only shows after a hard refresh (Ctrl+Shift+R). The service worker serves the old index until then. Module versions are content hashes, so URLs change with each edit.
- **Card styling uses UIX.** card-mod is gone from nixpkgs. Theme styling only applies while UIX has a config entry (added in the UI) and the theme sets `uix-theme`.
- **Live config goes through the user's browser.** Read or change it with Claude in Chrome on the HA site:
  - `document.querySelector("home-assistant").hass`
  - `hass.connection.sendMessagePromise({ type: "lovelace/config", ... })`
  - That `hass` object is a snapshot, so read it again after every await.
  - The HA MCP server only sees entities exposed to Assist, which is not all of them.
- **Deploys are the user's.** Commit and push when asked, then wait for them to say it is deployed before checking it live.

## Where to Find Things

| What | Where |
|------|-------|
| Flake inputs, outputs, host wiring | `flake.nix` |
| Host system config | `hosts/<Host>/default.nix` |
| User-level Home Manager config | `hosts/<Host>/users/<user>/default.nix` |
| Shared NixOS modules | `modules/nixos/` |
| Shared Darwin modules | `modules/darwin/` |
| Shared Home Manager modules | `modules/home-manager/` |
| Xcode installs (`custom.xcode`, `xcode-fetch`) | `docs/xcode-handbook.md` |
| Per-host CPU overlays | `overlays/<host>.nix` |
| Custom packages | `packages/` |
| Agenix secret definitions | `secrets/secrets.nix` |
| Nexus storage docs | `docs/nexus/` |
| CI/CD | `.github/workflows/` |
| Auto-deploy (comin, `deploy` branch) | `docs/auto-deploy-handbook.md` |
| Home Assistant (what is in the repo vs only in HA) | "Home Assistant (Nexus)" above; `hosts/Nexus/services/home-assistant/` |
| Home Assistant custom cards (house floorplan: where its layout lives, how to add sensors) | `hosts/Nexus/services/home-assistant/cards/README.md` |
| Herdr module (mods, workbench layout, agent labels, tests) | `modules/home-manager/herdr/README.md`; how to change it: `modules/home-manager/herdr/AGENTS.md` |
