{
  isVM,
  lib,
  pkgs,
  ...
}:
{
  imports =
    [
      ./networking.nix
      ./users.nix
      ./desktop.nix
      ./audio.nix
      ./services.nix
      ./graphics.nix
      ./fonts.nix
    ]
    ++ lib.optionals (!isVM) [
      ./gaming.nix
      ./hardware.nix
      ./printer.nix
      ../shared/bluetooth.nix
    ]
    ++ lib.optionals (isVM) [ /etc/nixos/hardware-configuration.nix ];

  boot.kernelPackages = pkgs.linuxPackages_6_9;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    memtest86.enable = pkgs.stdenv.hostPlatform.isx86;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  environment.systemPackages =
    with pkgs;
    [

    ]
    ++ lib.optionals (!isVM) [ sshfs ];

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
