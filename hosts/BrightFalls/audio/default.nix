_: {
  imports = [
    ./surround.nix
  ];
  services.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # High-fidelity audio configuration for Schiit Modi 2 + Magni 2 + HD650.
  #
  # Goal: bit-perfect playback to the Modi 2 — let PipeWire follow the source
  # sample rate so no resampling happens for 44.1/48/88.2/96 kHz material.
  #
  # Hardware facts that drive this config:
  #   - Modi 2 (regular): C-Media CM6631A USB receiver, AKM AK4396 DAC.
  #   - Linux/macOS max is 24-bit / 96 kHz; 192 kHz needs Schiit's Windows
  #     "Expert Mode" driver and is unreachable here.
  #   - Native rates: 44.1, 48, 88.2, 96 kHz @ 16/24-bit.
  #   - Magni 2 is a pure analog amp — no digital config concerns it.
  services.pipewire.extraConfig.pipewire = {
    "10-clock-rate" = {
      "context.properties" = {
        # default.clock.rate intentionally omitted — without a fixed default,
        # the graph rate follows the first stream that comes in, which gives
        # bit-perfect rates for 44.1, 48, 88.2, 96 kHz sources.
        "default.clock.allowed-rates" = [
          44100
          48000
          88200
          96000
        ];
      };
    };

    # Resampling quality. Rate-follow keeps resampling rare (only when streams
    # at different rates mix), so quality 10 is a comfortable middle ground —
    # quality 14 costs 2-3x CPU for negligible audible improvement.
    "20-resampling" = {
      "context.properties" = {
        "resample.quality" = 10;
      };
    };

    # Buffer/quantum: 1024 samples (~21 ms at 48 kHz) is stable for the USB1
    # Modi 2. Min == default keeps apps from negotiating tiny buffers that xrun
    # on the C-Media chip; max allows high-latency apps (e.g. media players) to
    # request larger ones.
    "30-quantum" = {
      "context.properties" = {
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 1024;
        "default.clock.max-quantum" = 8192;
      };
    };
  };

  # Per-device rule for the Modi 2.
  #
  # audio.format = S24LE        Modi 2 is a 24-bit DAC; padding 16-bit content
  #                             with zeros is mathematically lossless.
  # audio.rate   = 0            Follow the graph rate instead of locking the
  #                             node to a single rate (which would force
  #                             resampling of every other rate to that one).
  # audio.allowed-rates         DAC's actual native capability; constrains the
  #                             follow behaviour so an off-list rate (e.g.
  #                             192 kHz) cleanly resamples to 96 kHz instead
  #                             of being attempted on hardware that can't.
  #
  # The remaining rules trim the output picker down to the Modi and the
  # surround sinks in surround.nix.
  services.pipewire.wireplumber.extraConfig."50-alsa-config" = {
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
            "audio.rate" = 0;
            "audio.allowed-rates" = "44100,48000,88200,96000";
            "node.description" = "Modi 2 (Stereo)";
          };
        };
      }
      {
        matches = [
          {
            "device.name" = "alsa_card.usb-Schiit_Audio_USB_Modi_Device-00";
          }
        ];
        actions = {
          "update-props" = {
            "device.description" = "Modi 2";
            "device.profile-set" = "${./profile-sets/modi.conf}";
            "api.acp.disable-pro-audio" = true;
          };
        };
      }
      {
        matches = [
          {
            "device.name" = "~alsa_card.usb-Generic_Blue_Microphones.*";
          }
        ];
        actions = {
          "update-props" = {
            "device.profile-set" = "${./profile-sets/blue.conf}";
            "api.acp.disable-pro-audio" = true;
          };
        };
      }
      # Default input whenever it is plugged in: ALSA gives USB inputs equal
      # priority, so without this the BRIO webcam ties with it.
      {
        matches = [
          {
            "node.name" = "~alsa_input.usb-Generic_Blue_Microphones.*";
          }
        ];
        actions = {
          "update-props" = {
            "priority.session" = 3000;
          };
        };
      }
      # GPU HDMI/DP audio: the dGPU (Navi 21) and the iGPU.
      {
        matches = [
          { "device.name" = "alsa_card.pci-0000_07_00.1"; }
          { "device.name" = "alsa_card.pci-0000_0a_00.1"; }
        ];
        actions = {
          "update-props" = {
            "device.disabled" = true;
          };
        };
      }
    ];
  };
}
