{
  pkgs,
  config,
  ...
}:
{
  imports = [

    ../../../../modules/home-manager/firefox.nix

    ./gnome.nix
    ./git.nix
    ../../../shared/home-manager/vscode.nix
    ./zsh.nix
    ./browser.nix
    ./services.nix
    ./gaming.nix
    ./mounts.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOL_PATHS = "${config.home.homeDirectory}/.steam/root/compatibilitytools.d";
    NIXOS_OZONE_WL = "1";
  };

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnome-tweaks
    # Downloads
    aria
    # Security
    _1password-gui
    # Development
    gh
    # Other
    nix-output-monitor
    # Virtualisation
    qemu
    quickemu
    # Gaming
    reshade-steam-proton
    mangohud
    vulkan-tools
    mesa-demos
    bottles
    heroic
    # Other
    discord
    telegram-desktop
  ];

  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
}
