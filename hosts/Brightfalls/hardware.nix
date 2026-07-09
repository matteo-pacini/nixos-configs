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
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "sd_mod"
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

}
