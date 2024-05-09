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
          font = wezterm.font("MesloLGS NF", {weight="Regular", stretch="Normal", style="Normal"}),
          font_size = 18.0,
          enable_tab_bar = false,
          color_scheme = "Dracula (Official)",
          window_decorations = "RESIZE",
          window_close_confirmation = "NeverPrompt",
        }
    '';
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
