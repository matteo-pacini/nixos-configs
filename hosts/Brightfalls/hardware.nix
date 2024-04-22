{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["xhci_pci" "ahci" "usbhid" "sd_mod"];
  boot.initrd.kernelModules = ["dm-snapshot"];
  boot.kernelModules = ["kvm-amd"];
  boot.extraModulePackages = [];
  boot.kernelPackages = pkgs.linuxPackages_6_8;

  boot.kernelParams = [
    "initcall_blacklist=acpi_cpufreq_init"
    "amd_pstate=active"
  ];

  hardware.cpu.amd.updateMicrocode = true;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    memtest86.enable = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/cfeb4539-1275-4bed-8713-637c6194e01a";
    fsType = "xfs";
    options = ["defaults" "noatime"];
  };

  boot.initrd.luks.devices."root".device = "/dev/disk/by-uuid/5c7a8b8e-ed65-4820-a85e-0fb3cbe8a198";
  boot.initrd.luks.devices."root".preLVM = false;
  boot.initrd.luks.devices."root".allowDiscards = true;

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/EF95-E69F";
    fsType = "vfat";
  };

  systemd.services."systemd-cryptsetup@" = {
    path = with pkgs; [util-linux e2fsprogs];
    overrideStrategy = "asDropin";
    serviceConfig = {
      ExecStartPost = ["${pkgs.systemd}/sbin/udevadm trigger /dev/mapper/%i"];
    };
  };

  environment.etc.crypttab.text = ''
    home	/dev/Volumes/crypthome	/etc/luks/home.key	discard
    data  /dev/Volumes/cryptdata	/etc/luks/data.key	discard
    swap	/dev/Volumes/cryptswap	/dev/urandom		    swap,cipher=aes-xts-plain64,size=256,discard
    tmp		/dev/Volumes/crypttmp	  /dev/urandom		    tmp,cipher=aes-xts-plain64,size=256,discard
  '';

  fileSystems."/home" = {
    neededForBoot = false;
    device = "/dev/mapper/home";
    fsType = "xfs";
    mountPoint = "/home";
    options = ["defaults" "noatime"];
  };

  fileSystems."/data" = {
    neededForBoot = false;
    device = "/dev/mapper/data";
    fsType = "xfs";
    mountPoint = "/data";
    options = ["defaults" "noatime"];
  };

  fileSystems."swap" = {
    neededForBoot = false;
    device = "/dev/mapper/swap";
    fsType = "swap";
    mountPoint = "none";
    options = ["sw"];
  };

  fileSystems."/tmp" = {
    neededForBoot = false;
    device = "/dev/mapper/tmp";
    fsType = "tmpfs";
    mountPoint = "/tmp";
    options = ["defaults"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
