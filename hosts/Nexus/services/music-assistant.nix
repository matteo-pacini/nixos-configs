{ ... }:

{

  services.music-assistant = {
    enable = true;
    providers = [
      "builtin"
      "builtin_player"
      "jellyfin"
      "chromecast"
      "filesystem_local"
      "hass"
      "hass_players"
      "snapcast"
      "spotify"
    ];
  };
}
