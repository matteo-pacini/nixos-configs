{
  pkgs,
  inputs,
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
    ./virtualization.nix
    ./specialisations.nix
    ../shared/bluetooth.nix
    ../shared/linux/kernel.nix
  ];

  # Shared kernel configuration with BORE patches
  shared.kernel = {
    enable = true;
    useBorePatches = true;
  };

  # Nix & Nixpkgs

  nix = {
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # Enables use of `nix-shell -p ...` etc
    registry = {
      nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
    };
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

  # Disable suspend/hibernate (eGPU doesn't survive suspend)
  # This also hides the suspend option in GNOME's power menu
  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowSuspendThenHibernate=no
    AllowHybridSleep=no
  '';

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  system.stateVersion = "25.11";
}
