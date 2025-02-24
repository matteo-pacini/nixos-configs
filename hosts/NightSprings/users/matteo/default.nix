{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix

    ../../../shared/home-manager/firefox.nix
    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix
    ../../../shared/home-manager/emacs

    ./dotfiles.nix
    ./git.nix
    ./xcodes.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.sessionVariables = {
    LOOP_SKIP_UPDATE_CHECK = 1;
  };

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    tree
    yt-dlp
    # Encription
    age
    # Development
    gh
    # DevOps
    flyctl
    # Music
    cmus
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
