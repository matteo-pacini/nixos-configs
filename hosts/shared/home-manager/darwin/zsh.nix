{
  pkgs,
  config,
  lib,
  ...
}:

{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.autojump = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [ "--preview 'bat --color=always {}'" ];
  };

  programs.bat = {
    enable = true;
  };

  programs.ripgrep = {
    enable = true;
  };

  programs.tmux = {
    shell = "${pkgs.zsh}/bin/zsh";
    enable = true;
    clock24 = true;
    terminal = "tmux-256color";
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = dracula;
        extraConfig = ''
          set -g @dracula-show-battery true
          set -g @dracula-show-powerline true
          set -g @dracula-refresh-rate 10
          set -g @dracula-show-fahrenheit false
          set -g @dracula-fixed-location "Royal Tunbridge Wells"
        '';
      }
    ];

    extraConfig = ''
      set -g mouse on
      set-option -g default-command ''${SHELL}
      set-option -g default-shell ''${SHELL}
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    shellAliases = {
      ls = "${pkgs.eza}/bin/${pkgs.eza.meta.mainProgram} --icons --color=always";
      c = "${lib.getExe config.programs.vscode.package}";
      cr = "${lib.getExe config.programs.vscode.package} -r";
      suggestions_off = "ZSH_AUTOSUGGEST_HISTORY_IGNORE=*";
      suggestions_on = "unset ZSH_AUTOSUGGEST_HISTORY_IGNORE";
      reloadDock = ''
        defaults write com.apple.dock ResetLaunchPad -bool true;
        killall Dock;
        defaults write com.apple.dock ResetLaunchPad -bool false
      '';
      nix-gc = ''
        nix-collect-garbage --delete-old;
        sudo nix-collect-garbage --delete-old;
        nix-store --optimize -v;
      '';
    };
  };
}
