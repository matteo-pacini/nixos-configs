{ config, ... }:
let
  downloadDir = "/downloads/torrent";
  configDir = "/var/lib/qbittorrent";
in
{
  imports = [
    ./docker-compose.nix
  ];

  users.users.qbittorrent = {
    uid = 390;
    isSystemUser = true;
    group = "qbittorrent";
    extraGroups = [
      "downloads"
    ];
  };

  users.groups.qbittorrent = {
    gid = 390;
  };

  systemd.tmpfiles.rules = [
    "d ${downloadDir} 2770 qbittorrent downloads"
    "d ${configDir}   0700 qbittorrent qbittorrent"
  ];

  # Overrides

  virtualisation.oci-containers.containers."gluetun" = {
    environment = {
      "SERVER_CITIES" = "London";
    };
    environmentFiles = [
      config.age.secrets."nexus/wireguard.env".path
    ];
  };

  virtualisation.oci-containers.containers."torrent" = {
    environment = {
      "WEBUI_PORT" = "7777";
      "PUID" = toString config.users.users.qbittorrent.uid;
      "PGID" = toString config.users.groups.qbittorrent.gid;
      "TZ" = config.time.timeZone;
    };
    volumes = [
      "${downloadDir}:/downloads:rw"
      "${configDir}:/config:rw"
    ];
  };
}
