{
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules for UM890 Pro (NVMe-only, no SATA)
  # r8169: Realtek RTL8125 2.5GbE NIC for initrd SSH (remote LUKS unlock)
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "sd_mod"
    "r8169"
  ];
  boot.kernelModules = [
    "kvm-amd"
    "ntsync"
  ];

  # Disable WiFi - not needed, using Ethernet only
  # Blacklisting the top-level driver is sufficient; dependencies won't load
  boot.blacklistedKernelModules = [ "mt7921e" ];

  # amd_pstate=active enables EPP (Energy Performance Preference) mode
  # On Linux 6.5+ with Zen2+, amd_pstate is default but explicit active mode
  # ensures best performance/efficiency balance for Zen4 (8845HS)
  boot.kernelParams = [
    "amd_pstate=active"
    "pcie_aspm=off"
    "iommu=pt"
    "pci=realloc,assign-busses,pcie_bus_perf"
  ];

  # Fix intermittent poweroff hang: ABBA deadlock on dm->dc_lock in 7.1's
  # amdgpu_dm_ism.c. Backport of mainline 3714fe242592 (in v7.2-rc1, not
  # tagged for stable). Drop when kernel >= 7.2.
  boot.kernelPatches = [
    {
      name = "amdgpu-ism-dc-lock-deadlock";
      patch = ./patches/amdgpu-ism-dc-lock-deadlock.patch;
    }
  ];

  hardware.cpu.amd.updateMicrocode = true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  # Limit max CPU frequency to 4.5GHz for thermal/power reasons
  # With amd_pstate=active, the default powersave governor is dynamic (not fixed-min)
  powerManagement.cpufreq.max = 4500000; # kHz

  # Force mutter/GDM to use the 6800 XT (eGPU) as primary GPU
  # With dual AMD GPUs (iGPU + dGPU), mutter may pick the wrong one by default
  # This udev rule tells mutter to prefer the dGPU for rendering
  # Match by PCI device ID (1002:73BF = RX 6800 XT) for stability across reboots
  # See: https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1562
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card*", ATTRS{device}=="0x73bf", ATTRS{vendor}=="0x1002", TAG+="mutter-device-preferred-primary"
  '';

  # systemd initrd: needed for LVM activation ordering after LUKS unlock
  boot.initrd.systemd.enable = true;

  # Activate the LVM volume group inside the LUKS container
  boot.initrd.services.lvm.enable = true;

  # Flush initrd DHCP lease before stage 2 so NetworkManager can cleanly
  # acquire its own lease and configure DNS in systemd-resolved
  boot.initrd.network.flushBeforeStage2 = true;

  # Initrd networking for remote LUKS unlock via SSH
  boot.initrd.systemd.network = {
    enable = true;
    networks."10-enp2s0" = {
      matchConfig.Name = "enp2s0";
      networkConfig.DHCP = "ipv4";
    };
  };

  # Initrd SSH for remote LUKS unlock (port 2222 to avoid known_hosts conflict with main SSH on 1788)
  # Host key must be pre-generated: ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
  boot.initrd.network.ssh = {
    enable = true;
    port = 2222;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQiM93t9mXjpqdtY12ohNAELZNg1SOdE47bWNRb4HC0 matteo@MacBookPr"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINm/ozPgRTmYmOVgkdNOw2deEOzBjoA4gGWLjWzrEC+u Pixel"
    ];
    hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    extraConfig = "StrictModes no";
  };

}
