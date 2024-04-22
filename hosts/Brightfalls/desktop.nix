{
  config,
  lib,
  pkgs,
  ...
}: {
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  services.udev.packages = with pkgs; [gnome.gnome-settings-daemon];

  services.xserver.excludePackages = [pkgs.xterm];

  environment.gnome.excludePackages =
    (with pkgs; [
      gnome-photos
      gnome-tour
      snapshot
      gnome-text-editor
      simple-scan
    ])
    ++ (with pkgs.gnome; [
      cheese # webcam tool
      gnome-music
      #gedit # text editor
      epiphany # web browser
      geary # email reader
      gnome-characters
      tali # poker game
      iagno # go game
      hitori # sudoku game
      atomix # puzzle game
      yelp # Help view
      gnome-contacts
      gnome-initial-setup
      gnome-maps
      gnome-weather
      totem
    ]);

  programs.dconf.enable = true;
}
