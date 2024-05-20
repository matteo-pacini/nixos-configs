{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../../../modules/home-manager/darwin/xcodes.nix
    ../../../../modules/home-manager/darwin/dracula-wallpaper.nix
    ../../../../modules/home-manager/darwin/dracula-starship.nix

    ./dotfiles.nix
    ./git.nix
    ./text-editors.nix
    ./xcodes.nix
    ./terminal.nix
    ./zsh.nix
    ./firefox.nix
  ];

  home.username = "admin";
  home.homeDirectory = "/Users/admin";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Virtualization
    colima
    docker
    # Extra
    colorls
    tree
    # Other
    asciinema
    asciinema-agg
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
