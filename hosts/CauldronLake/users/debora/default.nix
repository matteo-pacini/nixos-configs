{ pkgs, ... }:
{
  imports = [
    ../../../shared/home-manager/firefox.nix

    ./gaming.nix
    ./gnome.nix
    ./flatpak.nix
    ./mounts.nix
    ./zsh.nix
  ];

  home.username = "debora";
  home.homeDirectory = "/home/debora";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome.gnome-tweaks
    # Browsers
    chromium
    # Security
    _1password-gui
    # Gaming
    unstable.mangohud
    vulkan-tools
    mesa-demos
    unstable.bottles
  ];

  home.file.".p10k.zsh".source = ./dot_p10k.zsh;

  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
