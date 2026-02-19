{ config, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d /diskpool/nextcloud 0750 nextcloud nextcloud"
    "d /var/log/nextcloud  0750 nextcloud nextcloud"
  ];

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;
    hostName = "nextcloud.matteopacini.me";
    https = true;
    datadir = "/diskpool/nextcloud";
    maxUploadSize = "16G";

    # Database: use existing PostgreSQL (configured in postgresql.nix)
    database.createLocally = false;
    config = {
      dbtype = "pgsql";
      dbuser = "nextcloud";
      dbname = "nextcloud";
      dbhost = "/run/postgresql";
      adminuser = "matteo";
      adminpassFile = config.age.secrets."nexus/nextcloud-admin-password".path;
    };

    configureRedis = true;

    settings = {
      trusted_proxies = [
        "127.0.0.1"
        "::1"
      ];
      overwriteprotocol = "https";
      default_phone_region = "IT";
      log_type = "file";
      logfile = "/var/log/nextcloud/nextcloud.log";
      loglevel = 2;
      maintenance_window_start = 1;
      enabledPreviewProviders = [
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"
        "OC\\Preview\\HEIC"
        "OC\\Preview\\WebP"
      ];
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
      "opcache.max_accelerated_files" = "10000";
      "opcache.memory_consumption" = "256";
      "opcache.revalidate_freq" = "1";
    };

    autoUpdateApps.enable = true;
    autoUpdateApps.startAt = "05:00:00";

    extraApps = with config.services.nextcloud.package.packages.apps; {
      inherit
        calendar
        contacts
        notes
        tasks
        ;
    };
  };

  # nginx: internal only, not network-accessible
  services.nginx = {
    enable = true;
    defaultListenAddresses = [ "127.0.0.1" ];
    defaultHTTPListenPort = 8085;
    virtualHosts."nextcloud.matteopacini.me" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 8085;
        }
      ];
    };
  };

  # Ensure nextcloud-setup waits for PostgreSQL
  systemd.services.nextcloud-setup = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
}
