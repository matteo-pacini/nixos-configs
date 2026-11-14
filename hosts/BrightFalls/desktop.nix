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

  # With no monitors.xml, mutter makes the highest-resolution output primary:
  # the 4K HDMI capture card, so the login box lands there and DP-1/DP-2 stay
  # grey. GDM points the greeter's XDG_CONFIG_HOME at this per-seat dir (not
  # its home under /run/gdm/home), and lchowns its contents on every start.
  systemd.tmpfiles.rules = [
    "L+ /var/lib/gdm/seat0/config/monitors.xml - - - - ${./monitors.xml}"
  ];
}
