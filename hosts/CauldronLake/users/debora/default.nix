{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../../shared/home-manager/firefox.nix

    ./gaming.nix
    ./gnome.nix
    ./flatpak.nix
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

  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;
  };

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
      nix-gc = ''
        nix-collect-garbage --delete-old;
        sudo nix-collect-garbage --delete-old;
        nix-store --optimize -v;
      '';
      update = ''
        cd /etc/nixos;
        git reset --hard;
        git clean -xdf;
        git pull;
        sudo nixos-rebuild boot;
        echo "Update complete, please reboot the computer";
      '';
    };
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
