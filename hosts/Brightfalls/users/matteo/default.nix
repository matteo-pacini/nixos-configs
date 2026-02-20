{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./gnome.nix
    ./git.nix
    ./zsh.nix
    ./browser.nix
    ./services.nix
    ./gaming.nix
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
      gnomeExtensions.paperwm
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
      prismlauncher
      # Other
      telegram-desktop
      element-desktop
      # Music
      jellyfin-tui
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

  custom.nvf.enable = true;
  custom.tmux.enable = true;
  custom.starship.enable = true;

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
