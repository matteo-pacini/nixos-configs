{ pkgs, ... }:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./gpu.nix
    ./hardware.nix
    ./hardware-extra.nix
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_9;

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    device = "/dev/disk/by-uuid/2f76e63a-859a-4721-9101-b278008d6f71";
    memtest86.enable = true;
  };

  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    snapraid
    htop
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
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  system.stateVersion = "23.11";
}
