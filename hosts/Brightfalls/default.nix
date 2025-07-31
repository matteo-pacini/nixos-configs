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
    ./gaming.nix
    ./hardware.nix
    ./printer.nix
    ../shared/bluetooth.nix
  ];

  # Nix & Nixpkgs

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "matteo"
        "root"
      ];
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Kernel

  boot.kernelPackages = pkgs.linuxPackages_6_15;

  # Boot loader

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    memtest86.enable = pkgs.stdenv.hostPlatform.isx86;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # System Packages

  environment.systemPackages = with pkgs; [
    sshfs
    steamtinkerlaunch
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
