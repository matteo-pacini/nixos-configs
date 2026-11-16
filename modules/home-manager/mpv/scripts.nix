{
  config,
  lib,
  pkgs,
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

      # Dracula, as in config.nix. console and context_menu take "#RRGGBB";
      # stats takes ASS order BBGGRR without "#".
      osc.boxalpha = 40;
      console = {
        focused_color = "#F8F8F2";
        focused_back_color = "#44475A";
        match_color = "#8BE9FD";
        # Opaque: a translucent box over a bright frame turns the same grey as
        # the focused row, and the selection disappears.
        background_alpha = 0;
      };
      context_menu = {
        focused_color = "#F8F8F2";
        focused_back_color = "#44475A";
        disabled_color = "#6272A4";
      };
      stats = {
        plot_bg_border_color = "F993BD";
        plot_bg_color = "362A28";
        plot_color = "F2F8F8";
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

      # OSD font, shipped so it does not depend on the host's installed fonts
      "mpv/fonts/FiraSans-Regular.otf".source =
        "${pkgs.fira-sans}/share/fonts/opentype/FiraSans-Regular.otf";
      "mpv/fonts/FiraSans-Bold.otf".source = "${pkgs.fira-sans}/share/fonts/opentype/FiraSans-Bold.otf";

      # Right-click context menu definition
      "mpv/menu.conf".source = ./assets/menu.conf;
    };
  };
}
