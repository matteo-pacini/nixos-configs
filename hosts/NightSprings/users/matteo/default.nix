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

    ../../../shared/home-manager/firefox.nix
    ../../../shared/home-manager/darwin/starship.nix

    ./dotfiles.nix
    ./git.nix
    ./text-editors.nix
    ./xcodes.nix
    ./terminal.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Virtualization
    colima
    docker
    # Extra
    colorls
    tree
    unstable.yt-dlp
    # Mine
    radiogogo
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
