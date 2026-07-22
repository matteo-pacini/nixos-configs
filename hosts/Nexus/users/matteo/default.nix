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
  custom.opencode = {
    enable = true;
    profiles.kimi.enable = true;
    profiles.glm.enable = true;
  };

  dracula.eza.enable = true;
  dracula.fzf.enable = true;
  dracula.bat.enable = true;

  home.packages = with pkgs; [
    # Development
    gh
  ];

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
}
