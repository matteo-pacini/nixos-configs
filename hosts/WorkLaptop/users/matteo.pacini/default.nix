{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/firefox.nix

    ../../../shared/home-manager/vscode.nix
    ./vscode.nix

    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix

    ./git.nix
    ./browser.nix
  ];

  home.username = "matteo.pacini";
  home.homeDirectory = "/Users/matteo.pacini";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    tree
    # Development
    gh
    # Window Management
    loopwm
  ];

  home.stateVersion = "23.11";

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
