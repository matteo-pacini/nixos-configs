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
    };
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
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
    "org/gnome/desktop/notifications" = {
      show-banners = false;
    };
    "org/gnome/Console" = {
      use-system-font = false;
      custom-font = "FiraCode Nerd Font 14";
    };
  };

  gtk = {
    enable = true;
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.gnome.gnome-themes-extra;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
    gtk3.extraConfig = {
      Settings = ''
        gtk-application-prefer-dark-theme=1
      '';
    };

    gtk4.extraConfig = {
      Settings = ''
        gtk-application-prefer-dark-theme=1
      '';
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };
}
