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

  # Nix & Nixpkgs

  nix = {
    package = pkgs.nixVersions.nix_2_22;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-platforms = [ "aarch64-linux" ];
      trusted-users = [
        "matteo"
        "root"
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Kernel

  boot.kernelPackages = pkgs.linuxPackages_6_10;

  # Boot loader

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    memtest86.enable = pkgs.stdenv.hostPlatform.isx86;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # System Packages

  environment.systemPackages =
    with pkgs;
    [

    ]
    ++ lib.optionals (!isVM) [ sshfs ];

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  system.stateVersion = "23.11";
}
