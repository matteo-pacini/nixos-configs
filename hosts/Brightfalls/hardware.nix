{
  pkgs,
  lib,
  modulesPath,
  isVM,
  ...
}:
let
  usbPartID = "usb-Kingston_DataTraveler_2.0_408D5CBF949DB471D95A0D4C-0:0-part1";
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ]
  ++ lib.optionals (isVM) [
    (modulesPath + "/virtualisation/qemu-guest-agent.nix")
  ];

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
  boot.kernelModules = lib.optionals (!isVM) [ "kvm-amd" ];

  boot.kernelParams = lib.optionals (!isVM) [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (!isVM) true;
  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.enableRedistributableFirmware = true;

  fileSystems."/" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-uuid/cfeb4539-1275-4bed-8713-637c6194e01a";
    fsType = "xfs";
    options = [
      "defaults"
      "noatime"
    ];
  };

  boot.initrd.luks.devices."root" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-uuid/5c7a8b8e-ed65-4820-a85e-0fb3cbe8a198";
    preLVM = false;
    allowDiscards = true;
    keyFile = "/key/brightfalls.bin";
    keyFileSize = 4096;
    fallbackToPassword = true;
    preOpenCommands = ''
      mkdir -m 0755 -p /key
      echo "Waiting for USB devices to settle..."
      sleep 5
      echo "Attempting to mount magic key..."
      mount -n -t vfat -o ro /dev/disk/by-id/${usbPartID} /key || {
        echo "No magic key found, continuing without it."
      }
    '';
    postOpenCommands = ''
      echo "Unmounting magic key..."
      umount /key
      rm -rf /key
    '';
  };

  fileSystems."/boot" = lib.mkIf (!isVM) {
    device = "/dev/disk/by-uuid/EF95-E69F";
    fsType = "vfat";
  };

  systemd.services."systemd-cryptsetup@" = lib.mkIf (!isVM) {
    path = with pkgs; [
      util-linux
      e2fsprogs
    ];
    overrideStrategy = "asDropin";
  };

  environment.etc.crypttab = lib.mkIf (!isVM) {
    text = ''
      home	/dev/Volumes/crypthome	/etc/luks/home.key	discard
      data  /dev/Volumes/cryptdata	/etc/luks/data.key	discard
      swap	/dev/Volumes/cryptswap	/dev/urandom		    swap,cipher=aes-xts-plain64,size=256,discard
      tmp		/dev/Volumes/crypttmp	  /dev/urandom		    tmp,cipher=aes-xts-plain64,size=256,discard
    '';
  };

  fileSystems."/home" = lib.mkIf (!isVM) {
    neededForBoot = false;
    device = "/dev/mapper/home";
    fsType = "xfs";
    mountPoint = "/home";
    options = [
      "defaults"
      "noatime"
    ];
  };

  fileSystems."/data" = lib.mkIf (!isVM) {
    neededForBoot = false;
    device = "/dev/mapper/data";
    fsType = "xfs";
    mountPoint = "/data";
    options = [
      "defaults"
      "noatime"
    ];
  };

  fileSystems."swap" = lib.mkIf (!isVM) {
    neededForBoot = false;
    device = "/dev/mapper/swap";
    fsType = "swap";
    mountPoint = "none";
    options = [ "sw" ];
  };

  fileSystems."/tmp" = lib.mkIf (!isVM) {
    neededForBoot = false;
    device = "/dev/mapper/tmp";
    fsType = "tmpfs";
    mountPoint = "/tmp";
    options = [ "defaults" ];
  };

  swapDevices = lib.mkIf (!isVM) [ { device = "/dev/disk/by-label/SWAP"; } ];

}
