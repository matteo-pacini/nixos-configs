{
  config,
  lib,
  pkgs,
  inputs,
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

  boot.kernelPackages = pkgs.linuxPackages_6_17;

  environment.systemPackages = with pkgs; [ sshfs ];

  nixpkgs.config.allowUnfree = true;

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
        "debora"
        "root"
      ];
    };
  };

  # Timezone and locale

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "uk";
  };

  system.stateVersion = "23.11";
}
