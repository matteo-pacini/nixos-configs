{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix
    ../../../../modules/home-manager/firefox.nix

    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix

    ../../../shared/home-manager/darwin/zsh.nix

    ./dotfiles.nix
    ./git.nix
    ./browser.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    tree
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
