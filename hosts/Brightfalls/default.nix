{
  config,
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
    # Substituter + auth for pulling from the private attic cache
    atticCache = {
      enable = true;
      netrcFile = config.age.secrets."brightfalls/attic-netrc".path;
    };
  };

  # Boot loader
  boot.loader.systemd-boot = {
    enable = true;
    memtest86.enable = pkgs.stdenv.hostPlatform.isx86;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  # System Packages

  environment.systemPackages = with pkgs; [
    sshfs
  ];

  custom.locale.enable = true;
  custom.bluetooth.enable = true;
  custom.fonts.enable = true;
  custom.nix-index.enable = true;

  system.stateVersion = "26.05";
}
