{
  isVM,
  pkgs,
  lib,
  ...
}:
{
  hardware.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = pkgs.stdenv.hostPlatform == "x86_64-linux";
    pulse.enable = true;
  };

  services.pipewire.extraConfig.pipewire = lib.mkIf (!isVM) {
    "10-clock-rate" = {
      "context.properties" = {
        "default.clock.rate" = 44100;
        "default.clock.allowed-rates" = [
          44100
          48000
          96000
          192000
        ];
      };
    };
  };
}
