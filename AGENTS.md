# Agent Instructions

Multi-host NixOS/nix-darwin flake managing 7 build configurations across 5 physical hosts. Read `flake.nix` for host wiring and `README.md` for hardware details.

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
- Commit style: semantic with host scope, e.g. `feat(nexus):`, `fix(brightfalls):`, `chore:`.
- CI builds all 7 configs on push to `master`. PRs run eval + diff against base. See `.github/workflows/`.

## Hosts

| Host | Platform | User | Notes |
|------|----------|------|-------|
| BrightFalls | x86_64-linux | matteo | Gaming PC |
| BrightFallsVM-x86_64-linux | x86_64-linux | matteo | VM variant |
| BrightFallsVM-aarch64-linux | aarch64-linux | matteo | VM variant |
| Nexus | x86_64-linux | matteo | Headless server |
| CauldronLake | x86_64-linux | **debora** | Razer laptop |
| NightSprings | aarch64-darwin | matteo | MacBook Pro M1 Max |
| WorkLaptop | aarch64-darwin | **matteo.pacini** | Work MacBook M4 |

## Architecture

- **Custom modules** use the `custom.X = { enable = true; }` convention: `mkEnableOption` + `mkIf` + `mkMerge`.
- **`mkBrightFalls`** in `flake.nix` is a factory that creates the BrightFalls system variants with an `isVM` flag. All three BrightFalls configs share the same host and user paths.
- **Per-host CPU overlays** in `overlays/<host>.nix` (e.g. `znver4`, `apple-m4`). Shared overlays live in `overlays/shared.nix`.
- **Darwin hosts** get extra modules NixOS hosts do not: `mac-app-util`, `xcodes` (NightSprings only), and `nix-homebrew`.
- **Shared Home Manager modules** are loaded on all hosts via `homeManagerModules.default` in `flake.nix`.
- **Kernel:** `modules/nixos/kernel.nix` sets `linuxPackages_7_0` and optionally applies BORE scheduler patches from `bore-scheduler-src`.

## Secrets

Only Nexus uses agenix secrets currently.

- Definitions: `secrets/secrets.nix`
- Encrypted files: `secrets/nexus/*.age`
- Re-key after changing `secrets.nix`:
  ```bash
  cd secrets && agenix --rekey -i /path/to/valid/identity
  ```

## Where to Find Things

| What | Where |
|------|-------|
| Flake inputs, outputs, host wiring | `flake.nix` |
| Host system config | `hosts/<Host>/default.nix` |
| User-level Home Manager config | `hosts/<Host>/users/<user>/default.nix` |
| Shared NixOS modules | `modules/nixos/` |
| Shared Darwin modules | `modules/darwin/` |
| Shared Home Manager modules | `modules/home-manager/` |
| Darwin-only xcodes module | `modules/home-manager/darwin/xcodes.nix` |
| Per-host CPU overlays | `overlays/<host>.nix` |
| Custom packages | `packages/` |
| Agenix secret definitions | `secrets/secrets.nix` |
| Nexus storage docs | `docs/nexus/` |
| CI/CD | `.github/workflows/` |
