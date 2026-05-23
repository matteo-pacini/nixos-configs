{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.mpv;
  isDarwin = pkgs.stdenv.isDarwin;

  videoOutput =
    if isDarwin then
      {
        vo = "gpu-next";
        hwdec = "videotoolbox";
      }
    else
      {
        vo = "gpu-next";
        gpu-api = "vulkan";
        hwdec = "auto-safe";
      };
in
{
  config = lib.mkIf cfg.enable {
    programs.mpv.config = lib.mkMerge [
      # Window + OSD
      {
        keep-open = "yes";
        keep-open-pause = "no";
        osd-duration = 1500;
        title = "\${filename}";
        osd-playlist-entry = "filename";
        autofit-larger = "100%x95%";
        hidpi-window-scale = "yes";
        osd-font-size = 25;
        input-ar-delay = 500;
        input-ar-rate = 20;
      }

      # GPU video output (platform-specific)
      videoOutput

      {
        hwdec-codecs = "h264,vc1,hevc,vp8,vp9,av1";
        target-colorspace-hint = "no";
        target-colorspace-hint-mode = "source";
      }

      # Scalers
      {
        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossharp";
        dscale = "ewa_robidoux";
        scale-antiring = 0.4;
        dscale-antiring = 0.5;
        correct-downscaling = "yes";
        sigmoid-upscaling = "yes";
      }

      # Dither / debanding
      {
        dither-depth = 8;
        dither = "fruit";
        deband = "no";
      }

      # Screenshots
      {
        screenshot-format = "png";
        screenshot-sw = "no";
        screenshot-high-bit-depth = "no";
        screenshot-tag-colorspace = "yes";
        screenshot-png-compression = 4;
        screenshot-directory = "~~/screenshots";
        screenshot-template = "%f_H%wH_M%wM_S%wS_MS.%wT_F%{estimated-frame-number}";
      }

      # Subtitles
      {
        sub-auto = "fuzzy";
        sub-font = "Gandhi Sans";
        sub-font-size = 48;
        sub-bold = "yes";
        sub-color = "#FFFFFFFF";
        sub-border-color = "#FF000000";
        sub-border-size = 2.4;
        sub-shadow-offset = 1;
        sub-shadow-color = "#8C000000";
        sub-use-margins = "no";
        sub-margin-y = 42;
        sub-margin-x = 80;
        sub-scale-with-window = "no";
        sub-ass-override = "no";
        blend-subtitles = "yes";
        sub-gray = "yes";
        sub-gauss = 0.65;
        demuxer-mkv-subtitle-preroll = "yes";
        sub-fix-timing = "no";
      }
    ];
  };
}
