{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/firefox.nix

    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix

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
    # Social
    # element-desktop - broken on darwin, requires Xcode 26+ actool
    # Tracking: https://github.com/NixOS/nixpkgs/pull/486275
    # Window management
    loopwm
  ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    vscode.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
    firefox.enable = true;
  };
}
