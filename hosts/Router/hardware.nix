{
  config,
  lib,
  ...
}:

{
  boot.initrd.availableKernelModules = [
    "ehci_pci"
    "ahci"
    "megaraid_sas"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/37aac0fb-8bfb-41a9-9c95-d1099bb2cf8a";
    fsType = "xfs";
  };

  zramSwap = {
    enable = true;
    swapDevices = 1;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
