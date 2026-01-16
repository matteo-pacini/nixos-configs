{
  lib,
  isVM,
  ...
}:
{
  imports = [
  ];
  services.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # High-fidelity audio configuration for Schiit Modi 2 + Magni + HD650
  # Optimized for bit-perfect playback and audio quality
  services.pipewire.extraConfig.pipewire = lib.mkIf (!isVM) {
    "10-clock-rate" = {
      "context.properties" = {
        # Default to 44.1kHz (most common music sample rate)
        "default.clock.rate" = 44100;
        # Modi 2 supports up to 96kHz (NOT 192kHz - removed to avoid unnecessary resampling)
        "default.clock.allowed-rates" = [
          44100
          48000
          88200
          96000
        ];
      };
    };

    # Resampling quality optimization for high-fidelity playback
    # Quality 10 provides excellent audio quality with minimal CPU overhead
    # (Quality 14 uses 2-3x more CPU with negligible audible improvement)
    "20-resampling" = {
      "context.properties" = {
        "resample.quality" = 10;
      };
    };

    # Buffer/quantum optimization for stable, high-quality playback
    # 8192 samples provides excellent stability without audible latency
    "30-quantum" = {
      "context.properties" = {
        "default.clock.quantum" = 8192;
        "default.clock.min-quantum" = 8192;
      };
    };
  };

  # Wireplumber configuration for bit-perfect USB DAC output
  # Enforces 24-bit format (S24LE) matching Modi 2 capabilities
  services.pipewire.wireplumber.extraConfig."50-alsa-config" = lib.mkIf (!isVM) {
    "monitor.alsa.rules" = [
      {
        matches = [
          {
            "node.name" = "~alsa_output.usb-Schiit_Audio_USB_Modi.*";
          }
        ];
        actions = {
          "update-props" = {
            "audio.format" = "S24LE";
            "audio.rate" = 96000;
          };
        };
      }
    ];
  };

}
