<div align="center"><img src="assets/nixos-logo.png" width="300px"></div>
<h1 align="center">Matteo's NixOS/Nix Configurations</h1>
<div align="center">

[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Flakes-enabled-green?logo=nix&logoColor=white)](https://nixos.wiki/wiki/Flakes)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)
[![Maintained](https://img.shields.io/badge/Maintained-Yes-brightgreen)](https://github.com/matteo-pacini/nixos-configs)

</div>

## 📋 Table of Contents

- [🖥️ Hosts](#-hosts)
  - [🎮 Gaming Systems](#-gaming-systems)
  - [🖥️ Servers](#-servers)
  - [💻 Development Laptops](#-development-laptops)
- [📦 Modules](#-modules)
- [📚 Docs](#-docs)

---

## 🖥️ Hosts

### 🎮 Gaming Systems

#### 🎮 BrightFalls

**Custom Gaming Desktop** (Fractal Design Meshify C ATX Mid Tower)

<details>
<summary><b>📋 Hardware Details</b></summary>

- **CPU:** AMD Ryzen 7 5800X3D 3.4 GHz 8-Core (Zen 3D, 105W TDP)
- **CPU Cooler:** be quiet! Dark Rock Pro 4
- **Motherboard:** Asus ROG STRIX B450-F GAMING ATX AM4
- **RAM:** 32GB (4x8GB) TEAMGROUP Dark Pro DDR4-3200 CL14
- **GPU:** Asus TUF-RX6800XT-O16G-GAMING Radeon RX 6800 XT 16 GB GDDR6
- **Storage:**
  - Samsung 840 Pro 256 GB 2.5" SSD
  - Samsung 850 Pro 512 GB 2.5" SSD
  - Samsung 860 Evo 1 TB 2.5" SSD
- **Power Supply:** EVGA SuperNOVA 750 G3 750W 80+ Gold
- **Displays:**
  - Asus ROG SWIFT PG278QR 27" 2560x1440 165Hz (DP)
  - Dell U2719D 27" 2560x1440 60Hz (DP)
- **Peripherals:**
  - Razer Viper Mouse
  - Sennheiser HD 650 Headphones
  - Audioengine A2+W Speakers
  - Valve Index VR
  - Schiit Modi 2 & Magni 2 (DAC/Amp)

</details>

<details>
<summary><b>⚙️ System Configuration</b></summary>

- GNOME desktop
- Linux 6.17 + BORE scheduler
- GRUB2 (EFI)
- Btrfs root (subvolumes), ext4 games, all LUKS encrypted
- Vault partition for keyfile auto-unlock
- KVM/QEMU, LACT (GPU OC), Sunshine, ananicy-cpp

</details>

<details>
<summary><b>💾 Disk Layout (Disko)</b></summary>

**OS Disk (1TB Samsung 860 EVO):**
- `/boot` - 512MB EFI partition (unencrypted)
- `/vault` - 48MB LUKS2 encrypted (Serpent-XTS, password-unlocked)
- `swap` - 32GB random encryption (ephemeral key per boot)
- `/` - ~899GB LUKS2 encrypted Btrfs (keyfile auto-unlock)
  - Subvolumes: `@`, `@home`, `@nix`, `@log`, `@cache`, `@snapshots`

**Games Disks:**
- 512GB Samsung 850 PRO - LUKS2 encrypted ext4 (keyfile auto-unlock)
- 256GB Samsung 840 PRO - LUKS2 encrypted ext4 (keyfile auto-unlock)

**Installation:**
```bash
# 1. Create password file for vault (used during disko format)
echo -n "your-vault-password" > /tmp/vault.passwordFile

# 2. Generate keyfile for other volumes (used during disko format)
dd if=/dev/urandom of=/tmp/luks.key bs=4096 count=1 iflag=fullblock

# 3. Run disko (formats all disks, mounts to /mnt, and copies keyfile to vault)
sudo nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake github:matteo-pacini/nixos-configs#BrightFalls

# 4. Install NixOS
sudo nixos-install --flake github:matteo-pacini/nixos-configs#BrightFalls
```

**Boot sequence:**
1. Enter vault password → vault unlocks and mounts at `/vault`
2. Root/games volumes auto-unlock using `/vault/luks.key`
3. System boots normally

</details>

### 🖥️ Servers

#### 🖥️ Nexus

**Dell PowerEdge R730xd 2U Server** (12x 3.5" LFF + 2x 2.5" SFF bays)

<details>
<summary><b>📋 Hardware Details</b></summary>

- 2x Xeon E5-2697 v4 (36c/72t total)
- 132GB DDR4 RDIMM
- Quadro P2000 5GB
- 8x 1GbE (Dell I350 + Intel Pro 1000PT)
- H730p RAID controller (2GB cache)
- 1100W Platinum PSU

</details>

<details>
<summary><b>💾 Storage Configuration</b></summary>

**OS:** 2x Crucial MX500 2TB (software RAID1)

**Data:** 10 disks (7.3-9.1TB mix of Seagate Barracuda Pro + WDC Red Pro), LUKS encrypted, pooled via MergerFS

**Parity:** 2x 9.1TB WDC Red Pro (SnapRAID dual parity)

**Total:** ~82TB raw, ~73TB usable

</details>

<details>
<summary><b>⚙️ System Configuration</b></summary>

- Linux 6.17, GRUB2 (legacy BIOS)
- XFS root, LUKS data disks
- aarch64 binfmt emulation
- smartd + UPS monitoring

</details>

<details>
<summary><b>🚀 Services</b></summary>

**Media:** Jellyfin, Sonarr, Radarr, NZBGet, NZBHydra, qBittorrent

**Home Automation:** Home Assistant, Zigbee2MQTT, Mosquitto

**Infra:** Grafana, VictoriaMetrics, PostgreSQL, NGINX, Tailscale

</details>

### 💻 Development Laptops

#### 💻 NightSprings

**Apple MacBook Pro M1 Max** — Personal laptop, nix-darwin + Homebrew, Xcodes, Tailscale.

#### 💻 WorkLaptop

**Apple MacBook Pro M1** — Work laptop, nix-darwin + Homebrew, Docker/Colima, Xcodes, Tailscale.

#### 💻 CauldronLake

**Razer Gaming Laptop** — Intel/NVIDIA Optimus, GNOME, Linux 6.17, NVIDIA Prime offload, Steam.

## 📦 Modules

### Xcodes (homeManagerModules.xcodes)

Home Manager module for managing multiple Xcode versions via [xcodes](https://github.com/XcodesOrg/xcodes). macOS only.

#### Requirements

- macOS + Home Manager
- Apple Developer account
- ~15GB disk per Xcode version

#### Usage

Add to your flake inputs:

```nix
inputs.nixos-configs.url = "github:matteo-pacini/nixos-configs";
```

Add to `home-manager.sharedModules`:

```nix
home-manager.sharedModules = [
  inputs.nixos-configs.homeManagerModules.xcodes
];
```

Configure in your Home Manager config:

```nix
programs.xcodes = {
  enable = true;
  versions = [ "16.2" "16.3" ];
  active = "16.2";
};
```

#### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the module |
| `versions` | list | `[ "15.4" ]` | Xcode versions to install |
| `active` | string | `"15.4"` | Active Xcode version |

On activation: updates index, installs specified versions, sets active, removes unlisted versions.

First run requires Apple ID auth; subsequent runs are automatic.

## 📚 Docs

### Nexus

- [Diskpool Handbook](docs/nexus/diskpool-handbook.md) — Storage architecture, LUKS, mergerfs, SnapRAID
- [Paperless-ngx Recovery](docs/nexus/paperless-ngx-recovery.md) — Disaster recovery for Paperless
