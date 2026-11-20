{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./desktop.nix
    ./git.nix
    ./zsh.nix
    ./browser.nix
    ./services.nix
    ./gaming.nix
    ./hyprland
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
      aria2
      _1password-gui
      gh
      rotate-github-key
      nix-output-monitor
      qemu
      quickemu
      mangohud
      vulkan-tools
      mesa-demos
      prismlauncher
      telegram-desktop
      whatsie
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [
      bottles
      pcsx2
      reshade-linux
      heroic
      exiled-exchange-2
      path-of-building-poe2
      # Wine/Proton preload runtime
      linuwux-runtime
      discord
    ];

  custom.nvf.enable = true;
  custom.ghostty.enable = true;
  programs.ghostty.settings.background-opacity = lib.mkForce 0.85;
  custom.nushell.enable = true;
  custom.starship.enable = true;
  custom.claude-code.enable = true;
  custom.claude-code.chrome.enable = true;
  custom.codex.enable = true;
  custom.opencode.enable = true;
  custom.herdr.enable = true;
  custom.herdr.desktop = true;
  custom.herdr.workbench.enable = true;
  custom.herdr.workbench.nixpkgsPrs.enable = true;
  custom.herdr.workbench.spaceCards.enable = true;
  custom.hex.enable = true;
  custom.phone.scrcpy.enable = true;
  custom.mpv.enable = true;
  custom.mpv.jellyfinShim.enable = true;
  # The shim closes to the tray only when a tray host is up, and the
  # Quickshell bar is it.
  systemd.user.services.jellyfin-mpv-shim.Unit.After = [ "quickshell.service" ];

  dracula.eza.enable = true;
  dracula.fzf.enable = true;
  dracula.bat.enable = true;

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
