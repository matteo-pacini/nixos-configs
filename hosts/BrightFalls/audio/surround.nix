{ lib, ... }:
let
  headphones = "alsa_output.usb-Schiit_Audio_USB_Modi_Device-00.analog-stereo";

  channels = [
    "FL"
    "FR"
    "FC"
    "LFE"
    "RL"
    "RR"
    "SL"
    "SR"
  ];

  # Column of the HeSuVi 14-channel HRIR (not the *-.wav variants) holding
  # each speaker's impulse response for each ear. LFE reuses FC.
  hesuvi = {
    FL = {
      L = 0;
      R = 1;
    };
    SL = {
      L = 2;
      R = 3;
    };
    RL = {
      L = 4;
      R = 5;
    };
    FC = {
      L = 6;
      R = 13;
    };
    FR = {
      L = 8;
      R = 7;
    };
    SR = {
      L = 10;
      R = 9;
    };
    RR = {
      L = 12;
      R = 11;
    };
    LFE = hesuvi.FC;
  };

  ears = [
    "L"
    "R"
  ];
  forEach = f: lib.concatMap (ch: map (ear: f ch ear) ears) channels;

  # 7.1 sink that renders each speaker binaurally to the Modi.
  mkSink =
    {
      id,
      label,
      hrir,
    }:
    {
      name = "libpipewire-module-filter-chain";
      args = {
        "node.description" = "Modi 2 (${label})";
        "media.name" = "Modi 2 (${label})";
        "filter.graph" = {
          # copy nodes fan each graph input out to both ears' convolvers.
          nodes =
            map (ch: {
              type = "builtin";
              label = "copy";
              name = "copy${ch}";
            }) channels
            ++ forEach (
              ch: ear: {
                type = "builtin";
                label = "convolver";
                name = "conv${ch}_${ear}";
                config = {
                  filename = "${hrir}";
                  channel = hesuvi.${ch}.${ear};
                  # -6 dB: each ear sums 8 convolved channels, which can
                  # exceed full scale and clip at the S24LE DAC.
                  gain = 0.5;
                };
              }
            )
            ++ map (ear: {
              type = "builtin";
              label = "mixer";
              name = "mix${ear}";
            }) ears;
          links =
            forEach (
              ch: ear: {
                output = "copy${ch}:Out";
                input = "conv${ch}_${ear}:In";
              }
            )
            ++ forEach (
              ch: ear: {
                output = "conv${ch}_${ear}:Out";
                input = "mix${ear}:In ${toString (lib.lists.findFirstIndex (c: c == ch) null channels + 1)}";
              }
            );
          inputs = map (ch: "copy${ch}:In") channels;
          outputs = map (ear: "mix${ear}:Out") ears;
        };
        "capture.props" = {
          "node.name" = "effect_input.virtual-surround-${id}";
          "media.class" = "Audio/Sink";
          "audio.channels" = 8;
          "audio.position" = channels;
          # Below every hardware sink, so it is only ever the default by hand.
          "priority.session" = 1;
        };
        "playback.props" = {
          "node.name" = "effect_output.virtual-surround-${id}";
          "node.passive" = true;
          "audio.channels" = 2;
          "audio.position" = [
            "FL"
            "FR"
          ];
          "target.object" = headphones;
          # The Modi leaves when the KVM switches away. Without this the
          # output would fall back to the default sink, which can be the
          # other surround sink, and the two would feed each other.
          "node.dont-fallback" = true;
        };
      };
    };
in
{
  services.pipewire.extraConfig.pipewire."40-virtual-surround" = {
    "context.modules" = map mkSink [
      {
        id = "atmos";
        label = "Atmos";
        hrir = ./hrir-atmos.wav;
      }
      {
        id = "dtshx";
        label = "DTS Headphone:X";
        hrir = ./hrir-dtshx.wav;
      }
    ];
  };
}
