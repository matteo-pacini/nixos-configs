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

  # Where the shim's conffile.py looks; it ignores XDG on macOS.
  shimConfigDir =
    if isDarwin then "Library/Application Support/jellyfin-mpv-shim" else ".config/jellyfin-mpv-shim";

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
    "fonts/FiraSans-Regular.otf"
    "fonts/FiraSans-Bold.otf"
    "script-opts/thumbfast.conf"
    "script-opts/smart-native-screenshot.conf"
    "script-opts/console.conf"
    "script-opts/context_menu.conf"
    "script-opts/stats.conf"
  ];

  # Library browser theme, merged by the shim over its built-in default.
  # SUBTLE_FG keeps the shim's stock grey: Dracula's comment colour is too
  # faint for the small metadata text it labels. browse_bg is the window
  # colour while browsing only; the shim restores black for video.
  draculaTheme = {
    name = "Dracula";
    palette = {
      WINDOW_BG = "282a36";
      CARD_BG = "44475a";
      PANEL_BG = "44475a";
      PLACEHOLDER_BG = "44475a";
      BUTTON_BG = "44475a";
      BUTTON_ACTIVE = "6272a4";
      ENTRY_BG = "44475a";
      BORDER = "6272a4";
      TEXT_FG = "f8f8f2";
      SUBTLE_FG = "9aa0a6";
      ACCENT = "bd93f9";
      ACCENT_HOVER = "ff79c6";
      ACCENT_SOFT = "44475a";
      ACCENT_FG = "282a36";
      FAV_RED = "ff5555";
      OK_GREEN = "50fa7b";
      WARN_AMBER = "ffb86c";
      PROGRESS_TRACK = "44475a";
      WATCHED_GREEN = "50fa7b";
    };
    browse_bg = "#282a36";
  };

  baseConf = {
    theme = "dracula";
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
    enable = lib.mkEnableOption "jellyfin-mpv-shim cast receiver";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Launch the shim on login, minimized: a systemd user service on Linux,
        a launchd agent in the Aqua session on Darwin.
      '';
    };
  };

  # On Darwin the shim plays through an external mpv process (its mpv_ext
  # default there), found on the PATH its package wrapper suffixes with
  # nixpkgs' mpv, so conf.json needs no mpv_ext keys.
  config = lib.mkIf (cfg.enable && shimCfg.enable) {
    home.packages = [ pkgs.jellyfin-mpv-shim ];

    # The shim runs mpv with its own config dir, so ~/.config/mpv is never read.
    home.file =
      lib.listToAttrs (
        map (f: {
          name = "${shimConfigDir}/${f}";
          value.source = config.xdg.configFile."mpv/${f}".source;
        }) mpvFiles
      )
      // {
        "${shimConfigDir}/themes/dracula.json".text = builtins.toJSON draculaTheme;
      };

    # Seed conf.json only if missing: the shim rewrites it on every settings
    # save, so it has to stay a writable file. Login tokens live in users.json.
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

    # No GPU pin: the Macs have one GPU. No network gate either: the shim's
    # connect_retry_mins and health check retry a server it missed at login.
    launchd.agents.jellyfin-mpv-shim = lib.mkIf (isDarwin && shimCfg.autoStart) {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.jellyfin-mpv-shim}/bin/jellyfin-mpv-shim"
          "--minimized"
        ];
        RunAtLoad = true;
        # Restart after a crash, stay down after Quit from the menu bar icon.
        KeepAlive.SuccessfulExit = false;
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
      };
    };
  };
}
