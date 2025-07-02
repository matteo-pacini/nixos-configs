{ pkgs, ... }:
{
  imports = [
    ./networking.nix
    ./hardware.nix
    ./users.nix
    ./openssh.nix
    ./services
  ];

  nix.settings.trusted-users = [
    "matteo"
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_15;

  boot.kernel = {
    sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    device = "/dev/sda";
    memtest86.enable = true;
  };

  environment.systemPackages = with pkgs; [
    terminus_font
    htop
    nix-output-monitor
    screen
    restic
    age
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
