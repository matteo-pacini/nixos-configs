{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
          font = wezterm.font("FiraCode Nerd Font", {weight="Regular", stretch="Normal", style="Normal"}),
          font_size = 18.0,
          enable_tab_bar = false,
          color_scheme = "Dracula (Official)",
          window_decorations = "RESIZE",
          window_close_confirmation = "NeverPrompt",
          adjust_window_size_when_changing_font_size = false,
        }
    '';
  };
}
