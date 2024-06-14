{ pkgs, ... }:
{
  imports = [
    ./gnome.nix
    ../../../shared/home-manager/firefox.nix
    ./flatpak.nix
    ./git.nix
    ./text-editors.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome.gnome-tweaks
    # Downloads
    aria
    # Security
    _1password-gui
    # Music
    cmus
    # Social
    # Other
    nix-output-monitor
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
