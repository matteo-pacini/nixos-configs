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
  # r8169: Realtek RTL8125 2.5GbE NIC for initrd SSH (remote LUKS unlock)
  boot.initrd.availableKernelModules = lib.optionals (!isVM) [
    "nvme"
    "xhci_pci"
    "usbhid"
    "sd_mod"
    "r8169"
  ];
  # ext2 required to mount vault partition in initrd
  boot.initrd.supportedFilesystems = lib.optionals (!isVM) [ "ext2" ];
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" "ntsync" ];

  # Disable WiFi - not needed, using Ethernet only
  # Blacklisting the top-level driver is sufficient; dependencies won't load
  boot.blacklistedKernelModules = lib.optionals (!isVM) [ "mt7921e" ];

  # amd_pstate=active enables EPP (Energy Performance Preference) mode
  # On Linux 6.5+ with Zen2+, amd_pstate is default but explicit active mode
  # ensures best performance/efficiency balance for Zen4 (8845HS)
  boot.kernelParams =
    lib.optionals (!isVM) [
      "amd_pstate=active"
    ]
    ++ lib.optionals isVM [
      (if pkgs.stdenv.hostPlatform.isAarch64 then "console=ttyAMA0,115200" else "console=ttyS0,115200")
    ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  # Limit max CPU frequency to 4.5GHz for thermal/power reasons
  # With amd_pstate=active, the default powersave governor is dynamic (not fixed-min)
  powerManagement.cpufreq.max = lib.mkIf (!isVM) 4500000; # kHz

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

  # Flush initrd DHCP lease before stage 2 so NetworkManager can cleanly
  # acquire its own lease and configure DNS in systemd-resolved
  boot.initrd.network.flushBeforeStage2 = true;

  # Initrd networking for remote LUKS unlock via SSH
  boot.initrd.systemd.network = lib.mkIf (!isVM) {
    enable = true;
    networks."10-enp2s0" = {
      matchConfig.Name = "enp2s0";
      networkConfig.DHCP = "ipv4";
    };
  };

  # Initrd SSH for remote LUKS unlock (port 2222 to avoid known_hosts conflict with main SSH on 1788)
  # Host key must be pre-generated: ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
  boot.initrd.network.ssh = lib.mkIf (!isVM) {
    enable = true;
    port = 2222;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQiM93t9mXjpqdtY12ohNAELZNg1SOdE47bWNRb4HC0 matteo@MacBookPr"
    ];
    hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    extraConfig = "StrictModes no";
  };

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
