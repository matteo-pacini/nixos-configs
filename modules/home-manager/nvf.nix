{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.nvf;
in
{
  options.custom.nvf = {
    enable = lib.mkEnableOption "Neovim configuration via nvf";
  };

  config = lib.mkIf cfg.enable {
    programs.nvf = {
      enable = true;
      defaultEditor = true;
      settings.imports = [ ../nvf ];
    };
  };
}
