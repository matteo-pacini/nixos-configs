{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.mpv;
  shimCfg = cfg.jellyfinShim;

  shimConfigDir = ".config/jellyfin-mpv-shim";

  # Files we generate via programs.mpv + xdg.configFile in the sibling modules.
  # We symlink them into the shim's config dir so both clients share one source of truth.
  # No scripts/osc.lua: the shim draws its own player HUD, and the OSC would overlap it.
  mpvFiles = [
    "mpv.conf"
    "input.conf"
    "menu.conf"
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
    # Retry a failed first connect every 30s for this many minutes (upstream
    # default is 0). After that the health check retries every 300s.
    connect_retry_mins = 5;
  };

  baseConfFile = pkgs.writeText "jellyfin-mpv-shim-conf.json" (builtins.toJSON baseConf);
in
{
  options.custom.mpv.jellyfinShim = {
    enable = lib.mkEnableOption "jellyfin-mpv-shim cast receiver (Linux only)";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Launch the shim on login, minimized, as a systemd user service.";
    };
  };

  config = lib.mkIf (cfg.enable && shimCfg.enable) {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "custom.mpv.jellyfinShim is Linux only.";
      }
    ];

    home.packages = [ pkgs.jellyfin-mpv-shim ];

    # The shim runs mpv with its own config dir, so ~/.config/mpv is never read.
    home.file = lib.listToAttrs (
      map (f: {
        name = "${shimConfigDir}/${f}";
        value.source = config.xdg.configFile."mpv/${f}".source;
      }) mpvFiles
    );

    # Seed conf.json only if missing: the shim rewrites it on every settings
    # save, so it has to stay a writable file. Login tokens live in users.json.
    home.activation.jellyfinShimSeedConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/${shimConfigDir}"
      if [ ! -e "$HOME/${shimConfigDir}/conf.json" ]; then
        run cp ${baseConfFile} "$HOME/${shimConfigDir}/conf.json"
        run chmod 600 "$HOME/${shimConfigDir}/conf.json"
      fi
    '';

    systemd.user.services.jellyfin-mpv-shim = lib.mkIf shimCfg.autoStart {
      Unit = {
        Description = "Jellyfin MPV Shim";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        # Without --minimized the shim opens its library window at every login.
        ExecStart = "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim --minimized";
        Restart = "on-failure";
        RestartSec = 5;
        # The shim's libmpv does not go through the mpv wrapper in default.nix,
        # so it needs the same discrete-GPU pin here.
        Environment = [ "MESA_VK_DEVICE_SELECT=discrete!" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
