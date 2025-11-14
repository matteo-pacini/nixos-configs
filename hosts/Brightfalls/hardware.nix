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

  boot.initrd.availableKernelModules = lib.optionals (!isVM) [
    "xhci_pci"
    "ahci"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = lib.optionals (!isVM) [
    "dm-snapshot"
    "usb_storage"
    "uas"
    "usbcore"
    "vfat"
    "nls_cp437"
    "nls_iso8859_1"
  ];

  # LUKS encryption configuration for physical machine
  # Vault partition is unlocked with password at boot and must be available before other LUKS devices
  # All other LUKS volumes (root, games1, games2) are auto-unlocked using keyfile from vault

  # Ensure vault is mounted during initrd before other LUKS devices try to unlock
  fileSystems."/vault".neededForBoot = lib.mkIf (!isVM) true;

  boot.initrd.luks.devices = lib.mkIf (!isVM) {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-a-os-disk-root";
      keyFile = "/vault/luks.key";
      allowDiscards = true;
    };
    cryptgames1 = {
      device = "/dev/disk/by-partlabel/disk-b-games-disk-1-games1";
      keyFile = "/vault/luks.key";
      allowDiscards = true;
    };
    cryptgames2 = {
      device = "/dev/disk/by-partlabel/disk-c-games-disk-2-games2";
      keyFile = "/vault/luks.key";
      allowDiscards = true;
    };
  };
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" ];

  boot.kernelParams = lib.optionals (!isVM) [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

}
