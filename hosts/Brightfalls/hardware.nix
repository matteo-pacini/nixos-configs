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
  boot.initrd.kernelModules = lib.optionals (!isVM) [ "dm-snapshot" ];
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" ];

  boot.kernelParams = lib.optionals (!isVM) [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  # Vault must be mounted during initrd before other LUKS devices can access the keyfile
  fileSystems."/vault".neededForBoot = lib.mkIf (!isVM) true;

  boot.initrd.luks.devices."cryptvault" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-partlabel/disk-a-os-disk-vault";
    allowDiscards = true;
  };

  boot.initrd.luks.devices."cryptroot" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-partlabel/disk-a-os-disk-root";
    keyFile = "/vault/luks.key";
    allowDiscards = true;
  };

  boot.initrd.luks.devices."cryptgames1" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-partlabel/disk-b-games-disk-1-games1";
    keyFile = "/vault/luks.key";
    allowDiscards = true;
  };

  boot.initrd.luks.devices."cryptgames2" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-partlabel/disk-c-games-disk-2-games2";
    keyFile = "/vault/luks.key";
    allowDiscards = true;
  };

}
