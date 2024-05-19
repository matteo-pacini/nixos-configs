{
  config,
  pkgs,
  inputs,
  ...
}: {
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
    defaultOptions = [
      "--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9"
      "--color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9"
      "--color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6"
      "--color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"
      "--preview 'bat --color=always {}'"
    ];
  };

  programs.bat = {
    enable = true;
    themes = {
      dracula = {
        src = inputs.sublime-dracula-theme;
        file = "Dracula.tmTheme";
      };
    };
    config = {
      theme = "Dracula";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    shellAliases = {
      ls = "colorls --dark";
      reloadDock = ''
        defaults write com.apple.dock ResetLaunchPad -bool true;
        killall Dock;
        defaults write com.apple.dock ResetLaunchPad -bool false
      '';
      reloadSkhd = ''
        launchctl unload ${config.home.homeDirectory}/Library/LaunchAgents/org.nixos.skhd.plist;
        sleep 1;
        launchctl load ${config.home.homeDirectory}/Library/LaunchAgents/org.nixos.skhd.plist;
      '';
      reloadYabai = ''
        launchctl unload ${config.home.homeDirectory}/Library/LaunchAgents/org.nixos.yabai.plist;
        sleep 1;
        launchctl load ${config.home.homeDirectory}/Library/LaunchAgents/org.nixos.yabai.plist;
      '';
      nix-gc = ''
        nix-collect-garbage --delete-old;
        sudo nix-collect-garbage --delete-old;
        nix-store --optimize -v;
      '';
    };
  };
}
