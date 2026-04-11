{ pkgs, ... }:
{
  imports = [
    ./zsh.nix
    ./git.nix
    ./xcodes.nix
    ./browser.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    rsync
    # Extra
    tree
    yt-dlp
    mosh
    # Encription
    age
    # Development
    claude-code
    gh
    # Social
    # element-desktop - broken on darwin, requires Xcode 26+ actool
    # Tracking: https://github.com/NixOS/nixpkgs/pull/486275
    # Music
    jellyfin-desktop
    jellyfin-tui
    # Window Management
    loopwm
  ];
  custom.nvf.enable = true;
  custom.tmux.enable = true;
  custom.starship.enable = true;
  custom.wezterm.enable = true;

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
    firefox.enable = true;
  };
}
