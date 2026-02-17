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
    ./gaming.nix
    ./hardware.nix
    ./printer.nix
    ./virtualization.nix
    ./specialisations.nix
  ];

  custom.kernel = {
    enable = true;
    useBorePatches = true;
  };

  custom.nix-core = {
    enable = true;
    trustedUsers = [
      "matteo"
      "root"
    ];
    permittedInsecurePackages = [
      "qtwebengine-5.15.19"
    ];
  };

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
  ];

  custom.locale.enable = true;
  custom.bluetooth.enable = true;
  custom.fonts.enable = true;

  system.stateVersion = "25.11";
}
