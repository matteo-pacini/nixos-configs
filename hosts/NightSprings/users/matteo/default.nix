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
    gh
    rotate-github-key
    # Music
    jellyfin-tui
    # Window Management
    loopwm
  ];
  custom.nvf.enable = true;
  custom.starship.enable = true;
  custom.ghostty.enable = true;
  custom.claude-code.enable = true;
  custom.herdr.enable = true;
  custom.sleepmode.enable = true;
  custom.mpv.enable = true;
  custom.mpv.jellyfinShim.enable = true;

  home.stateVersion = "26.05";

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
