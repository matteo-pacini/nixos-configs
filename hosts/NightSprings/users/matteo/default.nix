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

    ./dotfiles.nix
    ./git.nix
    ./xcodes.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Virtualization
    colima
    docker
    unstable.qemu
    # Extra
    tree
    unstable.yt-dlp
    # Development
    gh
    # Music
    cmus
    # Test
    zed-app
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
