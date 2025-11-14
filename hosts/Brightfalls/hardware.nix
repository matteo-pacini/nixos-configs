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
      keyFile = lib.mkForce "/vault/luks.key:/dev/mapper/cryptvault";
    };
    cryptgames1 = {
      keyFile = lib.mkForce "/vault/luks.key:/dev/mapper/cryptvault";
    };
    cryptgames2 = {
      keyFile = lib.mkForce "/vault/luks.key:/dev/mapper/cryptvault";
    };
  };

  fileSystems = lib.mkIf (!isVM) {
    "/vault".neededForBoot = true;
  };

}
