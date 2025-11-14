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

  boot.initrd.systemd.enable = lib.mkIf (!isVM) true;

  boot.initrd.luks.devices = lib.mkIf (!isVM) {
    cryptroot = {
      keyFile = lib.mkForce "/vault/luks.key";
      fallbackToPassword = lib.mkForce false;
    };
    cryptgames1 = {
      keyFile = lib.mkForce "/vault/luks.key";
      fallbackToPassword = lib.mkForce false;
    };
    cryptgames2 = {
      keyFile = lib.mkForce "/vault/luks.key";
      fallbackToPassword = lib.mkForce false;
    };
  };

  boot.initrd.systemd.mounts = lib.optionals (!isVM) [
    {
      what = "/dev/mapper/cryptvault";
      where = "/vault";
      type = "ext2";
      options = "ro";
      requiredBy = [
        "systemd-cryptsetup@cryptroot.service"
        "systemd-cryptsetup@cryptgames1.service"
        "systemd-cryptsetup@cryptgames2.service"
      ];
      after = [ "systemd-cryptsetup@cryptvault.service" ];
      before = [
        "systemd-cryptsetup@cryptroot.service"
        "systemd-cryptsetup@cryptgames1.service"
        "systemd-cryptsetup@cryptgames2.service"
      ];
    }
  ];

}
