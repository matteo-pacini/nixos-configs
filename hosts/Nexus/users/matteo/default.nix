{ pkgs, ... }:
{
  imports = [
    ./git.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  custom.nvf.enable = true;
  custom.zellij.enable = true;
  custom.starship.enable = true;
  custom.claude-code.enable = true;
  custom.codex.enable = true;
  custom.opencode.enable = true;
  custom.herdr.enable = true;
  custom.herdr.server = true;

  dracula.eza.enable = true;
  dracula.fzf.enable = true;
  dracula.bat.enable = true;

  home.packages = with pkgs; [
    # Development
    gh
    rotate-github-key
  ];

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
