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
      "15.2"
    ];
    active = "15.3";
  };

  home.activation.xcodeThemes = lib.hm.dag.entryAfter ["writeBoundary"] ''
    install -v -m 755 "${inputs.xcode-dracula-theme}/Dracula.xccolortheme" "${config.home.homeDirectory}/Library/Developer/Xcode/UserData/FontAndColorThemes/"
  '';
}
