{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.zellij;

  vimZellijNavigator = pkgs.fetchurl {
    url = "https://github.com/hiasr/vim-zellij-navigator/releases/download/0.2.1/vim-zellij-navigator.wasm";
    sha256 = "0z8yi6w153ivnpxgkpq3pc0l6ad5la5jjl6778h819lm94z334n2";
  };

  copyCommand = if pkgs.stdenv.isDarwin then "pbcopy" else "wl-copy";
in
{
  options.custom.zellij = {
    enable = lib.mkEnableOption "Zellij with Dracula theme and smart-splits integration";
  };

  config = lib.mkIf cfg.enable {
    programs.zellij.enable = true;

    home.packages = lib.optional pkgs.stdenv.isLinux pkgs.wl-clipboard;

    xdg.configFile."zellij/config.kdl".text = ''
      default_shell "zsh"
      mouse_mode false
      copy_command "${copyCommand}"
      theme "dracula"

      keybinds {
          shared_except "locked" {
              bind "Ctrl h" { MessagePlugin "file:${vimZellijNavigator}" { name "move_focus"; payload "left"; }; }
              bind "Ctrl j" { MessagePlugin "file:${vimZellijNavigator}" { name "move_focus"; payload "down"; }; }
              bind "Ctrl k" { MessagePlugin "file:${vimZellijNavigator}" { name "move_focus"; payload "up"; }; }
              bind "Ctrl l" { MessagePlugin "file:${vimZellijNavigator}" { name "move_focus"; payload "right"; }; }
              bind "Alt h"  { MessagePlugin "file:${vimZellijNavigator}" { name "resize";     payload "left"; }; }
              bind "Alt j"  { MessagePlugin "file:${vimZellijNavigator}" { name "resize";     payload "down"; }; }
              bind "Alt k"  { MessagePlugin "file:${vimZellijNavigator}" { name "resize";     payload "up"; }; }
              bind "Alt l"  { MessagePlugin "file:${vimZellijNavigator}" { name "resize";     payload "right"; }; }
          }
      }
    '';
  };
}
