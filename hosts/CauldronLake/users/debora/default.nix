{ pkgs, ... }:
{
  imports = [
    ./gaming.nix
    ./gnome.nix
    ./flatpak.nix
    ./mounts.nix
    ./zsh.nix
    ./browser.nix
  ];

  home.username = "debora";
  home.homeDirectory = "/home/debora";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome-tweaks
    # Browsers
    chromium
    # Security
    _1password-gui
    # Gaming
    mangohud
    vulkan-tools
    mesa-demos
    bottles
  ];

  custom.starship.enable = true;

  dracula.eza.enable = true;
  dracula.fzf.enable = true;
  dracula.bat.enable = true;

  programs.git = {
    enable = true;
    # package = pkgs.gitAndTools.gitFull;
  };

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
