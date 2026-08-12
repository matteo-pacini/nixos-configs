{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.ghostty;
in
{
  options.custom.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
      enableZshIntegration = true;
      settings = {
        font-family = "FiraCode Nerd Font";
        font-size = 15;
        background-opacity = 0.9;
        background-blur = 30;
        theme = "Dracula";
        macos-titlebar-style = "hidden";
        confirm-close-surface = false;
        keybind = [
          "ctrl+cmd+f=toggle_fullscreen"
          "shift+enter=text:\\x1b\\r"
        ];
      };
    };
  };
}
