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
      local wezterm = require 'wezterm'

        return {

          font = wezterm.font("MesloLGS NF", {weight="Regular", stretch="Normal", style="Normal"}),
          font_size = 16.0,
          enable_tab_bar = false,
          color_scheme = "Dracula (Official)",

        }
    '';
  };
}
