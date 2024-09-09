{ pkgs, ... }:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./gpu.nix
    ./hardware.nix
    ./hardware-extra.nix
    ./services
    ./snapraid.nix
  ];

  nix.package = pkgs.nixVersions.nix_2_24;

  nix.settings.trusted-users = [
    "matteo"
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_9;

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    # First SSD
    device = "/dev/disk/by-id/ata-CT2000MX500SSD1_2308E6B0D773";
    memtest86.enable = true;
  };

  environment.systemPackages = with pkgs; [
    terminus_font
    mergerfs
    mergerfs-tools
    snapraid
    htop
    nix-output-monitor
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "ter-v24n";
    keyMap = "us";
  };

  system.stateVersion = "23.11";
}
