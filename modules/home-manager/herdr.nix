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
  };
}
