{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.mpv;
  ea = cfg.exclusiveAudio;
in
{
  options.custom.mpv.exclusiveAudio = {
    enable = lib.mkEnableOption ''
      exclusive audio output (Linux equivalent of CoreAudio Hog mode).
      With PipeWire this asks for exclusive access to the default sink so
      other streams are suspended for the duration of playback.
    '';
  };

  config = lib.mkIf (cfg.enable && ea.enable) {
    programs.mpv.config = {
      audio-exclusive = "yes";
      # Don't apply replay-gain — preserves the source's exact amplitude.
      replaygain = "no";
    };
  };
}
