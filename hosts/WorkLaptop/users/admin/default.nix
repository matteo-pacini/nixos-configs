{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix

    ../../../shared/home-manager/darwin/starship.nix

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
    # Development
    gh
    # Music
    cmus
    # Other
    asciinema
    asciinema-agg
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
