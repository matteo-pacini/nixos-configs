{
  lib,
  pkgs,
  inputs,
  isVM,
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

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "qtwebengine-5.15.19"
    ];
  };

  # Kernel

  boot.kernelPackages = pkgs.linuxPackages_6_17;

  boot.kernelPatches =
    let
      # Use pkgs.linuxPackages_6_17.kernel.version instead of config.boot.kernelPackages.kernel.version
      # to avoid infinite recursion (boot.kernelPatches affects boot.kernelPackages)
      kernelVersion = lib.versions.majorMinor pkgs.linuxPackages_6_17.kernel.version;
      patchesDir = "${inputs.bore-scheduler-src}/patches/stable/linux-${kernelVersion}-bore";
    in
    lib.mapAttrsToList (name: _: {
      name = "bore-${name}";
      patch = "${patchesDir}/${name}";
    }) (builtins.readDir patchesDir);

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
      sshfs
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [
      steamtinkerlaunch
    ];

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  system.stateVersion = "25.05";
}
