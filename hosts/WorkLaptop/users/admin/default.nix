{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix

    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix
    ../../../shared/home-manager/emacs

    ./dotfiles.nix
    ./git.nix
    ./xcodes.nix
    ./firefox.nix
  ];

  home.username = "admin";
  home.homeDirectory = "/Users/admin";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    colorls
    tree
    # Window Manager
    loopwm
    # Development
    gh
    # Music
    cmus
    # Nix
    attic-client
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
