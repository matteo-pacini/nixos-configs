{ pkgs, ... }:
{
  imports = [
    ./git.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  custom.nvf.enable = true;
  custom.nvf.completion.enable = true;

  # Quadro P2000, 5 GB. 3B at Q8_0 (~3.3 GB) plus a q8_0 KV cache leaves
  # headroom; 7B at Q4_K_M would not fit alongside the cache.
  custom.code-completion-model = {
    enable = true;
    acceleration = "cuda";
    # Pascal, and nixpkgs only builds kernels for Turing and up.
    cudaCapabilities = [ "6.1" ];
    model.repo = "ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF";
    model.quant = "Q8_0";
    contextSize = 16384;
  };
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
