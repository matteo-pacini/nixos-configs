{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./zsh.nix
    ./git.nix
    ./browser.nix
  ];

  home.username = "matteo.pacini";
  home.homeDirectory = "/Users/matteo.pacini";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Extra
    tree
    # Development
    tokscale
    gh
    # Window Management
    loopwm
    # Music
    jellyfin-tui
  ];

  custom.nvf.enable = true;
  custom.zellij.enable = true;
  custom.vscode.enable = true;
  custom.starship.enable = true;
  custom.wezterm.enable = true;
  custom.claude-code.enable = true;
  custom.opencode.enable = true;
  custom.mpv.enable = true;
  custom.mpv.jellyfinShim.enable = true;

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.zsh.shellAliases = {
    c = "${lib.getExe config.programs.vscode.package}";
    cr = "${lib.getExe config.programs.vscode.package} -r";
  };

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    vscode.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
    firefox.enable = true;
  };
}
