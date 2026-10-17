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
    programs.mpv.bindings = {
      # Right-click → context menu
      MBTN_RIGHT = "script-binding select/menu";

      # Playlist nav
      F12 = "playlist-next";
      F11 = "playlist-prev";

      # Chapter nav
      PGUP = "add chapter 1";
      PGDWN = "add chapter -1";

      # Aspect / rotation / ICC
      a = ''cycle-values video-aspect-override "16:9" "4:3" "2.35:1" "-1"'';
      "Ctrl+r" = "cycle-values video-rotate 90 180 270 0";
      "Ctrl+I" = "cycle icc-profile-auto";

      # Esc → fullscreen toggle (not quit)
      ESC = "cycle fullscreen";

      # Image adjust
      "Ctrl+1" = "add contrast -1";
      "Ctrl+2" = "add contrast 1";
      "Ctrl+3" = "add brightness -1";
      "Ctrl+4" = "add brightness 1";
      "Ctrl+5" = "add gamma -1";
      "Ctrl+6" = "add gamma 1";
      "Ctrl+7" = "add saturation -1";
      "Ctrl+8" = "add saturation 1";

      # Video pan (numpad)
      "Ctrl+KP4" = "add video-pan-x 0.01";
      "Ctrl+KP6" = "add video-pan-x -0.01";
      "Ctrl+KP8" = "add video-pan-y 0.01";
      "Ctrl+KP2" = "add video-pan-y -0.01";
      "Ctrl+BS" = "set video-zoom 0; set video-pan-x 0; set video-pan-y 0";
    };
  };
}
