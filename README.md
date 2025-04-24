<div align="center"><img src="assets/nixos-logo.png" width="300px"></div>
<h1 align="center">Matteo's NixOS/Nix Configurations</h1>
<div align="center">
</div>

## ️ Hosts

### BrightFalls

- Brand: Custom PC (Fractal Design Meshify C ATX Mid Tower)
- CPU: AMD Ryzen 7 5800X3D 3.4 GHz 8-Core
- CPU Cooler: be quiet! Dark Rock Pro 4
- Motherboard: Asus ROG STRIX B450-F GAMING ATX AM4
- RAM: 32GB (4x8GB) TEAMGROUP Dark Pro DDR4-3200 CL14
- Storage:
  - Samsung 840 Pro 256 GB 2.5" SSD
  - Samsung 850 Pro 512 GB 2.5" SSD
  - Samsung 860 Evo 1 TB 2.5" SSD
- GPU: Asus TUF-RX6800XT-O16G-GAMING Radeon RX 6800 XT 16 GB
- Power Supply: EVGA SuperNOVA 750 G3 750W 80+ Gold
- Monitors:
  - Asus ROG SWIFT PG278QR 27" 2560x1440 165Hz
  - Dell U2719D 27" 2560x1440 60Hz
- Peripherals:
  - Razer Viper Mouse
  - Sennheiser HD 650 Headphones
  - Audioengine A2+W Speakers
  - Valve Index VR
  - Schiit Modi 2 & Magni 2 (DAC/Amp)
- Desktop Environment: GNOME
- Features:
  - Gaming setup with Steam
  - CoreCtrl for GPU overclocking
  - Encrypted disks with LUKS
  - QEMU/KVM virtualization support

### Nexus

- Brand: Dell PowerEdge R730xd 2U 12x 3.5" (LFF) 2x 2.5" (SFF)
- CPUs: 2 x Intel Xeon E5-2630 v4 @ 2.20GHz (10-Core, 20-Threads, 3.10GHz Boost, 25MB Cache)
- RAM: 132GB DDR4
- GPU: Nvidia Quadro P2000
- Storage:
  - 12x 3.5" front drive bays
  - 2x 2.5" rear SSDs (Crucial MX500 2TB)
  - Dell H730p Mini Mono RAID controller with 2GB cache
  - 10 data disks + 2 parity disks with SnapRAID and MergerFS
- Network: Dell I350 Quad Port 1GbE RJ45
- Power: 1100W Platinum Hot-Swap PSU
- Services:
  - Jellyfin (media server)
  - Sonarr (TV show management)
  - Radarr (movie management)
  - NZBGet (Usenet downloader)
  - NZBHydra (Usenet indexer)
  - qBittorrent (torrent client)

### NightSprings

- Brand: Apple MacBook Pro M1 Max
- CPU: Apple M1 Max
- OS: macOS (Darwin)
- Features:
  - Tailscale VPN
  - Homebrew integration
  - Xcodes development tools

### WorkLaptop

- Brand: Apple MacBook Pro M1
- CPU: Apple M1
- OS: macOS (Darwin)
- Features:
  - Development environment with Docker and Colima
  - Homebrew integration
  - Xcodes development tools

### CauldronLake

- Brand: Razer Laptop
- CPU: Intel
- GPU: NVIDIA (hybrid/Optimus configuration)
- Desktop Environment: GNOME
- Features:
  - Gaming setup
  - NVIDIA Prime for GPU switching
  - iPhone integration

### Queen

- CPU: Intel
- Desktop Environment: GNOME
- Locale: Italian (it_IT.UTF-8)
- Timezone: Europe/Rome
- User: antonella

### Dusk

- Brand: Apple MacBook Pro 2012
- CPU: Intel (x86_64)
- OS: macOS (Darwin)

### Router

- Brand: Dell PowerEdge R620 1U 4x 2.5" (SFF)
- CPU: Intel Xeon E5-2630L V1 2.00Ghz Hexa (6) Core
- RAM: 32GB DDR3-8500R (2x16GB)
- Storage: 2x Crucial 500GB MX500 SATA-III SSD
- Network: 
  - Dell I350 Quad Port 1GbE RJ45
  - Intel Pro 1000PT Quad Port 1GbE RJ45
- Power: 750W Platinum PSU
- Features:
  - dnsmasq for DHCP and DNS
  - nftables firewall
  - Tailscale VPN
  - ACME for SSL certificates
  - NGINX web server
  - Dynamic DNS

## 📦 Modules

### Xcodes (homeManagerModules.xcodes)

This module manages multiple Xcode installations on macOS environments using the [xcodes](https://github.com/XcodesOrg/xcodes) CLI tool.

#### Requirements

- macOS only (Darwin)
- Home Manager

#### Usage

To use this module in your flake:

1. Add it to your `home-manager.sharedModules` in your Darwin system configuration:

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
        self.homeManagerModules.xcodes  # Add the xcodes module here
      ];
    }
    # ... other modules
  ];
};
```

2. Then in your user's configuration, enable and configure it:

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
