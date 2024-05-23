{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.wallpapers.dracula;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  options.wallpapers.dracula = {
    enable = mkEnableOption "Activates the Dracula wallpaper on the first monitor";
  };

  config = mkIf cfg.enable {
    home.file."Pictures/wallpaper.png".source =
      if isDarwin
      then "${inputs.dracula-wallpaper}/first-collection/macos.png"
      else "${inputs.dracula-wallpaper}/first-collection/nixos.png";
  };
}
