{
  pkgs,
  lib,
  ...
}:
with lib.hm.gvariant;
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/shell/extensions/dash-to-dock" = {
      dash-max-icon-size = 64;
      show-mounts = true;
    };
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "code.desktop"
        "org.telegram.desktop.desktop"
        "firefox.desktop"
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
    "org/gnome/mutter" = {
      check-alive-timeout = mkUint32 10000;
      experimental-features = [ "variable-refresh-rate" ];
      edge-tiling = false;
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
      package = pkgs.gnome-themes-extra;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
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
