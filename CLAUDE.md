# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Multi-host NixOS/nix-darwin configuration repository using Nix flakes. Manages 6 systems across Linux (x86_64, aarch64) and macOS (aarch64-darwin).

## Build Commands

**Build a NixOS configuration:**
```bash
nix build ".#nixosConfigurations.BrightFalls.config.system.build.toplevel"
nix build ".#nixosConfigurations.Nexus.config.system.build.toplevel"
```

**Build a Darwin configuration:**
```bash
nix build ".#darwinConfigurations.NightSprings.config.system.build.toplevel"
```

**Apply configuration (NixOS):**
```bash
sudo nixos-rebuild switch --flake .#BrightFalls
```

**Apply configuration (macOS):**
```bash
nix run nix-darwin -- switch --flake .#NightSprings
```

**Format Nix files:**
```bash
nix fmt
```

## Architecture

### Hosts
- **BrightFalls** - Gaming PC (x86_64-linux), has VM variants for testing
- **Nexus** - Storage server (x86_64-linux), complex storage with agenix secrets
- **CauldronLake** - Gaming laptop (x86_64-linux), NVIDIA Optimus
- **NightSprings** - MacBook Pro M1 Max (aarch64-darwin)
- **WorkLaptop** - Work MacBook M1 (aarch64-darwin)

### Directory Structure
- `hosts/` - Per-host configurations, each host has modular files (networking.nix, services.nix, etc.)
- `hosts/shared/` - Shared modules across hosts (kernel.nix, home-manager configs)
- `modules/` - Custom NixOS and Home Manager modules
- `overlays/` - Per-host package overlays with CPU-specific optimizations
- `secrets/` - agenix encrypted secrets (.age files)
- `docs/` - Host-specific documentation (Nexus storage handbook)

### Key Patterns

**Host composition:** Each host imports modular files for subsystems:
```nix
imports = [
  ./networking.nix
  ./users.nix
  ./desktop.nix
  ./services.nix
  # ...
];
```

**mkBrightFalls helper:** Factory function in flake.nix for gaming systems with `isVM` flag for VM-specific tweaks.

**Overlays:** Per-host CPU optimizations (znver4 for BrightFalls, sandybridge for Nexus).

**Secrets:** agenix with age-encrypted files. Identity paths configured per host. Secrets available at `/run/agenix/...` after boot.

**Home Manager:** Integrated into NixOS/Darwin configs. Shared modules in `hosts/shared/home-manager/` work across Linux and macOS.

### Flake Inputs
- `nixpkgs` (nixos-unstable), `home-manager`, `nix-darwin`, `agenix`, `disko`, `nix-homebrew`, `mac-app-util`
- Dracula themes, Firefox GNOME theme, BORE scheduler patches

## CI/CD

GitHub Actions builds all 7 configurations on push to master. Uses Attic binary cache at `zpnixcache.fly.dev`.

## Commit Style

Semantic commits with host scope: `feat(nexus):`, `fix(brightfalls):`, etc.
