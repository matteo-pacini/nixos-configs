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
      # Expose only the discrete GPU to Vulkan so libplacebo can never land
      # on llvmpipe, which runs the nnedi3 shader on the CPU at ~1 fps.
      extraMakeWrapperArgs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        "--set"
        "MESA_VK_DEVICE_SELECT"
        "discrete!"
      ];
    };

    home.packages = [ pkgs.optipng ];
  };
}
