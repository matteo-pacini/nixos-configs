{
  config,
  pkgs,
  inputs,
  ...
}: {
  home.file.".p10k.zsh".source = ./dot_p10k.zsh;

  programs.zsh = {
    initExtra = ''
      source ~/.p10k.zsh
    '';
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
    shellAliases = {
      l = "eza -lh";
      ll = "eza -lha";
      refreshDock = ''
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
    };
  };
}
