<div align="center"><img src="assets/nixos-logo.png" width="300px"></div>
<h1 align="center">Matteo's NixOS/Nix Configurations</h1>
<div align="center">
</div>

## 🖥️ Hosts

### 💻 BrightFalls

**Custom Gaming Desktop** (Fractal Design Meshify C ATX Mid Tower)

**Hardware:**
- CPU: AMD Ryzen 7 5800X3D 3.4 GHz 8-Core (Zen 3D, 105W TDP)
- CPU Cooler: be quiet! Dark Rock Pro 4
- Motherboard: Asus ROG STRIX B450-F GAMING ATX AM4
- RAM: 32GB (4x8GB) TEAMGROUP Dark Pro DDR4-3200 CL14
- GPU: Asus TUF-RX6800XT-O16G-GAMING Radeon RX 6800 XT 16 GB GDDR6
- Storage:
  - Samsung 840 Pro 256 GB 2.5" SSD
  - Samsung 850 Pro 512 GB 2.5" SSD
  - Samsung 860 Evo 1 TB 2.5" SSD
- Power Supply: EVGA SuperNOVA 750 G3 750W 80+ Gold
- Displays:
  - Asus ROG SWIFT PG278QR 27" 2560x1440 165Hz (DP)
  - Dell U2719D 27" 2560x1440 60Hz (DP)
- Peripherals:
  - Razer Viper Mouse
  - Sennheiser HD 650 Headphones
  - Audioengine A2+W Speakers
  - Valve Index VR
  - Schiit Modi 2 & Magni 2 (DAC/Amp)

**System Configuration:**
- Desktop Environment: GNOME
- Kernel: Linux 6.17 with **BORE scheduler patches**
- Bootloader: GRUB2 with EFI support
- Filesystems: XFS (root, home, data), encrypted with LUKS
- Encryption: USB key-based LUKS unlock with fallback to password
- Timezone: Europe/London (en_GB.UTF-8)
- Virtualization: KVM/QEMU support enabled
- GPU Control: LACT for AMD GPU overclocking
- Game Streaming: Sunshine server
- Process Management: Ananicy-cpp for process prioritization

### 🏠 Nexus

**Dell PowerEdge R730xd 2U Server** (12x 3.5" LFF + 2x 2.5" SFF bays)

**Hardware:**
- CPUs: 2 x Intel Xeon E5-2697 v4 @ 2.30GHz (18-Core, 36-Threads per socket, 3.6GHz Turbo, 45MB L3 Cache)
  - Total: 72 logical CPUs (36 cores), 2 NUMA nodes
  - Architecture: x86_64, 46-bit physical addressing
  - Virtualization: VT-x enabled
  - Cache: 1.1 MiB L1d, 1.1 MiB L1i, 9 MiB L2, 90 MiB L3 (shared)
- RAM: 132GB DDR4 (RDIMM)
- GPU: Nvidia Quadro P2000 (5GB GDDR5)
- Network:
  - Dell I350 Quad Port 1GbE RJ45
  - Intel Pro 1000PT Quad Port 1GbE RJ45
  - Total: 8x 1GbE ports
- RAID Controller: Dell H730p Mini Mono with 2GB cache
- Power: 1100W Platinum Hot-Swap PSU

**Storage Configuration:**
- **OS Tier (RAID1 - Software RAID):**
  - 2x Crucial MX500 2TB SSDs (md127, 1.8TB usable)
  - Mounted: /, /nix/store, /var/lib/containers/storage/overlay

- **Data Tier (SnapRAID + MergerFS):**
  - **Data Disks (10x):**
    - sda: 9.1TB Seagate Barracuda Pro (X377_HLBRE10TA07)
    - sdb: 7.3TB WDC Red Pro (WDC WD80EFAX-68KNBN0)
    - sdc: 9.1TB WDC Red Pro (WDC WD101EMAZ-11G7DA0)
    - sdd: 9.1TB Seagate Barracuda Pro (X377_HLBRE10TA07)
    - sde: 7.3TB WDC Red Pro (WDC WD80EFAX-68KNBN0)
    - sdf: 9.1TB Seagate Barracuda Pro (X377_HLBRE10TA07)
    - sdg: 7.3TB WDC Red Pro (WDC WD80EFAX-68LHPN0)
    - sdh: 9.1TB WDC Red Pro (WDC WD101EDBZ-11B1DA0)
    - sdi: 7.3TB WDC Red Pro (WDC WD80EFAX-68LHPN0)
    - sdj: 9.1TB WDC Red Pro (WDC WD101EDBZ-11B1DA0)
  - **Parity Disks (2x):**
    - sdk: 9.1TB WDC Red Pro (WDC WD101EMAZ-11G7DA0)
    - sdl: 9.1TB WDC Red Pro (WDC WD101EMAZ-11G7DA0)
  - **Total Capacity:** ~82TB raw (10 data + 2 parity), ~73TB usable with single parity
  - **Encryption:** All data disks encrypted with LUKS (dm-crypt)
  - **Memory:** 62.9GB zram swap

**System Configuration:**
- Kernel: Linux 6.17
- Bootloader: GRUB2 (legacy BIOS)
- Filesystems: XFS (root), encrypted LUKS containers for data
- Timezone: Europe/London (en_GB.UTF-8)
- Multi-platform support: x86_64-linux and aarch64-linux (binfmt emulation)
- Monitoring: S.M.A.R.T. monitoring with smartd, UPS support

