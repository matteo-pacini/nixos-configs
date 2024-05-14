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
      "15.4"
    ];
    active = "15.4";
  };

  home.activation.xcodeThemes = lib.hm.dag.entryAfter ["writeBoundary"] ''
    THEMES_DIR="${config.home.homeDirectory}/Library/Developer/Xcode/UserData/FontAndColorThemes"
    [ -d "$THEMES_DIR" ] || mkdir -p "$THEMES_DIR"
    cd "$THEMES_DIR"
    find . -type l -delete
    $DRY_RUN_CMD ln -s "${inputs.xcode-dracula-theme}/Dracula.xccolortheme" .
  '';
}
