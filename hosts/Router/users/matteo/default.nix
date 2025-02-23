{ pkgs, ... }:
{
  imports = [

    ./git.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = [ ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
