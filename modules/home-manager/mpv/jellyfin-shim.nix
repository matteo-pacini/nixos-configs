{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.mpv;
  shimCfg = cfg.jellyfinShim;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  shimConfigDir =
    if isDarwin then "Library/Application Support/jellyfin-mpv-shim" else ".config/jellyfin-mpv-shim";

  # Files we generate via programs.mpv + xdg.configFile in the sibling modules.
  # We symlink them into the shim's config dir so both clients share one source of truth.
  mpvFiles = [
    "mpv.conf"
    "input.conf"
    "menu.conf"
    "scripts/osc.lua"
    "scripts/smart-native-screenshot.lua"
    "scripts/persist-properties.lua"
    "shaders/nnedi3-nns128-win8x6.hook"
    "fonts/GandhiSans-Regular.otf"
    "fonts/GandhiSans-Italic.otf"
    "fonts/GandhiSans-Bold.otf"
    "fonts/GandhiSans-BoldItalic.otf"
    "script-opts/thumbfast.conf"
    "script-opts/smart-native-screenshot.conf"
  ];

  baseConf = {
    shader_pack_enable = false;
    transcode_hdr = false;
    transcode_dolby_vision = false;
    mpv_ext = isDarwin;
    # Retry the server connection every 30s for this many minutes before
    # giving up and blocking on the login window (upstream default is 0,
    # i.e. a single attempt).
    connect_retry_mins = 5;
  }
  // lib.optionalAttrs isDarwin {
    mpv_ext_path = "${pkgs.mpv}/bin/mpv";
  };

  baseConfFile = pkgs.writeText "jellyfin-mpv-shim-conf.json" (builtins.toJSON baseConf);
in
{
  options.custom.mpv.jellyfinShim = {
    enable = lib.mkEnableOption "jellyfin-mpv-shim cast receiver";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Launch shim on login: systemd user service on Linux, launchd
        agent (gui domain / Aqua session) on Darwin.
      '';
    };
  };

  # Darwin notes: nixpkgs marks the package Linux-only and its python-mpv
  # dep can't pass tests there — overlays/shared.nix lifts both. The shim's
  # embedded libmpv backend is broken upstream on macOS, so we run the
  # external-mpv backend (mpv_ext, upstream default on darwin since 2.10.0;
  # kept explicit below alongside the store path).
  config = lib.mkIf (cfg.enable && shimCfg.enable) {
    home.packages = [ pkgs.jellyfin-mpv-shim ];

    # Reuse the mpv config tree — single source of truth.
    home.file = lib.listToAttrs (
      map (f: {
        name = "${shimConfigDir}/${f}";
        value.source = config.xdg.configFile."mpv/${f}".source;
      }) mpvFiles
    );

    # Seed conf.json only if missing so Quick Connect tokens (written by the
    # shim into the same file) survive rebuilds.
    home.activation.jellyfinShimSeedConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/${shimConfigDir}"
      if [ ! -e "$HOME/${shimConfigDir}/conf.json" ]; then
        run cp ${baseConfFile} "$HOME/${shimConfigDir}/conf.json"
        run chmod 600 "$HOME/${shimConfigDir}/conf.json"
      fi
    '';

    systemd.user.services.jellyfin-mpv-shim = lib.mkIf (!isDarwin && shimCfg.autoStart) {
      Unit = {
        Description = "Jellyfin MPV Shim";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        # network-online.target is a no-op in the user manager (nothing
        # activates it there), so gate on NetworkManager connectivity
        # instead. On timeout the unit fails and Restart=on-failure turns
        # this into an indefinite retry. Without the gate the shim starts
        # before the network is up, fails its single connection attempt,
        # and blocks forever on the login window without exiting.
        ExecStartPre = "${pkgs.networkmanager}/bin/nm-online -q --timeout=60";
        ExecStart = "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim";
        Restart = "on-failure";
        RestartSec = 5;
        # Exclude the llvmpipe software rasterizer from Vulkan device
        # selection — libplacebo / mpv occasionally pick it over a real
        # GPU on cold start, which drops nnedi3 onto the CPU and renders
        # at ~1 fps.
        Environment = [ "MESA_VK_DEVICE_SELECT=!llvmpipe" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # No network gate on Darwin: launchd's KeepAlive.NetworkState is
    # documented as no longer implemented, and connect_retry_mins above
    # already covers a slow network at login.
    launchd.agents.jellyfin-mpv-shim = lib.mkIf (isDarwin && shimCfg.autoStart) {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim" ];
        RunAtLoad = true;
        # Restart on crash/nonzero exit, stay dead on clean quit from the tray.
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
      };
    };
  };
}
