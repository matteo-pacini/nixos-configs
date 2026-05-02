<div align="center">
  <img src="assets/nixos-logo.png" width="220px" alt="NixOS Logo">
  <h1>Matteo's NixOS &amp; Nix-Darwin Configurations</h1>

[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white)](https://nixos.org)
[![nix-darwin](https://img.shields.io/badge/nix--darwin-master-purple?logo=apple&logoColor=white)](https://github.com/LnL7/nix-darwin)
[![Flakes](https://img.shields.io/badge/Flakes-enabled-green?logo=nix&logoColor=white)](https://nixos.wiki/wiki/Flakes)
[![Build](https://github.com/matteo-pacini/nixos-configs/actions/workflows/build.yml/badge.svg)](https://github.com/matteo-pacini/nixos-configs/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

<em>Personal NixOS &amp; nix-darwin flake. Hosts named after the <a href="https://en.wikipedia.org/wiki/Alan_Wake">Alan Wake</a> universe.</em>

</div>

---

## Overview

Seven build configurations across five physical machines. Linux hosts run NixOS on `linuxPackages_7_0`; Darwin hosts use nix-darwin with Homebrew taps pinned through `nix-homebrew`. Home Manager is shared across both. Secrets are managed with [agenix](https://github.com/ryantm/agenix) (Nexus only, today).

| Host | Platform | Role | User |
|------|----------|------|------|
| **BrightFalls** | `x86_64-linux` | Gaming desktop | `matteo` |
| **BrightFallsVM-x86_64-linux** | `x86_64-linux` | VM variant | `matteo` |
| **BrightFallsVM-aarch64-linux** | `aarch64-linux` | VM variant | `matteo` |
| **Nexus** | `x86_64-linux` | Headless home server | `matteo` |
| **CauldronLake** | `x86_64-linux` | Razer travel laptop | `debora` |
| **NightSprings** | `aarch64-darwin` | MacBook Pro M1 Max | `matteo` |
| **WorkLaptop** | `aarch64-darwin` | MacBook Pro M4 | `matteo.pacini` |

## Quick Start

```bash
# Build a configuration (doesn't apply it)
nix build ".#nixosConfigurations.<Host>.config.system.build.toplevel"

# Apply on NixOS
sudo nixos-rebuild switch --flake .#<Host>

# Apply on macOS
nix run nix-darwin -- switch --flake .#<Host>

# Format the tree
nix fmt
```

> See [`AGENTS.md`](AGENTS.md) for the full development workflow, cross-platform evaluation tips, and module conventions.

---

## Hosts

### BrightFalls — Gaming Desktop

**Minisforum UM890 Pro** with an **RX 6800 XT** running through a DEG1 eGPU dock. Daily driver.

<details>
<summary><strong>Hardware</strong></summary>

| Component | Model |
|-----------|-------|
| CPU | AMD Ryzen 7 8845HS — Zen 4, 8C/16T, 45 W |
| RAM | 32 GB DDR5-5600 |
| GPU | RX 6800 XT 16 GB (DEG1 eGPU dock) |
| Storage | Crucial P310 4 TB NVMe |
| Displays | ASUS ROG SWIFT PG278QR 1440p @165 Hz · Dell U2719D 1440p @60 Hz |
| Audio | Schiit Modi 2 / Magni 2 + Sennheiser HD 650 |
| VR | Valve Index |

</details>

<details>
<summary><strong>Software</strong></summary>

- GNOME on Wayland
- Linux 7.0 with **BORE** scheduler patches
- Per-host **znver4** overlay tuning the system for Zen 4
- **Full-disk encryption** (LUKS2) using vault-based keyfile unlock
- KVM/QEMU virtualization, **Sunshine** for game streaming, **LACT** for GPU control
- Suspend disabled (the eGPU never recovers cleanly)

</details>

<details>
<summary><strong>Disk Layout</strong></summary>

Single 4 TB NVMe partitioned with [disko](https://github.com/nix-community/disko):

| Mount | Size | FS | Encryption |
|-------|------|----|------------|
| `/boot` | 1 GB | FAT32 | none |
| `/vault` | 64 MB | ext2 | LUKS2 (password) |
| `swap` | 36 GB | swap | LUKS2 (keyfile) |
| `/` | 200 GB | ext4 | LUKS2 (keyfile) |
| `/home` | 1 TB | ext4 | LUKS2 (keyfile) |
| `/games` | ~2.7 TB | XFS | LUKS2 (keyfile) |

You enter the vault password once at boot. Everything else unlocks automatically from the keyfile stored in `/vault`. Initrd SSH on port `2222` is available for remote unlock.

**Fresh install:**

```bash
# 1. Stage vault password and a random keyfile
echo -n "your-vault-password" > /tmp/vault.key
dd if=/dev/urandom of=/tmp/luks.key bs=4096 count=1 iflag=fullblock

# 2. Partition, format, and mount
sudo nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake github:matteo-pacini/nixos-configs#BrightFalls

# 3. Install
sudo nixos-install --flake github:matteo-pacini/nixos-configs#BrightFalls
```

</details>

### CauldronLake — Razer Blade

Travel gaming laptop running NixOS. Intel CPU + NVIDIA GPU (Optimus, PRIME render offload), GNOME on Linux 7.0, Steam with Proton.

### Nexus — Home Server

**Dell PowerEdge R730xd**. Headless. Handles media, automation, backups, and home-lab workloads. Secrets via agenix.

<details>
<summary><strong>Hardware</strong></summary>

| Component | Model |
|-----------|-------|
| CPU | 2× Xeon E5-2697 v4 (36C / 72T total) |
| RAM | 132 GB DDR4 ECC |
| GPU | NVIDIA Quadro P2000 5 GB (Jellyfin transcoding) |
| Network | 8× 1 GbE |
| RAID | PERC H730p (2 GB cache) |
| PSU | 1100 W 80+ Platinum |

</details>

<details>
<summary><strong>Storage</strong> — ~82 TB raw / ~73 TB usable</summary>

| Pool | Disks | FS | Notes |
|------|-------|----|-------|
| OS | 2× MX500 2 TB | XFS | mdadm RAID1 |
| Data | 10× 7–9 TB HDDs | ext4 | LUKS encrypted, merged via [mergerfs](https://github.com/trapexit/mergerfs) |
| Parity | 2× 9 TB HDDs | ext4 | [SnapRAID](https://www.snapraid.it) dual parity |

See the [Diskpool Handbook](docs/nexus/diskpool-handbook.md) for the full storage architecture.

</details>

<details>
<summary><strong>Services</strong></summary>

- **Media** — Jellyfin (NVENC), Sonarr, Radarr, NZBGet, NZBHydra, Paperless-ngx
- **Cloud & sync** — Nextcloud, Atuin shell-history server
- **Home automation** — Home Assistant, Zigbee2MQTT, Mosquitto, Wyoming (faster-whisper STT + Piper TTS)
- **AI & automation** — n8n, LibreChat with Meilisearch (OpenRouter backend)
- **Infrastructure** — PostgreSQL, Caddy, Tailscale, Mosh, Fail2ban, Route53 DDNS, MaxMind GeoIP

</details>

<details>
<summary><strong>Software</strong></summary>

- Headless (no desktop)
- Linux 7.0, legacy BIOS boot
- aarch64 binfmt emulation for cross-compilation
- smartd monitoring + dual-UPS [`apcupsd-multi`](modules/nixos/apcupsd-multi.nix)
- Secrets managed with [agenix](https://github.com/ryantm/agenix)

</details>

### NightSprings — MacBook Pro M1 Max

Personal laptop. nix-darwin + nix-homebrew, declaratively managed Xcode versions (see [`xcodes`](#homemanagermodulesxcodes--declarative-xcode) below), Tailscale.

### WorkLaptop — MacBook Pro M4

Work machine. nix-darwin + nix-homebrew, Docker via Colima, Tailscale.

---

## Modules

The flake exposes three module sets — `nixosModules.default`, `darwinModules.default`, and `homeManagerModules.default` — plus the standalone `homeManagerModules.xcodes`. Most modules are personal config; the ones below are written with options so they can be reused.

### `homeManagerModules.xcodes` — Declarative Xcode

Home Manager module for managing [Xcode](https://developer.apple.com/xcode/) versions through [xcodes](https://github.com/XcodesOrg/xcodes). Darwin only. Handles installation, version switching, and cleanup of old versions automatically.

```nix
inputs.nixos-configs.url = "github:matteo-pacini/nixos-configs";

home-manager.sharedModules = [
  inputs.nixos-configs.homeManagerModules.xcodes
];

programs.xcodes = {
  enable = true;
  versions = [ "16.2" "16.3" ];
  active = "16.2";
};
```

First activation requires Apple ID authentication; subsequent runs are automatic.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module |
| `versions` | list | `[]` | Xcode versions to install |
| `active` | string | `null` | Version to set active |

### Other configurable modules

Scoped to this flake but written with options should you want to crib them:

- **`custom.nix-core`** *(NixOS, Darwin)* — Trusted users, experimental features, extra platforms.
- **`custom.kernel`** *(NixOS)* — Linux 7.0 with optional BORE scheduler patches.
- **`custom.locale`** *(NixOS)* — Locale, timezone, console keymap and font.
- **`custom.bluetooth`**, **`custom.fonts`** *(NixOS / Darwin)* — Simple bundles.
- **`custom.system-defaults`** *(Darwin)* — Dock, Finder, Touch ID for `sudo`, dark mode.
- **`programs.git`**, **`programs.ssh`**, **`programs.atuin`**, **`programs.shell-tools`** *(Home Manager)* — Wrappers around their upstream counterparts with my preferences pre-applied.
- **[`apcupsd-multi`](modules/nixos/apcupsd-multi.nix)** *(NixOS)* — apcupsd configured for multiple UPS units.

## Packages

`overlays/shared.nix` exposes a few custom packages:

- **`tokscale`** — CLI for tracking token usage across agentic coding tools (Claude Code, OpenCode). Nix packaging of [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale).
- **`reshade-steam-proton`** — ReShade installer for Linux games running under Wine/Proton.
- **`claude-code`** — Vendored from nixpkgs master with a wrapper that puts Node.js and `rtk` on PATH and toggles auto-compact + prompt caching.

---

## Documentation

- [`AGENTS.md`](AGENTS.md) — Development workflow, conventions, and gotchas for working in this repo.
- [Diskpool Handbook](docs/nexus/diskpool-handbook.md) — Nexus storage architecture (LUKS, mergerfs, SnapRAID).
- [Paperless-ngx Recovery](docs/nexus/paperless-ngx-recovery.md) — Disaster recovery for the document archive.

## Acknowledgments

Built on top of excellent projects from the Nix community:

- [Home Manager](https://github.com/nix-community/home-manager)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [agenix](https://github.com/ryantm/agenix)
- [disko](https://github.com/nix-community/disko)
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew)
- [nvf](https://github.com/NotAShelf/nvf)
- [BORE Scheduler](https://github.com/firelzrd/bore-scheduler)
