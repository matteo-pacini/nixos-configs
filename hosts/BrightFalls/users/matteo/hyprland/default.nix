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
  # Run by activation only, not put on PATH.
  deskReload = pkgs.writeShellApplication {
    name = "desk-reload";
    runtimeInputs = with pkgs; [
      coreutils
      quickshell
    ];
    text = builtins.readFile ./desk-reload.sh;
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
  # linked file by file under ~/.local/share/desk; each directory of user/ is
  # one read-only link under ~/.config.
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
  # A change to quickshell/ or desk/ (the palette the shell reads) sets the
  # flag, and the shell is asked for one reload after every link is in place:
  # Quickshell does not notice a retargeted link. No Hyprland reload: it would
  # end game mode and single-monitor's rule, and a switch can come from comin
  # mid-game. onChange runs in onFilesChange, in the same shell as the entry
  # below.
  xdg.configFile."quickshell" = {
    source = ./user/quickshell;
    onChange = "deskReloadShell=1";
  };
  xdg.configFile."hypr".source = ./user/hypr;
  xdg.configFile."desk" = {
    source = ./user/desk;
    onChange = "deskReloadShell=1";
  };
  home.activation.deskReloadShell = lib.hm.dag.entryAfter [ "onFilesChange" ] ''
    if [[ -v deskReloadShell ]]; then
      run ${lib.getExe deskReload} ${config.xdg.configHome}/quickshell
    fi
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
  # with desk-unlock and desk-nest.
  home.packages = with pkgs; [
    deskUnlock
    (callPackage ./desk-nest.nix { })
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
  # It reloads after a switch that changes that tree (deskReloadShell above)
  # and on `qs ipc call shell reload`, never on its own. It is also the
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
  # than through `settings`, so ~/.config/hypr is only the linked user/hypr;
  # a new picture changes ExecStart, which restarts the unit on a switch.
  services.hyprpaper.enable = true;
  systemd.user.services.hyprpaper.Service.ExecStart =
    lib.mkForce "${lib.getExe pkgs.hyprpaper} -c ${hyprpaperConf}";
}
