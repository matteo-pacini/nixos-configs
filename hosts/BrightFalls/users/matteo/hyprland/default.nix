# The user side of the Hyprland session (UWSM): the desktop's config files,
# its helpers and the Quickshell service.
{
  config,
  lib,
  pkgs,
  ...
}:
let
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

  # Recovery from a text console when the lock screen dies (README.md, "Lock
  # screen").
  deskUnlock = pkgs.writeShellApplication {
    name = "desk-unlock";
    runtimeInputs = with pkgs; [
      hyprland
      procps
      systemd
    ];
    text = builtins.readFile ./desk-unlock.sh;
  };
in
{
  imports = [ ./calendar.nix ];

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
    deskUnlock
    grim
    slurp
    satty
    wl-clipboard
    playerctl
    quickshell
    # The network panel's speed-test providers (quickshell/network/SpeedTest.qml).
    cfspeedtest
    ookla-speedtest
    (callPackage ../audio-output-cycle.nix { })
    (callPackage ./bt-agent.nix { })
  ];

  # The desktop shell, from user/quickshell/ (installed at
  # ~/.config/quickshell, the default config `qs` runs and `qs ipc` talks to).
  # It reloads on its own when a file there changes. It is also the
  # notification daemon, with no D-Bus activation file for that name: a
  # notification sent before the shell is up is lost.
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe' pkgs.quickshell "qs";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