**Services:**
- Jellyfin (media server)
- Sonarr (TV show management)
- Radarr (movie management)
- NZBGet (Usenet downloader)
- NZBHydra (Usenet indexer)
- qBittorrent (torrent client)
- Home Assistant (home automation)
- Grafana + VictoriaMetrics (monitoring)
- ACME + NGINX (SSL certificates & web server)
- Dynamic DNS & Tailscale VPN
- PostgreSQL (database)
- Mosquitto (MQTT broker)
- Zigbee2MQTT (Zigbee gateway)

### 💻 NightSprings

**Apple MacBook Pro M1 Max** (macOS/Darwin)

**Hardware:**
- CPU: Apple M1 Max (10-core CPU, 16-core GPU)
- Architecture: aarch64-darwin
- OS: macOS (Darwin)

**System Configuration:**
- Kernel: aarch64-darwin
- Shell: Zsh
- Primary User: matteo
- Nix: Flakes support, relaxed sandbox
- Package Management: Homebrew, Nix
- Development: Xcodes, Tailscale VPN

### 💼 WorkLaptop

**Apple MacBook Pro M1** (macOS/Darwin)

**Hardware:**
- CPU: Apple M1 (8-core CPU, 8-core GPU)
- Architecture: aarch64-darwin
- OS: macOS (Darwin)

**System Configuration:**
- Kernel: aarch64-darwin
- Shell: Zsh
- Primary User: matteo.pacini
- Nix: Flakes support, relaxed sandbox
- Package Management: Homebrew, Nix
- Virtualization: Docker + Colima
- Development: Xcodes, Tailscale VPN

### 🎮 CauldronLake

**Razer Gaming Laptop**

**Hardware:**
- CPU: Intel (x86_64)
- GPU: NVIDIA (hybrid/Optimus configuration with Intel iGPU)
- Storage: NVMe SSD (XFS)
- Swap: Dedicated swap partition

**System Configuration:**
- Desktop Environment: GNOME
- Kernel: Linux 6.17
- Bootloader: GRUB2 with EFI support
- Filesystems: XFS (root, /boot)
- Timezone: Europe/London (en_GB.UTF-8)
- Keyboard: UK layout
- GPU Driver: NVIDIA Beta driver with Prime offload mode
- Virtualization: KVM support
- Gaming: Steam with hardware acceleration
- Peripherals: Audio, printer, iPhone integration

### 👑 Queen

**Desktop Computer**

**Hardware:**
- CPU: Intel (x86_64)
- Storage: XFS filesystems (root, /home)
- Swap: Dedicated swap partition

**System Configuration:**
- Desktop Environment: GNOME
- Kernel: Linux 6.17
- Bootloader: GRUB2 with EFI support
- Filesystems: XFS (root, /home), vfat (/boot)
- Locale: Italian (it_IT.UTF-8)
- Timezone: Europe/Rome
- Keyboard: Italian layout
- Primary User: antonella
- Virtualization: KVM support
- Services: SSH server, audio, printer, Bluetooth

### 🍎 Dusk

**Apple MacBook Pro 2012** (macOS/Darwin)

**Hardware:**
- CPU: Intel (x86_64)
- Architecture: x86_64-darwin
- OS: macOS (Darwin)

**System Configuration:**
- Kernel: x86_64-darwin
- Shell: Zsh
- Primary User: matteo
- Nix: Flakes support
- Package Management: Homebrew, Nix

## 📦 Modules

### Xcodes (homeManagerModules.xcodes)

This module manages multiple Xcode installations on macOS environments using the [xcodes](https://github.com/XcodesOrg/xcodes) CLI tool.

#### Requirements

- macOS only (Darwin)
- Home Manager

#### Usage

To use this module in your flake:

1. First, add this repository as a flake input:

```nix
# In your flake.nix inputs
inputs = {
  # ... your other inputs
  nixos-configs.url = "github:matteo-pacini/nixos-configs";
};
```

2. Add the module to your `home-manager.sharedModules` in your Darwin system configuration:

```nix
# In your flake.nix for Darwin systems
darwinConfigurations."YourMacName" = inputs.nix-darwin.lib.darwinSystem {
  # ... other configuration
  modules = [
    # ... other modules
    inputs.home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.yourusername = import ./path/to/user/config;
      home-manager.sharedModules = [
        inputs.nixos-configs.homeManagerModules.xcodes  # Add the xcodes module here
      ];
    }
    # ... other modules
  ];
};
```

3. Then in your user's configuration, enable and configure it:

```nix
# In your user's home-manager configuration
{ ... }:
{
  programs.xcodes = {
    enable = true;
    versions = [
      "16.2"
      "16.3"
    ];
    active = "16.2";
  };
}
```

#### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Whether to enable the xcodes module |
| `versions` | list of strings | `[ "15.4" ]` | List of Xcode versions to install |
| `active` | string | `"15.4"` | Version to set as the active Xcode |

#### How It Works

The module:

1. Installs the `xcodes` CLI tool
2. Automatically installs specified Xcode versions into `~/Applications`
3. Sets the active Xcode version
4. Removes any Xcode versions not listed in the `versions` option
