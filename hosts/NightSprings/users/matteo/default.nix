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
    utm
    colima
    docker
    # Social
    element-desktop
    # Extra
    eza
    # Mine
    radiogogo
  ];

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
