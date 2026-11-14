# A bare Hyprland session (UWSM), picked in GDM beside GNOME. Everything
# here must stay inert in the GNOME session.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # graphical-session.target is reached by GNOME as well; this skips a unit
  # unless XDG_CURRENT_DESKTOP, which UWSM exports, contains Hyprland.
  onlyInHyprland = ''${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition "Hyprland" ""'';

  deskSync = pkgs.writeShellApplication {
    name = "desk-sync";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      findutils
      gnugrep
      gnused
      git
    ];
    text = ''
      manifest="${./user}"
      config_home="${config.xdg.configHome}"
      state="${config.xdg.stateHome}/desk"
    ''
    + builtins.readFile ./desk-sync.sh;
  };
in
{
  # The two layers of the desktop's config; see README.md. defaults/ is
  # linked read-only from the store; every file under user/ is copied to the
  # same path under ~/.config as a writable file, keeping live edits.
  xdg.dataFile."desk" = {
    source = ./defaults;
    recursive = true;
  };
  home.activation.deskSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe deskSync} activate ||
      echo "desk-sync: some files under ${config.xdg.configHome} were not installed, see above" >&2
  '';

  # Sourced by UWSM only when it starts Hyprland. The links come from udev,
  # because card numbers change between boots.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export AQ_DRM_DEVICES=/dev/dri/dgpu:/dev/dri/igpu
  '';

  # Commands the binds in user/hypr/bindings.lua run.
  home.packages = with pkgs; [
    deskSync
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
}
