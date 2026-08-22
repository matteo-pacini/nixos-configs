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
    gh
    rotate-github-key
    # Window Management
    loopwm
    # Music
    jellyfin-tui
  ];

  custom.nvf.enable = true;
  custom.nvf.completion.enable = true;

  # M4 Pro, 24 GB unified. 7B at Q4_K_M (~4.7 GB) plus a q8_0 KV cache sits
  # well inside the default Metal VRAM cap.
  custom.code-completion-model = {
    enable = true;
    model.repo = "QuantFactory/Qwen2.5-Coder-7B-GGUF";
  };
  custom.vscode.enable = true;
  custom.starship.enable = true;
  custom.ghostty.enable = true;
  custom.claude-code.enable = true;
  custom.codex.enable = true;
  custom.opencode.enable = true;
  custom.herdr.enable = true;
  custom.sleepmode.enable = true;
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
