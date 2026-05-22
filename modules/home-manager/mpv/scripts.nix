{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.mpv;
in
{
  config = lib.mkIf cfg.enable {
    programs.mpv.scriptOpts = {
      thumbfast = {
        max_height = 200;
        max_width = 200;
        tone_mapping = "no";
        network = "no";
        audio = "no";
        hwdec = "no";
        spawn_first = "yes";
      };
      smart-native-screenshot = {
        save_path = "";
      };
    };

    xdg.configFile = {
      # Vendored scripts (not packaged in nixpkgs)
      "mpv/scripts/osc.lua".source = ./assets/scripts/osc.lua;
      "mpv/scripts/smart-native-screenshot.lua".source = ./assets/scripts/smart-native-screenshot.lua;
      "mpv/scripts/persist-properties.lua".source = ./assets/scripts/persist-properties.lua;

      # Upscaler shader (required by sd-to-1440p profile)
      "mpv/shaders/nnedi3-nns128-win8x6.hook".source = ./assets/shaders/nnedi3-nns128-win8x6.hook;

      # Subtitle font (mpv auto-loads from ~/.config/mpv/fonts/)
      "mpv/fonts/GandhiSans-Regular.otf".source = ./assets/fonts/GandhiSans-Regular.otf;
      "mpv/fonts/GandhiSans-Italic.otf".source = ./assets/fonts/GandhiSans-Italic.otf;
      "mpv/fonts/GandhiSans-Bold.otf".source = ./assets/fonts/GandhiSans-Bold.otf;
      "mpv/fonts/GandhiSans-BoldItalic.otf".source = ./assets/fonts/GandhiSans-BoldItalic.otf;

      # Right-click context menu definition
      "mpv/menu.conf".source = ./assets/menu.conf;
    };
  };
}
