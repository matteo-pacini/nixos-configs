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
    [ -f "Catppuccin Frappé.xccolortheme" ] || ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Frappé.xccolortheme" .
    [ -f "Catppuccin Latte.xccolortheme" ] || ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Latte.xccolortheme" .
    [ -f "Catppuccin Macchiato.xccolortheme" ] || ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Macchiato.xccolortheme" .
    [ -f "Catppuccin Mocha.xccolortheme" ] || ln -s "${inputs.xcode-catppuccin-theme}/dist/Catppuccin Mocha.xccolortheme" .
  '';
}
