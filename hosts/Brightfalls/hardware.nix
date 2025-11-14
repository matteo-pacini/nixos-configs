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
  boot.initrd.supportedFilesystems = lib.optionals (!isVM) [ "ext2" ];
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" ];

  boot.kernelParams = lib.optionals (!isVM) [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  boot.supportedFilesystems = [ "btrfs" ];

  boot.initrd.systemd.enable = lib.mkIf (!isVM) true;

  boot.initrd.luks.devices = lib.mkIf (!isVM) {

    cryptroot.keyFile = lib.mkForce "/vault/luks.key";
  };

  # Mount the *decrypted* vault to /vault inside initrd
  boot.initrd.systemd.mounts = lib.mkIf (!isVM) [
    {
      what = "/dev/mapper/cryptvault";
      where = "/vault";
      type = "ext2";
      options = [
        "noatime"
        "errors=remount-ro"
      ];
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@cryptvault.service" ];
    }
  ];

  fileSystems = lib.mkIf (!isVM) {
    "/vault" = {
      neededForBoot = true;
    };
    "/mnt/games1" = {
      neededForBoot = false;
    };
    "/mnt/games2" = {
      neededForBoot = false;
    };
  };

  environment.etc."crypttab" = lib.mkIf (!isVM) {
    text = ''
      cryptgames1 /dev/disk/by-id/ata-Samsung_SSD_850_PRO_512GB_S250NXAG978494H-part1 /vault/luks.key luks,discard
      cryptgames2 /dev/disk/by-id/ata-Samsung_SSD_840_PRO_Series_S1ATNSADA34160X-part1 /vault/luks.key luks,discard
    '';
  };

}
