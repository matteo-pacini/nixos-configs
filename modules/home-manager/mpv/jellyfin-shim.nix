{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.mpv;
  shimCfg = cfg.jellyfinShim;
  isDarwin = pkgs.stdenv.isDarwin;

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

  baseConf =
    {
      shader_pack_enable = false;
      transcode_hdr = false;
      transcode_dolby_vision = false;
      mpv_ext = isDarwin;
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
      default = !isDarwin;
      description = ''
        Launch shim on login via systemd user service (Linux only).
        Darwin has no equivalent — launch manually or add a launchd agent
        at the system level.
      '';
    };
  };

  # Skip entirely on Darwin: the shim's embedded libmpv backend is broken
  # upstream on macOS, jellyfin-mpv-shim's python-mpv dep fails to build
  # because its test suite requires Xvfb, and home-manager cannot manage
  # launchd agents for auto-start anyway.
  config = lib.mkIf (cfg.enable && shimCfg.enable && !isDarwin) {
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
  };
}
