{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.mpv;
in
{
  imports = [
    ./config.nix
    ./profiles.nix
    ./bindings.nix
    ./scripts.nix
    ./jellyfin-shim.nix
    ./exclusive-audio.nix
  ];

  options.custom.mpv = {
    enable = lib.mkEnableOption "mpv with SoM-MPV-Config derived setup";
  };

  config = lib.mkIf cfg.enable {
    programs.mpv = {
      enable = true;
      scripts = [
        pkgs.mpvScripts.autoload
        pkgs.mpvScripts.thumbfast
      ];
    };

    home.packages = [ pkgs.optipng ];
  };
}
