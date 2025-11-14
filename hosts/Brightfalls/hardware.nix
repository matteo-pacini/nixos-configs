{
  pkgs,
  lib,
  modulesPath,
  isVM,
  ...
}:
let
  # Hook to mount vault before unlocking devices that use the keyfile
  mountVaultHook = ''
    mkdir -p /vault
    mount /dev/mapper/cryptvault /vault
  '';

  # Hook to unmount vault after unlocking
  unmountVaultHook = ''
    umount /vault
    rmdir /vault
  '';
in
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

  # Mount vault before trying to decrypt root filesystem
  boot.initrd.postDeviceCommands = pkgs.lib.mkBefore (
    lib.optionalString (!isVM) ''
      echo "Mounting vault..."
      mkdir -m 0755 -p /vault
      mount -t ext2 -o ro /dev/mapper/cryptvault /vault
      echo "Vault mounted at /vault"
    ''
  );

  boot.initrd.luks.devices = lib.mkIf (!isVM) {
    cryptroot = {
      keyFile = lib.mkForce "/vault/luks.key";
      # If this is true the decryption is attempted before the postDeviceCommands can run
      preLVM = false;
    };
    cryptgames1 = {
      keyFile = lib.mkForce "/vault/luks.key";
    };
    cryptgames2 = {
      keyFile = lib.mkForce "/vault/luks.key";
    };
  };

}
