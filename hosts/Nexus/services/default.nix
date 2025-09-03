{ ... }:
{
  imports = [
    ./openssh.nix
    ./smartd.nix
    ./jellyfin.nix
    ./backup.nix
    ./nzbget.nix
    ./nzbhydra.nix
    ./radarr.nix
    ./sonarr.nix
    ./qbittorrent
    ./acme.nix
    ./ddns.nix
    ./nginx.nix
    ./zigbee2mqtt.nix
    ./mosquitto.nix
    ./home-assistant.nix
    ./music-assistant.nix
    ./ups.nix
    ./victoriametrics.nix
  ];

  systemd.tmpfiles.rules = [
    "d /downloads        2770 matteo downloads"
  ];

  # To control /diskpool/media access
  users.groups.media = { };

  # To control /diskpool/downloads access
  users.groups.downloads = { };
}
