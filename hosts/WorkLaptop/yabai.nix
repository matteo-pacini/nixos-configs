{
  config,
  pkgs,
  lib,
  ...
}: {
  services.skhd = {
    enable = true;
    package = pkgs.unstable.skhd;
    skhdConfig = ''
      shift + cmd - return : open -na WezTerm
      alt - h : yabai -m window --focus west
      alt - j : yabai -m window --focus south
      alt - k : yabai -m window --focus north
      alt - l : yabai -m window --focus east
      shift + alt - h : yabai -m window --swap west
      shift + alt - j : yabai -m window --swap south
      shift + alt - k : yabai -m window --swap north
      shift + alt - l : yabai -m window --swap east
      shift + cmd - h : yabai -m window --warp west
      shift + cmd - j : yabai -m window --warp south
      shift + cmd - k : yabai -m window --warp north
      shift + cmd - l : yabai -m window --warp east
      shift + alt + cmd - l : yabai -m window --display next
      shift + alt + cmd - h : yabai -m window --display prev
      shift + alt + cmd - r : yabai -m space --balance
    '';
  };

  services.yabai = {
    enable = true;
    package = pkgs.unstable.yabai;
    enableScriptingAddition = false;
    config = {
      #focus_follows_mouse = "autoraise";
      mouse_follows_focus = "on";
      window_placement = "second_child";
      layout = "bsp";
      top_padding = 10;
      bottom_padding = 10;
      left_padding = 10;
      right_padding = 10;
      window_gap = 10;
      mouse_drop_action = "swap";
    };
    extraConfig = ''
      yabai -m rule --add app='System Settings' manage=off
      yabai -m rule --add app='Finder' manage=off
    '';
  };
}
