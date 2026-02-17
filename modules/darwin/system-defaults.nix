{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.system-defaults;
in
{
  options.custom.system-defaults = {
    enable = lib.mkEnableOption "Shared macOS system defaults";
    touchIdSudo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Touch ID for sudo authentication";
    };
  };

  config = lib.mkIf cfg.enable {
    system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
    system.defaults.dock.magnification = true;
    system.defaults.dock.show-recents = false;
    system.defaults.finder.CreateDesktop = true;
    system.defaults.finder.AppleShowAllExtensions = true;
    security.pam.services.sudo_local.touchIdAuth = cfg.touchIdSudo;
  };
}
