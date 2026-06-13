{ pkgs, inputs, ... }:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./gpu.nix
    ./hardware.nix
    ./hardware-extra.nix
    ./services
    ./snapraid.nix
    ./mdadm.nix
    ./storage-tuning.nix
  ];

  custom.kernel.enable = true;
  custom.nix-index.enable = true;

  custom.nix-core = {
    enable = true;
    trustedUsers = [
      "root"
      "matteo"
    ];
    extraPlatforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    # First SSD
    device = "/dev/disk/by-id/ata-CT2000MX500SSD1_2308E6B0D773";
    memtest86.enable = true;
    configurationLimit = 5;
  };

  environment.systemPackages = with pkgs; [
    terminus_font
    mergerfs
    mergerfs-tools
    snapraid
    htop
    nix-output-monitor
    screen
  ];

  custom.locale = {
    enable = true;
    consoleFont = "ter-v24n";
  };

  system.stateVersion = "26.05";
}
