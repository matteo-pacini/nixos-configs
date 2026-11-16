{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Hyprland on VT 1. The first login of each boot needs no password (the
  # whole system is encrypted). After a logout, tuigreet asks for the password.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings =
      let
        # The Exec line of hyprland-uwsm.desktop.
        session = "${lib.getExe config.programs.uwsm.package} start -e -D Hyprland hyprland.desktop";
      in
      {
        initial_session = {
          user = "matteo";
          command = session;
        };
        default_session.command = "${lib.getExe pkgs.tuigreet} --time --remember --cmd '${session}'";
      };
  };

  programs.dconf.enable = true;

  # The secret service and the SSH agent (SSH_AUTH_SOCK is
  # $XDG_RUNTIME_DIR/gcr/ssh, set by the agent's socket unit).
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gcr-ssh-agent.enable = true;
  programs.seahorse.enable = true;
  # Trash, mounts and network locations in Nautilus and the GTK file chooser.
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  # TLS for GIO, which gvfs network locations use.
  services.gnome.glib-networking.enable = true;
  services.upower.enable = true;
  # Nautilus's Space preview.
  services.gnome.sushi.enable = true;

  # Hyprland has no file chooser or settings portal; gtk provides them.
  xdg.portal.config.hyprland = {
    default = [
      "hyprland"
      "gtk"
    ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
  };

  # Adwaita Sans and Mono, the GTK interface fonts.
  custom.fonts.extraPackages = [ pkgs.adwaita-fonts ];

  environment.systemPackages = with pkgs; [
    nautilus
    loupe
    papers
    file-roller
    htop
    dua
    adwaita-icon-theme
    # Nautilus thumbnails: images, and audio and video.
    glycin-thumbnailer
    gst-thumbnailers
  ];
}
