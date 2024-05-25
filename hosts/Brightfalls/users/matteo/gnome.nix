{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
with lib.hm.gvariant; {
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      icon-theme = "Adwaita";
    };
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "pop-shell@system76.com"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "firefox.desktop"
        "org.corectrl.corectrl.desktop"
        "org.gnome.Console.desktop"
        "com.obsproject.Studio.desktop"
        "steam.desktop"
        "com.usebottles.bottles.desktop"
      ];
    };
    "org/gnome/desktop/session" = {
      idle-delay = mkUint32 0;
    };
    "org/gnome/settings-daemon/plugins/power" = {
      power-button-action = "interactive";
      sleep-inactive-ac-type = "nothing";
    };
    "org/gnome/mutter" = {
      check-alive-timeout = mkUint32 10000;
      experimental-features = ["variable-refresh-rate"];
      edge-tiling = false;
    };
    "org/gnome/shell/extensions/pop-shell" = {
      tile-by-default = true;
      active-hint = true;
      active-hint-border-radius = mkUint32 4;
      gap-inner = mkUint32 8;
      gap-outer = mkUint32 8;
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
  };

  xdg.configFile = {
    "gtk-4.0/assets".source = "${config.gtk.theme.package}/share/themes/${config.gtk.theme.name}/gtk-4.0/assets";
    "gtk-4.0/gtk.css".source = "${config.gtk.theme.package}/share/themes/${config.gtk.theme.name}/gtk-4.0/gtk.css";
    "gtk-4.0/gtk-dark.css".source = "${config.gtk.theme.package}/share/themes/${config.gtk.theme.name}/gtk-4.0/gtk-dark.css";
  };

  qt = {
    enable = true;
    platformTheme = "gnome";
    style.name = "adwaita-dark";
  };
}
