{ pkgs, ... }:
{
  services.xserver = {
    enable = true;
  };

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.udev.packages = with pkgs; [ gnome-settings-daemon ];

  services.xserver.excludePackages = [ pkgs.xterm ];

  environment.gnome.excludePackages = (
    with pkgs;
    [
      gnome-photos
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

  # Set up GDM to use a custom monitors configuration
  systemd.tmpfiles.rules =
    let
      monitorsXmlContent = builtins.readFile ./monitors.xml;
      monitorsConfig = pkgs.writeText "gdm_monitors.xml" monitorsXmlContent;
    in
    [
      "L+ /run/gdm/.config/monitors.xml - - - - ${monitorsConfig}"
    ];
}
