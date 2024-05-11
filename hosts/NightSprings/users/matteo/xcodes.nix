{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  programs.xcodes = {
    enable = true;
    useAria = true;
    versions = [
      "15.3"
      "15.4 Release Candidate"
    ];
    active = "15.3";
  };

  home.activation.xcodeThemes = lib.hm.dag.entryAfter ["writeBoundary"] ''
    THEMES_DIR="${config.home.homeDirectory}/Library/Developer/Xcode/UserData/FontAndColorThemes"
    [ -d "$THEMES_DIR" ] || mkdir -p "$THEMES_DIR"
    cd "$THEMES_DIR"
    find . -type l -delete
    $DRY_RUN_CMD ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Frappé.xccolortheme" .
    $DRY_RUN_CMD ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Latte.xccolortheme" .
    $DRY_RUN_CMD ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Macchiato.xccolortheme" .
    $DRY_RUN_CMD ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Mocha.xccolortheme" .
  '';
}
