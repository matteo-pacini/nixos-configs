{ ... }:
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

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
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
        launchctl unload /Users/matteo/Library/LaunchAgents/org.nixos.skhd.plist;
        sleep 1;
        launchctl load /Users/matteo/Library/LaunchAgents/org.nixos.skhd.plist;
      '';
      reloadYabai = ''
        launchctl unload /Users/matteo/Library/LaunchAgents/org.nixos.yabai.plist;
        sleep 1;
        launchctl load /Users/matteo/Library/LaunchAgents/org.nixos.yabai.plist;
      '';
      nix-gc = ''
        nix-collect-garbage --delete-old;
        sudo nix-collect-garbage --delete-old;
        nix-store --optimize -v;
      '';
    };
  };
}
