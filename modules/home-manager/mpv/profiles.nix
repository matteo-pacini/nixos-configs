{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.mpv;
in
{
  config = lib.mkIf cfg.enable {
    programs.mpv.profiles = {
      # SD anime/series upscale to 1440p (retargeted from SoM's 4K trigger)
      "sd-to-1440p" = {
        profile-cond = ''p["video-params/w"]<=720 and p["osd-dimensions/w"]>=2560'';
        profile-restore = "copy-equal";
        glsl-shader = "~~/shaders/nnedi3-nns128-win8x6.hook";
      };

      # PGS subtitles: mpv applies sub-scale to bitmap subs only when
      # sub-ass-override is not "no"
      "pgs-scaling" = {
        profile-cond = ''(function() local t = p["track-list"] or {}; for _, tr in ipairs(t) do if tr.type == "sub" and tr.selected then return (tr["codec"] or ""):lower():match("pgs") ~= nil end end; return false end)()'';
        profile-restore = "copy-equal";
        sub-ass-override = "yes";
      };

      # SD NTSC primaries fix (480p US/anime)
      "sd-ntsc" = {
        profile-cond = ''p["video-params/w"]<=720 and p["video-params/primaries"]=="bt.601-525"'';
        profile-restore = "copy-equal";
        target-prim = "bt.601-525";
        target-trc = "bt.1886";
        scale-antiring = 0;
      };

      # SD PAL primaries fix (576p UK/Euro)
      "sd-pal" = {
        profile-cond = ''p["video-params/w"]<=720 and p["video-params/primaries"]=="bt.601-625"'';
        profile-restore = "copy-equal";
        target-prim = "bt.601-625";
        target-trc = "bt.1886";
        scale-antiring = 0;
      };

      # 1080p Blu-ray BT.709 SDR
      "sdr-bt709" = {
        profile-cond = ''p["video-params/primaries"]=="bt.709" and p["video-params/gamma"]~="pq"'';
        profile-restore = "copy-equal";
        target-prim = "bt.709";
        target-trc = "bt.1886";
      };

      # HDR → SDR tone-map (4K HDR Blu-ray, HDR WEBDL)
      hdr = {
        profile-cond = ''p["video-params/gamma"]=="pq"'';
        profile-restore = "copy-equal";
        tone-mapping = "spline";
        hdr-compute-peak = "yes";
        target-prim = "bt.709";
        target-trc = "bt.1886";
        gamut-mapping-mode = "perceptual";
        target-peak = 120;
        screenshot-high-bit-depth = "yes";
        screenshot-sw = "yes";
      };

      # Dolby Vision → SDR tone-map
      dolby-vision = {
        profile-cond = ''p["video-params/colormatrix"]=="dolbyvision"'';
        profile-restore = "copy-equal";
        tone-mapping = "bt.2446a";
        hdr-compute-peak = "yes";
        target-prim = "bt.709";
        target-trc = "bt.1886";
        gamut-mapping-mode = "perceptual";
        target-peak = 120;
      };
    };
  };
}
