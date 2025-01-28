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

  home.sessionVariables = {
    LOOP_SKIP_UPDATE_CHECK = 1;
  };

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    colorls
    tree
    # Development
    gh
    element-desktop
    # Music
    cmus
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
