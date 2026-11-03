{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;
in
{
  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.herdr-core ] ++ lib.optional cfg.desktop pkgs.herdr-desktop;

    # Offered in the desktop app's theme picker. Only the theme file is managed:
    # the picked theme lives in herdr-app's own writable layout state.
    xdg.configFile."herdr-app/themes/dracula.json" = lib.mkIf cfg.desktop {
      source = ./herdr/dracula.json;
    };
  };
}
