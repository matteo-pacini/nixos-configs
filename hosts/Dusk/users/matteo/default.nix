{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix

    ../../../shared/home-manager/firefox.nix
    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    # Wezterm fails on x86_64-darwin (#239384)
    #../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix

    ./dotfiles.nix
    ./git.nix
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
