{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.xserver = {
    enable = true;
  };

  services.desktopManager.gnome.enable = true;

  services.displayManager = {
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
      totem
    ]
  );

  programs.dconf.enable = true;

  # Never suspend on AC, so the laptop stays reachable for SSH and comin.
  # The screen still blanks on GNOME's idle-delay; battery keeps GNOME's
  # suspend defaults. gdm and user are separate dconf profiles: the login
  # screen (where every `boot` deploy lands) ignores the user's settings.
  programs.dconf.profiles =
    let
      noSleepOnAc = {
        settings."org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
      };
    in
    {
      gdm.databases = [ noSleepOnAc ];
      user.databases = [ noSleepOnAc ];
    };
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
}
