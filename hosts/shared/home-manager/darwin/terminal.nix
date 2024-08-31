{ ... }:
{
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      return {
          font = wezterm.font("FiraCode Nerd Font", {weight="Regular", stretch="Normal", style="Normal"}),
          window_background_opacity = 0.9,
          macos_window_background_blur = 30,
          font_size = 18.0,
          color_scheme = "Dracula (Official)",
          window_decorations = "RESIZE",
          window_close_confirmation = "NeverPrompt",
          -- https://github.com/NixOS/nixpkgs/issues/336069
          front_end = "WebGpu",
        }
    '';
  };
}
