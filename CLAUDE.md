# CLAUDE.md

Behavioral guidelines and project onboarding for Claude Code. The behavioral
sections reduce common LLM coding mistakes. The project sections onboard you to
this specific codebase.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial
tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes,
simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add a module" -> "Write the module, enable it in a host, `nix build`
  succeeds"
- "Fix the build" -> "Identify the error, apply fix, `nix build` succeeds"
- "Add a service" -> "Configure the service, verify the build, check firewall
  rules"

For multi-step tasks, state a brief plan:

```
1. [Step] -> verify: [check]
2. [Step] -> verify: [check]
3. [Step] -> verify: [check]
```

---

## 5. Repository Overview

Multi-host NixOS/nix-darwin configuration repository using Nix flakes. Manages 5
physical hosts across 3 platforms, producing 7 build configurations.

**Hosts:**

- **BrightFalls** - Gaming PC (x86_64-linux) + two VM variants (x86_64, aarch64)
- **Nexus** - Home server (x86_64-linux) - storage, media, home automation,
  backups
- **CauldronLake** - Laptop (x86_64-linux) - user is `debora`, not `matteo`
- **NightSprings** - MacBook Pro M1 Max (aarch64-darwin)
- **WorkLaptop** - Work MacBook M4 (aarch64-darwin) - user is `matteo.pacini`,
  not `matteo`

**Key architectural decisions:**

- Custom modules use the `custom.X = { enable = true; }` pattern
  (`mkEnableOption` + `mkIf` + `mkMerge`)
- `mkBrightFalls` factory function in `flake.nix` creates gaming system variants
  with an `isVM` flag
- Per-host CPU optimizations via overlays (znver4, sandybridge, znver2,
  apple-m1, apple-m4)
- Shared Home Manager modules in `modules/home-manager/` are loaded on all hosts
  via `homeManagerModules.default`
- Secrets managed with agenix (currently only Nexus uses secrets)
- Dracula theme applied consistently across terminal, editor, and browser via
  `modules/home-manager/dracula.nix`

## 6. Working on This Repo

**Build a NixOS configuration:**

```bash
nix build ".#nixosConfigurations.<Host>.config.system.build.toplevel"
```

**Build a Darwin configuration (requires macOS):**

```bash
nix build ".#darwinConfigurations.<Host>.config.system.build.toplevel"
```

**Evaluate a Darwin configuration on Linux (can't build, but can check for eval
errors):**

```bash
nix eval ".#darwinConfigurations.<Host>.config.system.build.toplevel" --raw 2>&1 | head -5
```

**Apply configuration:**

```bash
# NixOS
sudo nixos-rebuild switch --flake .#<Host>
# macOS
nix run nix-darwin -- switch --flake .#<Host>
```

**Format Nix files (no formatter defined in flake, use nixfmt directly):**

```bash
nix run nixpkgs#nixfmt -- file.nix
```

**Important workflow notes:**

- New `.nix` files must be `git add`ed before `nix build` — the flake uses the
  git store, so untracked files are invisible.
- Commit style: semantic commits with host scope, e.g. `feat(nexus):`,
  `fix(brightfalls):`, `chore:`.
- CI builds all 7 configurations on push to master. Uses Attic binary cache. See
  `.github/workflows/build.yml`.
- PR builds run eval + diff against base. See `.github/workflows/pr-build.yml`.

## 7. Where to Find Things

Read these files as needed based on the task at hand. Don't read everything
upfront.

| What                                                                                                                    | Where                                                                   |
| ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Flake inputs, outputs, host wiring                                                                                      | `flake.nix`                                                             |
| Host system config (hardware, networking, services, desktop)                                                            | `hosts/<Host>/` - each has a `default.nix` that imports subsystem files |
| User-level Home Manager config                                                                                          | `hosts/<Host>/users/<user>/default.nix`                                 |
| Shared NixOS modules (nix-core, kernel, locale, bluetooth, fonts, apcupsd-multi)                                        | `modules/nixos/`                                                        |
| Shared Darwin modules (nix-core, system-defaults, fonts)                                                                | `modules/darwin/`                                                       |
| Shared Home Manager modules (git, zsh, ssh, atuin, firefox, dracula, nvf, tmux, vscode, starship, wezterm, shell-tools) | `modules/home-manager/`                                                 |
| Xcodes module (Darwin-only, manages Xcode installations)                                                                | `modules/home-manager/darwin/xcodes.nix`                                |
| Per-host CPU optimization overlays                                                                                      | `overlays/<host>.nix`                                                   |
| Agenix secret definitions                                                                                               | `secrets/secrets.nix`                                                   |
| Encrypted secret files                                                                                                  | `secrets/nexus/*.age`                                                   |
| Nexus storage handbook (disk pool, snapraid, recovery)                                                                  | `docs/nexus/`                                                           |
| CI/CD pipelines                                                                                                         | `.github/workflows/`                                                    |
| Custom packages                                                                                                         | `packages/`                                                             |
