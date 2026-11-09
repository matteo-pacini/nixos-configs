{ pkgs, ... }:
{
  imports = [
    ./zsh.nix
    ./git.nix
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
    # Window Management
    loopwm
  ];
  custom.nvf.enable = true;
  custom.nushell = {
    enable = true;
    darwinAliases = true;
  };
  custom.starship.enable = true;
  custom.ghostty.enable = true;
  custom.claude-code.enable = true;
  custom.codex.enable = true;
  custom.opencode.enable = true;
  custom.herdr.enable = true;
  custom.herdr.desktop = true;
  custom.herdr.workbench.enable = true;
  custom.herdr.workbench.fleet.enable = true;
  custom.herdr.workbench.spaceCards.enable = true;
  custom.hex.enable = true;
  custom.sleepmode.enable = true;
  custom.mpv.enable = true;

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
