{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../../../modules/home-manager/darwin/xcodes.nix

    ./git.nix
    ./text-editors.nix
    ./xcodes.nix
    ./terminal.nix
    ./zsh.nix
  ];

  home.username = "matteo";
  home.homeDirectory = "/Users/matteo";

  home.packages = with pkgs; [
    # Basic utilities
    coreutils
    # Virtualization
    colima
    docker
    # Extra
    tree
    eza
    unstable.yt-dlp
    # Mine
    radiogogo
  ];

  home.file."Brewfile".text = ''
    cask_args appdir: '/Applications'
    cask '1password'
    cask 'firefox'
    cask 'mullvadvpn'
    cask 'dash'
    cask 'telegram-desktop'
    cask 'whatsapp'
    cask 'microsoft-teams'
    cask 'utm'
    cask 'zerotier-one'
  '';

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
