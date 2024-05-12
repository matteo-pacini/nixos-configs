{
  config,
  pkgs,
  inputs,
  lib,
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
    colorls
    tree
    unstable.yt-dlp
    # Mine
    radiogogo
  ];

  home.file."Brewfile".text = ''

    tap "homebrew/bundle"
    tap "homebrew/cask"
    tap "homebrew/core"

    cask_args appdir: '/Applications'
    cask '1password'
    cask 'firefox'
    cask 'mullvadvpn'
    cask 'dash'
    cask 'telegram'
    cask 'whatsapp'
    cask 'microsoft-teams'
    cask 'utm'
    cask 'zerotier-one'
    cask 'jellyfin-media-player'
  '';

  home.activation.brewUpdate =
    lib.hm.dag.entryAfter [
      "linkGeneration"
      "writeBoundary"
    ] ''
      export PATH="$PATH:/opt/homebrew/bin"
      $DRY_RUN_CMD brew bundle --file="$HOME/Brewfile" \
        --no-lock \
        --cleanup --zap \
        --verbose \
        install
    '';

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
