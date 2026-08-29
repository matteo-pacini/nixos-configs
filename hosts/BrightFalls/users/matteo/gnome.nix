{
  pkgs,
  lib,
  ...
}:
with lib.hm.gvariant;
{
  xdg.configFile."monitors.xml".source = ../../monitors.xml;

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
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
    "org/gnome/desktop/notifications" = {
      show-banners = false;
    };
  };

  gtk = {
    enable = true;
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.gnome-themes-extra;
    };
    # GTK 2/3 theme
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    # GTK 4: Disable theme to prevent broken gtk.css import workaround
    # Dark mode is handled via dconf color-scheme = "prefer-dark" above
    # See: https://github.com/nix-community/home-manager/issues/8232
    gtk4.theme = null;
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };
}
