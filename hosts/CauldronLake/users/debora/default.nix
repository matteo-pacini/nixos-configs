{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./gaming.nix
    ./gnome.nix
    ./firefox.nix
    ./flatpak.nix
    ./text-editors.nix
    ./mounts.nix
  ];

  home.username = "debora";
  home.homeDirectory = "/home/debora";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome.gnome-tweaks
    # Security
    _1password-gui
    # Gaming
    unstable.mangohud
    vulkan-tools
    mesa-demos
    unstable.bottles
  ];

  home.file.".p10k.zsh".source = ./dot_p10k.zsh;

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
    };
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
