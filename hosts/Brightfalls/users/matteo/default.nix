{
  pkgs,
  lib,
  isVM,
  ...
}:
{
  imports =
    [

      ./gnome.nix
      ../../../shared/home-manager/firefox.nix
      ./git.nix
      ../../../shared/home-manager/vscode.nix
      ../../../shared/home-manager/emacs
      ./zsh.nix
    ]
    ++ lib.optionals (!isVM) [
      ./flatpak.nix
      ./gaming.nix
      ./mounts.nix
    ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages =
    with pkgs;
    [
      #Gnome
      gnomeExtensions.appindicator
      gnome-tweaks
      # Downloads
      aria
      # Security
      _1password-gui
      # Music
      # Social
      # Other
      nix-output-monitor
    ]
    ++ lib.optionals (!isVM) [
      # No need for these in a VM
      # Music
      cmus
      # Virtualisation
      qemu
      quickemu
      # Gaming
      reshade-steam-proton
      mangohud
      vulkan-tools
      mesa-demos
      bottles
      # Other
      miru
    ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
