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
      With PipeWire this asks for exclusive access to the target node so other
      streams are suspended for the duration of playback.
    '';

    device = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "pipewire/alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo";
      description = ''
        Audio device to pin. Empty means mpv picks the default sink, which is
        fine if the DAC is already the default. Use `pactl list short sinks`
        to find the node name.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && ea.enable) {
    programs.mpv.config = {
      audio-exclusive = "yes";
      # Don't apply replay-gain — preserves the source's exact amplitude.
      replaygain = "no";
    }
    // lib.optionalAttrs (ea.device != "") {
      audio-device = ea.device;
    };
  };
}
