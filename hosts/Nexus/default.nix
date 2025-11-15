{ pkgs, inputs, ... }:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./gpu.nix
    ./hardware.nix
    ./hardware-extra.nix
    ./services
    ./snapraid.nix
    ../shared/linux/kernel.nix
  ];

  # Shared kernel configuration (no BORE patches)
  shared.kernel.enable = true;

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
        "root"
        "matteo"
      ];
      extra-platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    # First SSD
    device = "/dev/disk/by-id/ata-CT2000MX500SSD1_2308E6B0D773";
    memtest86.enable = true;
  };

  environment.systemPackages = with pkgs; [
    terminus_font
    mergerfs
    mergerfs-tools
    snapraid
    htop
    nix-output-monitor
    screen
  ];

  nixpkgs.config.allowUnfree = true;

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "ter-v24n";
    keyMap = "us";
  };

  system.stateVersion = "25.11";
}
