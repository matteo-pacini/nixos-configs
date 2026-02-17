{
  pkgs,
  lib,
  ...
}:

{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
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

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    forceOverwriteSettings = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "http://nexus-ts.walrus-draconis.ts.net:8888";
      search_mode = "fuzzy";
      filter_mode = "global";
      filter_mode_shell_up_key_binding = "directory";
      style = "compact";
      inline_height = 30;
      enter_accept = true;
      update_check = false;
      show_help = false;
      workspaces = true;
      secrets_filter = true;
      history_filter = [
        "^rm " "^shred " "^dd "
      ];
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = false;
    shellAliases = {
      ls = "${pkgs.eza}/bin/${pkgs.eza.meta.mainProgram} --icons --color=always";
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
