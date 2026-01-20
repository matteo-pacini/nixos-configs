<div align="center"><img src="assets/nixos-logo.png" width="300px"></div>
<h1 align="center">Matteo's NixOS/Nix Configurations</h1>
<div align="center">

[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Flakes-enabled-green?logo=nix&logoColor=white)](https://nixos.wiki/wiki/Flakes)
[![Build](https://github.com/matteo-pacini/nixos-configs/actions/workflows/build.yml/badge.svg)](https://github.com/matteo-pacini/nixos-configs/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

</div>

Personal NixOS and nix-darwin configurations for my machines. Uses flakes, Home Manager, and agenix for secrets. Host names are from the [Alan Wake](https://en.wikipedia.org/wiki/Alan_Wake) universe.

## Quick Start

```bash
# Build a configuration (doesn't apply it)
nix build ".#nixosConfigurations.BrightFalls.config.system.build.toplevel"

# Apply on NixOS
sudo nixos-rebuild switch --flake .#BrightFalls

# Apply on macOS
nix run nix-darwin -- switch --flake .#NightSprings
```

## Hosts

### Gaming

#### BrightFalls

**Minisforum UM890 Pro** with RX 6800 XT eGPU — my main desktop.

<details>
<summary>Hardware</summary>

| Component | Model |
|-----------|-------|
| CPU | AMD Ryzen 7 8845HS (Zen4, 8C/16T, 45W) |
| RAM | 32GB DDR5-5600 |
| GPU | RX 6800 XT 16GB (DEG1 eGPU dock) |
| Storage | Crucial P310 4TB NVMe |
| Displays | ROG SWIFT PG278QR 1440p 165Hz + Dell U2719D 1440p 60Hz |
| Audio | Schiit Modi 2/Magni 2, Sennheiser HD 650 |
| VR | Valve Index |

</details>

<details>
<summary>Software</summary>

- GNOME on Wayland
- Linux 6.18 with BORE scheduler
- Full disk encryption (LUKS2) with vault-based keyfile unlock
- KVM/QEMU for VMs, Sunshine for streaming, LACT for GPU control
- Suspend disabled (eGPU doesn't survive it)

</details>

<details>
<summary>Disk Layout</summary>

Single 4TB NVMe partitioned with [disko](https://github.com/nix-community/disko):

| Mount | Size | Filesystem | Encryption |
|-------|------|------------|------------|
| `/boot` | 1GB | FAT32 | None |
| `/vault` | 64MB | ext2 | LUKS2 (password) |
| `swap` | 36GB | swap | LUKS2 (keyfile) |
| `/` | 200GB | ext4 | LUKS2 (keyfile) |
| `/home` | 1TB | ext4 | LUKS2 (keyfile) |
| `/games` | ~2.7TB | XFS | LUKS2 (keyfile) |

On boot, you enter the vault password once. Everything else unlocks automatically from the keyfile stored in `/vault`.

**Fresh install:**
```bash
# Create vault password and generate keyfile
echo -n "your-vault-password" > /tmp/vault.key
dd if=/dev/urandom of=/tmp/luks.key bs=4096 count=1 iflag=fullblock

# Partition and format
sudo nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake github:matteo-pacini/nixos-configs#BrightFalls

# Install
sudo nixos-install --flake github:matteo-pacini/nixos-configs#BrightFalls
```

</details>

#### CauldronLake

**Razer Blade** — gaming laptop for travel.

- Intel CPU + NVIDIA GPU (Optimus, Prime offload)
- GNOME, Linux 6.18
- Steam with Proton

---

### Server

#### Nexus

**Dell PowerEdge R730xd** — home server for media, backups, and home automation.

<details>
<summary>Hardware</summary>

| Component | Model |
|-----------|-------|
| CPU | 2x Xeon E5-2697 v4 (36C/72T total) |
| RAM | 132GB DDR4 ECC |
| GPU | Quadro P2000 5GB (transcoding) |
| Network | 8x 1GbE |
| RAID | H730p (2GB cache) |
| PSU | 1100W Platinum |

</details>

<details>
<summary>Storage</summary>

~82TB raw, ~73TB usable after parity.

| Purpose | Disks | Filesystem | Notes |
|---------|-------|------------|-------|
| OS | 2x MX500 2TB | XFS | Software RAID1 |
| Data | 10x 7-9TB HDDs | ext4 | LUKS encrypted, merged via [mergerfs](https://github.com/trapexit/mergerfs) |
| Parity | 2x 9TB HDDs | ext4 | [SnapRAID](https://www.snapraid.it/) dual parity |

See [Diskpool Handbook](docs/nexus/diskpool-handbook.md) for the full storage architecture.

</details>

<details>
<summary>Services</summary>

**Media:** Jellyfin, Sonarr, Radarr, qBittorrent, NZBGet, NZBHydra, Paperless-ngx

**Home Automation:** Home Assistant, Zigbee2MQTT, Mosquitto, Wyoming (Piper TTS + Whisper STT)

**Automation:** n8n

**Infrastructure:** PostgreSQL, Caddy, Grafana, VictoriaMetrics, VictoriaLogs, Tailscale, Fail2ban, Route53 DDNS

</details>

<details>
<summary>Software</summary>

- Headless (no desktop)
- Linux 6.18, legacy BIOS boot
- aarch64 binfmt emulation for cross-compilation
- smartd monitoring, dual UPS with apcupsd
- Secrets managed with [agenix](https://github.com/ryantm/agenix)

</details>

---

### macOS

#### NightSprings

**MacBook Pro M1 Max** — personal laptop.

nix-darwin + Homebrew, managed Xcode versions, Tailscale.

#### WorkLaptop

**MacBook Pro M1** — work machine.

nix-darwin + Homebrew, Docker via Colima, Tailscale.

---

## Modules

### Xcodes

Home Manager module for declaratively managing [Xcode](https://developer.apple.com/xcode/) versions via [xcodes](https://github.com/XcodesOrg/xcodes). macOS only.

Handles installation, version switching, and cleanup of old versions automatically.

**Usage:**

```nix
# flake.nix
inputs.nixos-configs.url = "github:matteo-pacini/nixos-configs";

# In your darwin configuration
home-manager.sharedModules = [
  inputs.nixos-configs.homeManagerModules.xcodes
];

# In your Home Manager config
programs.xcodes = {
  enable = true;
  versions = [ "16.2" "16.3" ];
  active = "16.2";
};
```

First activation requires Apple ID authentication. Subsequent runs are automatic.

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module |
| `versions` | list | `[]` | Xcode versions to install |
| `active` | string | `null` | Version to set as active |

---

## Documentation

- [Diskpool Handbook](docs/nexus/diskpool-handbook.md) — Nexus storage architecture (LUKS, mergerfs, SnapRAID)
- [Paperless-ngx Recovery](docs/nexus/paperless-ngx-recovery.md) — Disaster recovery procedures

---

## Acknowledgments

Built on top of excellent projects from the Nix community:

- [Home Manager](https://github.com/nix-community/home-manager)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [agenix](https://github.com/ryantm/agenix)
- [disko](https://github.com/nix-community/disko)
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew)
