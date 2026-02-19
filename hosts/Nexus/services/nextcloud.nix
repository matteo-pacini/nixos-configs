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
      # Allow Nextcloud apps to reach local services (e.g. paperless at localhost:28981)
      allow_local_remote_servers = true;
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

  # Enable the bundled files_external app for Paperless directory mounts.
  # files_external is a core Nextcloud app (ships with the server), it just needs enabling.
  systemd.services.nextcloud-paperless-setup = {
    description = "Enable files_external app for Paperless integration";
    after = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nextcloud";
    };
    path = [ config.services.nextcloud.occ ];
    script = ''
      nextcloud-occ app:enable files_external || true
    '';
  };

  # Periodic scan so Nextcloud picks up new files written by paperless to external storage.
  systemd.services.nextcloud-scan-external = {
    description = "Scan Nextcloud external storage for new documents";
    after = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
    };
    path = [ config.services.nextcloud.occ ];
    script = ''
      nextcloud-occ files:scan --all --shallow
    '';
  };

  systemd.timers.nextcloud-scan-external = {
    description = "Timer for scanning Nextcloud external storage";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
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
