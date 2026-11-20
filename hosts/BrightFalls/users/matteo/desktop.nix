{ pkgs, lib, ... }:
let
  # Handlers the apps register for themselves: defaults and added associations.
  registered = {
    "x-scheme-handler/http" = "firefox.desktop";
    "x-scheme-handler/https" = "firefox.desktop";
    "x-scheme-handler/chrome" = "firefox.desktop";
    "text/html" = "firefox.desktop";
    "application/x-extension-htm" = "firefox.desktop";
    "application/x-extension-html" = "firefox.desktop";
    "application/x-extension-shtml" = "firefox.desktop";
    "application/xhtml+xml" = "firefox.desktop";
    "application/x-extension-xhtml" = "firefox.desktop";
    "application/x-extension-xht" = "firefox.desktop";
    "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
    "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    "x-scheme-handler/ton" = "org.telegram.desktop.desktop";
  };
  allTo = app: types: lib.genAttrs types (_: app);
in
{
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # XCursor only: the package has no hyprcursor files, so hyprcursor stays off.
  home.pointerCursor = {
    enable = true;
    name = "Dracula-cursors";
    package = pkgs.dracula-theme;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
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

  # ~/.config/mimeapps.list becomes a link into the store, so an app's own
  # "make default" cannot change it; change it here.
  xdg.mimeApps = {
    enable = true;
    associations.added = registered;
    defaultApplications =
      registered
      // {
        "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
        "x-scheme-handler/proxyman" = "proxyman.desktop";
        "inode/directory" = "org.gnome.Nautilus.desktop";
      }
      // allTo "org.gnome.Loupe.desktop" [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/avif"
        "image/heic"
        "image/jxl"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
        "image/vnd.microsoft.icon"
      ]
      // allTo "org.gnome.Papers.desktop" [
        "application/pdf"
        "image/vnd.djvu"
        "application/vnd.comicbook+zip"
        "application/vnd.comicbook-rar"
      ]
      // allTo "org.gnome.FileRoller.desktop" [
        "application/zip"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/x-tar"
        "application/gzip"
        "application/x-compressed-tar"
        "application/x-xz"
        "application/x-xz-compressed-tar"
        "application/zstd"
        "application/x-zstd-compressed-tar"
      ];
  };
}
