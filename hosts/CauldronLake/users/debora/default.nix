{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/firefox.nix

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

  home.file.".p10k.zsh".source = ./dot_p10k.zsh;

  programs.git = {
    enable = true;
    # package = pkgs.gitAndTools.gitFull;
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
