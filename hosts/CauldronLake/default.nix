{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./audio.nix
    ./services.nix
    ./gaming.nix
    ./fonts.nix
    ../shared/bluetooth.nix
    ./printer.nix
    ./iphone.nix
  ];

  # Kernel

  boot.kernelPackages = pkgs.linuxPackages_6_11;

  environment.systemPackages = with pkgs; [ sshfs ];

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [
    "debora"
    "root"
  ];

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "uk";
  };

  system.stateVersion = "23.11";
}
