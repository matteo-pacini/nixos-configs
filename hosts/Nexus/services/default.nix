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
    ./n8n
    ./acme.nix
    ./ddns.nix
    ./caddy.nix
    ./fail2ban.nix
    ./zigbee2mqtt.nix
    ./mosquitto.nix
    ./home-assistant.nix
    ./ups.nix
    ./victoriametrics.nix
    ./postgresql.nix
    ./grafana.nix
    ./geoipupdate.nix
    ./paperless.nix
  ];

  systemd.tmpfiles.rules = [
    "d /downloads        2770 matteo downloads"
  ];

  # To control /diskpool/media access
  users.groups.media = { };

  # To control /diskpool/downloads access
  users.groups.downloads = { };
}
