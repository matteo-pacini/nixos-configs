{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./git.nix
    ./text-editors.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Terminal
    iterm2
    # Development
    xcodes-app-bin
    # Virtualization
    utm
    # Extra
    eza
  ];

  home.file.".p10k.zsh".source = ./dot_p10k.zsh;

  home.file."Library/Preferences/com.googlecode.iterm2.plist".text = ''
    SUEnableAutomaticChecks = 0
  '';

  programs.zsh = {
    initExtra = ''
      source ~/.p10k.zsh
    '';
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
      }
    ];
    shellAliases = {
      l = "eza -lh";
      ll = "eza -lha";
      boom = "/opt/homebrew/bin/brew update && /opt/homebrew/bin/brew upgrade && /opt/homebrew/bin/brew cleanup -s";
    };
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
