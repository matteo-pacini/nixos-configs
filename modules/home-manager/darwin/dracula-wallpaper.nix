{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.wallpapers.dracula;
in {
  options.wallpapers.dracula = {
    enable = mkEnableOption "Activates the Dracula wallpaper on the first monitor";
  };

  config = mkIf cfg.enable {
    home.file."Pictures/wallpaper.png".source = "${inputs.dracula-wallpaper}/first-collection/macos.png";
  };
}
