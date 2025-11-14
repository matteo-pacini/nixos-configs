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

  boot.supportedFilesystems = [ "btrfs" ];
  boot.initrd.systemd.enable = lib.mkIf (!isVM) true;

  # Use keyfile from vault to unlock the root filesystem in initrd
  # The vault must be unlocked first (with password), then its keyfile is used for root
  boot.initrd.luks.devices.cryptroot = lib.mkIf (!isVM) {
    keyFile = lib.mkForce "/vault/luks.key";
  };

  # Mount the vault in the initrd so /vault/luks.key is available to unlock root
  # This service runs after cryptvault is unlocked and before cryptroot needs the keyfile
  boot.initrd.systemd.services.mount-vault = lib.mkIf (!isVM) {
    description = "Mount vault partition to access LUKS keyfile";
    wantedBy = [ "initrd.target" ];
    before = [ "systemd-cryptsetup@cryptroot.service" ];
    after = [ "systemd-cryptsetup@cryptvault.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /vault
      mount -t ext2 /dev/mapper/cryptvault /vault
    '';
  };

  # Configure post-boot unlocking of games disks using the same keyfile
  environment.etc."crypttab" = lib.mkIf (!isVM) {
    text = ''
      cryptgames1 /dev/disk/by-id/ata-Samsung_SSD_850_PRO_512GB_S250NXAG978494H-part1 /vault/luks.key luks,discard
      cryptgames2 /dev/disk/by-id/ata-Samsung_SSD_840_PRO_Series_S1ATNSADA34160X-part1 /vault/luks.key luks,discard
    '';
  };

}
