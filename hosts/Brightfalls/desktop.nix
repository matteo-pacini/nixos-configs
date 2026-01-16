{
  pkgs,
  lib,
  isVM,
  ...
}:
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

  # autoLogin fixes
  # https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

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
  systemd.tmpfiles.rules = lib.optionals (!isVM) (
    let
      monitorsXmlContent = builtins.readFile ./monitors.xml;
      monitorsConfig = pkgs.writeText "gdm_monitors.xml" monitorsXmlContent;
    in
    [
      "L+ /run/gdm/.config/monitors.xml - - - - ${monitorsConfig}"
    ]
  );
}
