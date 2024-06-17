{pkgs, ...}: {
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/darwin/xcodes.nix

    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix

    ./dotfiles.nix
    ./git.nix
    ./xcodes.nix
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
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
