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
    ./git.nix
    ./text-editors.nix
    ./mounts.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome.gnome-tweaks
    # Security
    _1password-gui
    # Virtualisation
    qemu
    quickemu
    # Custom packages
    reshade-steam-proton
    radiogogo
    # Gaming
    unstable.mangohud
    vulkan-tools
    mesa-demos
    unstable.bottles
    # Music
    cmus
    # Social
    # Other
    eza
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
      l = "eza -lh";
      ll = "eza -lha";
    };
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
