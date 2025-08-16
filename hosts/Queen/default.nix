{
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./audio
    ./services.nix
    ./graphics.nix
    ./fonts.nix
    ./hardware.nix
    ./printer.nix
    ../shared/bluetooth.nix
    ./openssh.nix
  ];

  # Nix & Nixpkgs

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "antonella"
        "root"
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Kernel

  boot.kernelPackages = pkgs.linuxPackages_6_16;

  # Boot loader

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    memtest86.enable = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # System Packages

  environment.systemPackages = [ ];

  # Timezone and locale

  time.timeZone = "Europe/Rome";

  i18n.defaultLocale = "it_IT.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "it";
  };

  system.stateVersion = "23.11";
}
