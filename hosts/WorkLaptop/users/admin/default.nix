{ pkgs, ... }:
{
  imports = [
    ../../../../modules/home-manager/dracula.nix
    ../../../../modules/home-manager/firefox.nix

    ../../../shared/home-manager/vscode.nix
    ../../../shared/home-manager/darwin/starship.nix
    ../../../shared/home-manager/darwin/terminal.nix
    ../../../shared/home-manager/darwin/zsh.nix

    ./git.nix
    ./xcodes.nix
    ./browser.nix
  ];

  home.username = "admin";
  home.homeDirectory = "/Users/admin";

  home.sessionVariables = {
    LOOP_SKIP_UPDATE_CHECK = 1;
  };

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    macmon
    # Extra
    colorls
    tree
    mosh
    # Development
    gh
    element-desktop
    # Music
    cmus
    # Other
    loopwm
  ];

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    vscode.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
    firefox.enable = true;
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
