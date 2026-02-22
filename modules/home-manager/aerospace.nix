{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.aerospace;
in
{
  options.custom.aerospace = {
    enable = lib.mkEnableOption "AeroSpace tiling window manager";
  };

  config = lib.mkIf cfg.enable {
    programs.aerospace = {
      enable = true;
      launchd.enable = true;

      settings = {
        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;
        accordion-padding = 30;
        default-root-container-layout = "tiles";
        default-root-container-orientation = "horizontal";

        gaps = {
          inner.horizontal = 8;
          inner.vertical = 8;
          outer.left = 8;
          outer.right = 8;
          outer.top = 8;
          outer.bottom = 8;
        };

        mode.main.binding = {
          # Focus navigation (PaperWM: Super+,/./arrows)
          "ctrl-alt-h" = "focus left";
          "ctrl-alt-j" = "focus down";
          "ctrl-alt-k" = "focus up";
          "ctrl-alt-l" = "focus right";

          # Move windows (PaperWM: Super+Ctrl+arrows)
          "ctrl-alt-shift-h" = "move left";
          "ctrl-alt-shift-j" = "move down";
          "ctrl-alt-shift-k" = "move up";
          "ctrl-alt-shift-l" = "move right";

          # Resize (PaperWM: Super++/-)
          "ctrl-alt-minus" = "resize smart -50";
          "ctrl-alt-equal" = "resize smart +50";

          # Layout (PaperWM: Super+R cycle, Super+F fullscreen)
          "ctrl-alt-f" = "fullscreen";
          "ctrl-alt-slash" = "layout tiles horizontal vertical";
          "ctrl-alt-comma" = "layout accordion horizontal vertical";
          "ctrl-alt-shift-f" = "layout floating tiling";

          # Workspaces (PaperWM: Super+N)
          "ctrl-alt-1" = "workspace 1";
          "ctrl-alt-2" = "workspace 2";
          "ctrl-alt-3" = "workspace 3";
          "ctrl-alt-4" = "workspace 4";
          "ctrl-alt-5" = "workspace 5";
          "ctrl-alt-6" = "workspace 6";
          "ctrl-alt-7" = "workspace 7";
          "ctrl-alt-8" = "workspace 8";
          "ctrl-alt-9" = "workspace 9";

          # Move to workspace (PaperWM: Ctrl+Super+N)
          "ctrl-alt-shift-1" = "move-node-to-workspace 1";
          "ctrl-alt-shift-2" = "move-node-to-workspace 2";
          "ctrl-alt-shift-3" = "move-node-to-workspace 3";
          "ctrl-alt-shift-4" = "move-node-to-workspace 4";
          "ctrl-alt-shift-5" = "move-node-to-workspace 5";
          "ctrl-alt-shift-6" = "move-node-to-workspace 6";
          "ctrl-alt-shift-7" = "move-node-to-workspace 7";
          "ctrl-alt-shift-8" = "move-node-to-workspace 8";
          "ctrl-alt-shift-9" = "move-node-to-workspace 9";

          # Workspace back-and-forth (PaperWM: Super+`)
          "ctrl-alt-tab" = "workspace-back-and-forth";

          # Monitor focus (PaperWM: Shift+Super+arrows)
          "ctrl-alt-left" = "focus-monitor left";
          "ctrl-alt-right" = "focus-monitor right";

          # Move workspace to monitor
          "ctrl-alt-shift-left" = "move-workspace-to-monitor --wrap-around prev";
          "ctrl-alt-shift-right" = "move-workspace-to-monitor --wrap-around next";

          # Service mode
          "ctrl-alt-shift-semicolon" = "mode service";
        };

        mode.service.binding = {
          "esc" = [
            "reload-config"
            "mode main"
          ];
          "r" = [
            "flatten-workspace-tree"
            "mode main"
          ];
          "f" = [
            "layout floating tiling"
            "mode main"
          ];
          "backspace" = [
            "close-all-windows-but-current"
            "mode main"
          ];
        };
      };
    };
  };
}
