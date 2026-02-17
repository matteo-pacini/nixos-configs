{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.locale;
in
{
  options.custom.locale = {
    enable = lib.mkEnableOption "Shared locale and timezone configuration";
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/London";
      description = "System timezone";
    };
    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_GB.UTF-8";
      description = "Default system locale";
    };
    consoleKeyMap = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "Console keyboard layout";
    };
    consoleFont = lib.mkOption {
      type = lib.types.str;
      default = "Lat2-Terminus16";
      description = "Console font";
    };
  };

  config = lib.mkIf cfg.enable {
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = cfg.defaultLocale;
    console = {
      font = cfg.consoleFont;
      keyMap = cfg.consoleKeyMap;
    };
  };
}
