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
  ];

  home.username = "matteo";
  home.homeDirectory = "/home/matteo";

  home.packages = with pkgs; [
    #Gnome
    gnomeExtensions.appindicator
    gnome.gnome-tweaks
    # GUI Apps
    _1password-gui
    # Virtualisation
    qemu
    quickemu
    # Video
    vlc
    # Custom packages
    reshade-steam-proton
    radiogogo
    # Gaming
    unstable.mangohud
    vulkan-tools
    mesa-demos
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

  home.file."scripts/mount_games.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      [ -d /home/matteo/Mounts ] || mkdir /home/matteo/Mounts
      [ -d /home/matteo/Mounts/Games ] || mkdir /home/matteo/Mounts/Games
      mount -t fuse.sshfs -o port=1788,idmap=user matteo@192.168.7.7:/diskpool/games /home/matteo/Mounts/Games
    '';
  };

  home.file."scripts/unmount_games.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      fusermount -u /home/matteo/Mounts/Games
    '';
  };

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
