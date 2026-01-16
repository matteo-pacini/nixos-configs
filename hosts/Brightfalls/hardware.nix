{
  pkgs,
  lib,
  modulesPath,
  isVM,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ]
  ++ lib.optionals (isVM) [
    (modulesPath + "/virtualisation/qemu-guest-agent.nix")
  ];

  # Enable SPICE vdagent for clipboard sharing in VM
  services.spice-vdagentd.enable = lib.mkIf isVM true;

  # Kernel modules for UM890 Pro (NVMe-only, no SATA)
  boot.initrd.availableKernelModules = lib.optionals (!isVM) [
    "nvme"
    "xhci_pci"
    "usbhid"
    "sd_mod"
  ];
  # ext2 required to mount vault partition in initrd
  boot.initrd.supportedFilesystems = lib.optionals (!isVM) [ "ext2" ];
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" ];

  # amd_pstate=active enables EPP (Energy Performance Preference) mode
  # On Linux 6.5+ with Zen2+, amd_pstate is default but explicit active mode
  # ensures best performance/efficiency balance for Zen4 (8845HS)
  boot.kernelParams = lib.optionals (!isVM) [
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  # Force mutter/GDM to use the 6800 XT (eGPU) as primary GPU
  # With dual AMD GPUs (iGPU + dGPU), mutter may pick the wrong one by default
  # This udev rule tells mutter to prefer the dGPU for rendering
  # Match by PCI device ID (1002:73BF = RX 6800 XT) for stability across reboots
  # See: https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/1562
  services.udev.extraRules = lib.mkIf (!isVM) ''
    SUBSYSTEM=="drm", KERNEL=="card*", ATTRS{device}=="0x73bf", ATTRS{vendor}=="0x1002", TAG+="mutter-device-preferred-primary"
  '';

  # Use systemd in initrd for proper LUKS dependency ordering
  # This ensures vault is mounted before other LUKS devices try to read keyfile
  boot.initrd.systemd.enable = lib.mkIf (!isVM) true;

  # Set runtime keyfile path for all LUKS devices that use keyfile unlock
  # (disko's settings.keyFile is only used during installation, not at boot)
  boot.initrd.luks.devices = lib.mkIf (!isVM) {
    cryptswap.keyFile = lib.mkForce "/vault/luks.key";
    cryptroot.keyFile = lib.mkForce "/vault/luks.key";
    crypthome.keyFile = lib.mkForce "/vault/luks.key";
    cryptgames.keyFile = lib.mkForce "/vault/luks.key";
  };

  # Mount the *decrypted* vault to /vault inside initrd
  # This makes /vault/luks.key available for unlocking other LUKS devices
  boot.initrd.systemd.mounts = lib.mkIf (!isVM) [
    {
      what = "/dev/mapper/cryptvault";
      where = "/vault";
      type = "ext2";
      options = "noatime,errors=remount-ro";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@cryptvault.service" ];
    }
  ];

  # Mark vault as needed early in boot so it's available for LUKS keyfile
  fileSystems = lib.mkIf (!isVM) {
    "/vault" = {
      neededForBoot = true;
    };
  };

}
