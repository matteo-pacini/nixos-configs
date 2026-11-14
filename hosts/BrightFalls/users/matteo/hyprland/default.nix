# A bare Hyprland session (UWSM), picked in GDM beside GNOME. Everything
# here must stay inert in the GNOME session.
{
  pkgs,
  ...
}:
let
  # graphical-session.target is reached by GNOME as well; this skips a unit
  # unless XDG_CURRENT_DESKTOP, which UWSM exports, contains Hyprland.
  onlyInHyprland = ''${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition "Hyprland" ""'';
in
{
  # The Lua config, installed read-only from the store.
  xdg.configFile."hypr" = {
    source = ./user/hypr;
    recursive = true;
  };

  # Sourced by UWSM only when it starts Hyprland. The links come from udev,
  # because card numbers change between boots.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export AQ_DRM_DEVICES=/dev/dri/dgpu:/dev/dri/igpu
  '';

  # Commands the binds in user/hypr/bindings.lua run.
  home.packages = with pkgs; [
    grim
    slurp
    satty
    wl-clipboard
    playerctl
    (callPackage ../audio-output-cycle.nix { })
  ];

  services.hyprpolkitagent.enable = true;
  systemd.user.services.hyprpolkitagent.Service.ExecCondition = onlyInHyprland;

  # Not services.mako: it installs mako's D-Bus activation file, and a
  # notification sent before GNOME Shell owns the name would start mako there.
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "org.freedesktop.Notifications";
      ExecCondition = onlyInHyprland;
      ExecStart = "${pkgs.mako}/bin/mako";
      ExecReload = "${pkgs.mako}/bin/makoctl reload";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Dracula.
  xdg.configFile."mako/config".text = ''
    background-color=#282a36
    text-color=#f8f8f2
    border-color=#bd93f9
    progress-color=over #44475a
    border-radius=8
    default-timeout=5000

    [urgency=high]
    border-color=#ff5555
    default-timeout=0
  '';
}
