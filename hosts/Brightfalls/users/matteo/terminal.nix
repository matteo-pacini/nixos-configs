{ ... }:
{
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
        font = wezterm.font("FiraCode Nerd Font", {weight="Regular", stretch="Normal", style="Normal"}),
        font_size = 14.0,
        color_schemes = {
          ["Adwaita Dark"] = {
            foreground = "#ffffff",
            background = "#1e1e1e",
            cursor_bg = "#ffffff",
            cursor_fg = "#1e1e1e",
            ansi = {"#241f31", "#c01c28", "#2ec27e", "#f5c211", "#1e78e4", "#9841bb", "#0ab9dc", "#c0bfbc"},
            brights = {"#5e5c64", "#ed333b", "#57e389", "#f8e45c", "#51a1ff", "#c061cb", "#4fd2fd", "#f6f5f4"},
          },
        },
        color_scheme = "Adwaita Dark",
        window_decorations = "RESIZE",
        window_close_confirmation = "NeverPrompt",
        max_fps = 144,
        keys = {
          { key = "F11", action = wezterm.action.ToggleFullScreen },
        },
      }
    '';
  };
}
