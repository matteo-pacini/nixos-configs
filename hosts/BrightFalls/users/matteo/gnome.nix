{
  pkgs,
  lib,
  ...
}:
with lib.hm.gvariant;
let
  audioOutputCycle = pkgs.callPackage ./audio-output-cycle.nix { };
in
{
  xdg.configFile."monitors.xml" = {
    source = ../../monitors.xml;
    # GNOME Settings replaces the link with a regular file on "Keep changes".
    force = true;
  };

  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "magunetto@matteopacini.me"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "code.desktop"
        "org.telegram.desktop.desktop"
        "firefox.desktop"
      ]
      ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [
        "steam.desktop"
        "com.usebottles.bottles.desktop"
        "io.github.ilya_zlobintsev.LACT.desktop"
      ];
    };
    "org/gnome/desktop/session" = {
      idle-delay = mkUint32 0;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      power-button-action = "interactive";
      sleep-inactive-ac-type = "nothing";
    };
    "org/gnome/shell/extensions/magunetto" = {
      show-radial-menu = [ "<Alt>z" ];
    };
    "org/gnome/mutter" = {
      check-alive-timeout = mkUint32 10000;
      edge-tiling = false;
    };
    # Replaces any custom shortcuts added in Settings.
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/audio-output-cycle/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/audio-output-cycle" = {
      name = "Cycle audio output";
      command = lib.getExe audioOutputCycle;
      binding = "<Shift><Super>o";
    };
    "org/gnome/desktop/notifications" = {
      # Explicit true, not removed: Home Manager never resets dropped dconf keys.
      show-banners = true;
    };
  };
}
