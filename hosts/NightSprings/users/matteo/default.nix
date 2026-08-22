{ pkgs, ... }:
{
  imports = [
    ./zsh.nix
    ./git.nix
    ./xcodes.nix
    ./browser.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    rsync
    # Extra
    tree
    yt-dlp
    mosh
    # Encription
    age
    # Development
    gh
    rotate-github-key
    # Music
    jellyfin-tui
    # Window Management
    loopwm
  ];
  custom.nvf.enable = true;
  custom.nvf.completion.enable = true;

  # M1 Max, 64 GB unified. Qwen3-Coder-30B-A3B at Q4_K_M is ~17.3 GB and
  # MoE, so it stays fast despite the size.
  custom.code-completion-model = {
    enable = true;
    model.repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
  };
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

  dracula = {
    wallpaper.enable = true;
    eza.enable = true;
    xcode.enable = true;
    fzf.enable = true;
    bat.enable = true;
    firefox.enable = true;
  };
}
