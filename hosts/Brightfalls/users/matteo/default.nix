{
  pkgs,
  lib,
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
    NIXOS_OZONE_WL = "1";
  }
  // lib.optionalAttrs (pkgs.stdenv.hostPlatform.isx86_64) {
    STEAM_EXTRA_COMPAT_TOOL_PATHS = "${config.home.homeDirectory}/.steam/root/compatibilitytools.d";
  };

  home.packages =
    with pkgs;
    [
      #Gnome
      gnomeExtensions.appindicator
      gnomeExtensions.dash-to-dock
      gnome-tweaks
      # Downloads
      aria2
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
      mangohud
      vulkan-tools
      mesa-demos
      # Other
      telegram-desktop
      element-desktop
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [
      # Gaming
      bottles
      pcsx2
      reshade-steam-proton
      heroic
      # Other
      discord
    ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
