{ pkgs, ... }:
{
  services.xserver = {
    enable = true;
  };

  services.desktopManager.gnome.enable = true;

  services.displayManager = {
    # Makes sense to me as the whole system is encrypted
    autoLogin = {
      enable = true;
      user = "matteo";
    };
    gdm = {
      enable = true;
    };
  };

  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  services.xserver.excludePackages = [ pkgs.xterm ];

  environment.gnome.excludePackages = (
    with pkgs;
    [
      gnome-tour
      snapshot
      gnome-text-editor
      simple-scan
      cheese
      gnome-music
      epiphany
      geary
      gnome-characters
      tali
      iagno
      hitori
      atomix
      yelp
      gnome-contacts
      gnome-initial-setup
      gnome-maps
      gnome-weather
    ]
  );

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

  # With no monitors.xml, mutter makes the highest-resolution output primary:
  # the 4K HDMI capture card, so the login box lands there and DP-1/DP-2 stay
  # grey. GDM points the greeter's XDG_CONFIG_HOME at this per-seat dir (not
  # its home under /run/gdm/home), and lchowns its contents on every start.
  systemd.tmpfiles.rules = [
    "L+ /var/lib/gdm/seat0/config/monitors.xml - - - - ${./monitors.xml}"
  ];
}
