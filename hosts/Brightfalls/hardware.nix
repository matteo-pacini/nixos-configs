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
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "mount-vault";
    };
    script = ''
      set -x
      echo "mount-vault: Starting vault mount service"
      mkdir -p /vault
      echo "mount-vault: Waiting for /dev/mapper/cryptvault to appear..."
      # Wait for device to be ready (should be immediate after cryptvault unlock)
      for i in {1..10}; do
        if [ -e /dev/mapper/cryptvault ]; then
          echo "mount-vault: Device /dev/mapper/cryptvault found"
          break
        fi
        echo "mount-vault: Attempt $i/10 - device not ready, waiting..."
        sleep 0.5
      done
      if [ ! -e /dev/mapper/cryptvault ]; then
        echo "mount-vault: ERROR - /dev/mapper/cryptvault not found after timeout" >&2
        ls -la /dev/mapper/ >&2
        exit 1
      fi
      echo "mount-vault: Mounting /dev/mapper/cryptvault at /vault..."
      if mount -t ext2 -o noatime,errors=remount-ro /dev/mapper/cryptvault /vault; then
        echo "mount-vault: Successfully mounted vault"
        ls -la /vault/
      else
        echo "mount-vault: ERROR - Failed to mount vault" >&2
        exit 1
      fi
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
