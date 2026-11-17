{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.deskWallpaper;
  left = "${../../../../assets/wallpapers/left.png}";
in
{
  options.custom.deskWallpaper = {
    enable = lib.mkEnableOption "per-display desktop pictures for the desk's two monitors (README.md)";
  };

  config = lib.mkIf cfg.enable {
    # For `desk-wallpaper list` by hand.
    home.packages = [ pkgs.desk-wallpaper ];

    # Image paths are store paths on the command line, so a new picture
    # changes the plist and Home Manager restarts the agent on the switch.
    # Names and EDID ids are the ones macOS reports (system_profiler).
    launchd.agents.desk-wallpaper = {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe pkgs.desk-wallpaper)
          "run"
          "--external"
          "ROG PG278QR"
          "6b3"
          "27b1"
          left
          "--external"
          "DELL U2719D"
          "10ac"
          "415a"
          "${../../../../assets/wallpapers/right.png}"
          "--builtin"
          left
          "--builtin-docked"
          "${../../../../assets/wallpapers/background.png}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/desk-wallpaper.log";
      };
    };
  };
}
