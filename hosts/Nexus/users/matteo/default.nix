{ pkgs, ... }:
{
  imports = [
    ./git.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  custom.nvf.enable = true;
  custom.tmux.enable = true;

  home.packages = [ ];

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
