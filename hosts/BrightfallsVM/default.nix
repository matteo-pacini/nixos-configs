{ pkgs, modulesPath, ... }:
{
  imports = [
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./audio.nix
    ./services.nix
    ./fonts.nix
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  boot.kernelPackages = pkgs.linuxPackages_6_9;

  environment.systemPackages = [ ];

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
