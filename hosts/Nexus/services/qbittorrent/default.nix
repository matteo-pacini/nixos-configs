{
  config,
  lib,
  pkgs,
  ...
}:
let
  downloadDir = "/downloads/torrent";
  configDir = "/var/lib/qbittorrent";
in
{
  imports = [
    ./docker-compose.nix
  ];

  users.users.qbittorrent = {
    isSystemUser = true;
    group = "qbittorrent";
    extraGroups = [
      "downloads"
    ];
  };

  users.groups.qbittorrent = { };

  systemd.tmpfiles.rules = [
    "d ${downloadDir} 2770 qbittorrent downloads"
    "d ${configDir}   0700 qbittorrent qbittorrent"
  ];

  # Overrides

  virtualisation.oci-containers.containers."nexus-qbittorrent-gluetun" = {
    environment = {
      "SERVER_CITIES" = "London";
    };
    environmentFiles = [
      config.age.secrets."nexus/wireguard.env".path
    ];
  };

  virtualisation.oci-containers.containers."nexus-qbittorrent-torrent" = {
    environment = {
      "WEBUI_PORT" = "7777";
      "TZ" = config.time.timeZone;
    };
    volumes = [
      "${downloadDir}:/downloads:rw"
      "${configDir}:/config:rw"
    ];
    extraOptions = [
      "-e=PUID"
      "-e=PGID"
    ];
  };

  systemd.services."podman-nexus-qbittorrent-torrent".script = lib.mkBefore ''
    export PUID="$(${pkgs.coreutils}/bin/id -u qbittorrent)"
    export PGID="$(${pkgs.getent}/bin/getent group downloads | cut -d: -f3)"
  '';

}
