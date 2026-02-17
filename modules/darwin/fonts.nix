{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.fonts;
in
{
  options.custom.fonts = {
    enable = lib.mkEnableOption "Font configuration";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional font packages to install";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = [ pkgs.nerd-fonts.fira-code ] ++ cfg.extraPackages;
  };
}
