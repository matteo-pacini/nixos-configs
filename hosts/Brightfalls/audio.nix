{
  config,
  lib,
  ...
}: {
  hardware.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.etc."pipewire/pipewire.conf.d/99-rates.conf".text = ''
    context.properties = {
      default.clock.rate = 44100
      default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
    }
  '';
}
