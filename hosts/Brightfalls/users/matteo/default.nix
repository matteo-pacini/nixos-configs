{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./gaming.nix
    ./gnome.nix
    ../../../shared/home-manager/firefox.nix
    ./flatpak.nix
    ./git.nix
    ./text-editors.nix
    ./mounts.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    pkgs.unstable.gnomeExtensions.pop-shell
    gnome.gnome-tweaks
    # Downloads
    aria
    # Security
    _1password-gui
    # Virtualisation
    qemu
    quickemu
    # Custom packages
    reshade-steam-proton
    # Gaming
    fixed-unstable-mangohud
    vulkan-tools
    mesa-demos
    unstable.bottles
    # Music
    cmus
    # Social
    # Other
    nix-output-monitor
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
