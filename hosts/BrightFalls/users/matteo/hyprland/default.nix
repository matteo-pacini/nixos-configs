# The user side of the Hyprland session (UWSM): the desktop's config files,
# its helpers, the Quickshell service and the wallpapers.
{
  config,
  osConfig,
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
      quickshell
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

  # The Tailscale panel's mesh hosts (README.md, "Tailscale: status and mesh
  # hosts"): every host in
  # lib/ssh-mesh.nix with a Tailscale name.
  mesh = import ../../../../../lib/ssh-mesh.nix;
  kinds = import ../../../../../lib/host-kinds.nix;
  tailscaleHosts = lib.mapAttrsToList (name: host: {
    label = name;
    dns = host.tailscale;
    alias = host.principal;
    sshd = host ? port;
    inherit (kinds.${name}) device;
  }) (lib.filterAttrs (_: host: host ? tailscale) mesh.hosts);

  # Monitors matched by description, not connector: connector numbers are
  # shared between the two GPUs and follow probe order. hyprpaper compares
  # `desc:` as a prefix of the wl_output description ("make model serial")
  # with the trailing "(port)" removed. "##" is hyprlang's escape for a
  # literal "#", which otherwise starts a comment.
  hyprpaperConf = pkgs.writeText "hyprpaper.conf" ''
    splash = false
    ipc = false

    wallpaper {
        monitor = desc:ASUSTek COMPUTER INC ROG PG278QR ##ASO0f7HLJ+Pd
        path = ${../../../../../assets/wallpapers/left.png}
        fit_mode = cover
    }

    wallpaper {
        monitor = desc:Dell Inc. DELL U2719D 7CGY223
        path = ${../../../../../assets/wallpapers/right.png}
        fit_mode = cover
    }
  '';
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
  xdg.dataFile."desk/tailscale/hosts.json".text = builtins.toJSON { hosts = tailscaleHosts; };
  # The weather panel's radar map draws this outline (README.md, "Weather
  # panel").
  xdg.dataFile."desk/weather/coast.json".source = pkgs.callPackage ./weather-coast.nix { };
  # The shell's token panel and bar item read the file this writes.
  custom.herdr.workbench.claudeLimitsFile.enable = true;
  home.activation.deskSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe deskSync} activate ||
      echo "desk-sync: some files under ${config.xdg.configHome} were not installed, see above" >&2
  '';

  # Sourced by UWSM only when it starts Hyprland. The links come from udev,
  # because card numbers change between boots. The cursor variables are here
  # because UWSM sources only /etc/profile and ~/.profile, and neither loads
  # Home Manager's session variables.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export AQ_DRM_DEVICES=/dev/dri/dgpu:/dev/dri/igpu
    export XCURSOR_THEME=${config.home.pointerCursor.name}
    export XCURSOR_SIZE=${toString config.home.pointerCursor.size}
  '';

  # Commands the binds in user/hypr/bindings.lua and the shell's panels run,
  # with desk-sync and desk-unlock.
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
    # gdbus: the shell's notifications from Bluetooth, the audio panel and
    # reminders, and the lock screen's watch for sleep (quickshell/Lockscreen.qml).
    glib.bin
    (callPackage ../audio-output-cycle.nix { })
    (callPackage ./bt-agent.nix { })
    (callPackage ./desk-mqtt.nix {
      configFile = osConfig.age.secrets."brightfalls/office-mqtt".path;
    })
    (callPackage ./desk-fleet.nix {
      self = config.custom.ssh.mesh.host;
      repo = lib.removeSuffix ".git" (
        lib.removePrefix "https://github.com/" (lib.head osConfig.services.comin.remotes).url
      );
    })
    (callPackage ./desk-tokens.nix { })
    (callPackage ./desk-weather.nix {
      configFile = osConfig.age.secrets."brightfalls/weather".path;
    })
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

  # Wallpapers (README.md, "Wallpaper"). The config goes by store path rather
  # than through `settings`, so ~/.config/hypr holds only desk-sync's files;
  # a new picture changes ExecStart, which restarts the unit on a switch.
  services.hyprpaper.enable = true;
  systemd.user.services.hyprpaper.Service.ExecStart =
    lib.mkForce "${lib.getExe pkgs.hyprpaper} -c ${hyprpaperConf}";
}
