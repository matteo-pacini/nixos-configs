{
  pkgs,
  config,
  lib,
  ...
}:
let
  backupDestination = "/diskpool/configuration";
  envFile = config.age.secrets."nexus/janitor.env".path;
  notify = "${pkgs.telegram-notify}/bin/telegram-notify";
  haServices = [
    "zigbee2mqtt"
    "mosquitto"
    "home-assistant"
    "victoriametrics"
    "victorialogs"
    "grafana"
  ];
  affectedServices = [
    "jellyfin"
    "nzbget"
    "nzbhydra2"
    "radarr"
    "sonarr"
    "paperless-web"
    "paperless-scheduler"
    "paperless-consumer"
    "paperless-task-queue"
    "phpfpm-nextcloud"
    "nginx"
  ];
  affectedComposeTargets = [
    "nexus-qbittorrent"
    "nexus-n8n"
  ];
  fullComposeTargetName = shortName: "podman-compose-${shortName}-root.target";
  haBackupJob = pkgs.writeShellScriptBin "haBackupJob_4" ''
    set -eo pipefail
    export TELEGRAM_ENV_FILE="${envFile}"

    ${notify} "Home Assistant services will go down for backup in 60 seconds..."

    # Wait
    sleep 60

    # Stop HA services
    ${lib.concatMapStringsSep "\n" (service: "systemctl stop ${service}") haServices}

    RSYNC_CMD="${pkgs.rsync}/bin/rsync -avh --delete"

    # zigbee2mqtt
    ''${RSYNC_CMD} ${config.services.zigbee2mqtt.dataDir} ${backupDestination}/
    # mosquitto
    ''${RSYNC_CMD} ${config.services.mosquitto.dataDir} ${backupDestination}/
    # home-assistant
    ''${RSYNC_CMD} ${config.services.home-assistant.configDir} ${backupDestination}/
    # victoriametrics
    ''${RSYNC_CMD} -L /var/lib/${config.services.victoriametrics.stateDir} ${backupDestination}/
    # victorialogs
    ''${RSYNC_CMD} -L /var/lib/${config.services.victorialogs.stateDir} ${backupDestination}/
    # grafana
    ''${RSYNC_CMD} ${config.services.grafana.dataDir} ${backupDestination}/

    # Special case: PostgreSQL
    # Does not need to be stopped, just backed up
    ''${RSYNC_CMD} ${config.services.postgresqlBackup.location} ${backupDestination}/

    # Restart HA services
    ${lib.concatMapStringsSep "\n" (service: "systemctl start ${service}") haServices}

    ${notify} "Home Assistant services back online, starting full backup..."
  '';

  backupJob = pkgs.writeShellScriptBin "backupJob_19" ''
    set -eo pipefail
    export TELEGRAM_ENV_FILE="${envFile}"

    ${notify} "Remaining Nexus services will go down for maintenance in 60 seconds..."

    # Wait
    sleep 60

    # Stop all services
    ${lib.concatMapStringsSep "\n" (service: "systemctl stop ${service}") affectedServices}

    # Stop all compose targets
    ${lib.concatMapStringsSep "\n" (
      service: "systemctl stop ${fullComposeTargetName service}"
    ) affectedComposeTargets}

    # This is needed to ensure that the services are fully stopped before proceeding with the backup
    sleep 60

    RSYNC_CMD="${pkgs.rsync}/bin/rsync -avh --delete"

    # Jellyfin
    ''${RSYNC_CMD} ${config.services.jellyfin.dataDir} ${backupDestination}/
    # NZBGet
    ''${RSYNC_CMD} /var/lib/nzbget ${backupDestination}/
    # nzbhydra2
    ''${RSYNC_CMD} ${config.services.nzbhydra2.dataDir} ${backupDestination}/
    # radarr
    ''${RSYNC_CMD} ${config.services.radarr.dataDir} ${backupDestination}/
    # sonarr
    ''${RSYNC_CMD} ${config.services.sonarr.dataDir} ${backupDestination}/
    # qbittorrent
    ''${RSYNC_CMD} /var/lib/qbittorrent ${backupDestination}/
    # paperless - data directory
    ''${RSYNC_CMD} ${config.services.paperless.dataDir} ${backupDestination}/
    # paperless - media directory
    ''${RSYNC_CMD} ${config.services.paperless.mediaDir} ${backupDestination}/
    # n8n - application data
    ''${RSYNC_CMD} /var/lib/n8n ${backupDestination}/
    # n8n - PostgreSQL database
    ''${RSYNC_CMD} /var/lib/postgresql_n8n ${backupDestination}/
    # nextcloud
    ''${RSYNC_CMD} /diskpool/nextcloud ${backupDestination}/

    # Sync SnapRAID
    ${pkgs.snapraid}/bin/snapraid --force-zero sync

    # Restart all services
    ${lib.concatMapStringsSep "\n" (service: "systemctl start ${service}") affectedServices}

    # Restart all compose targets
    ${lib.concatMapStringsSep "\n" (
      service: "systemctl start ${fullComposeTargetName service}"
    ) affectedComposeTargets}

    ${notify} "Nexus is fully back online."
  '';
in
{
  systemd.timers."backup" = {
    description = "Backup sequence timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      Unit = "backup-job.service";
    };
  };

  systemd.services = {
    "ha-backup" = {
      description = "Fast HA services backup";
      before = [ "backup-job.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe haBackupJob}";
      };
    };

    "backup-job" = {
      description = "Slow services backup";
      after = [ "ha-backup.service" ];
      requires = [ "ha-backup.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe backupJob}";
      };
    };
  };

  services.restic.backups = {
    matteo = {
      user = "root";
      repository = "s3:s3.eu-central-003.backblazeb2.com/matteo-nexus-backup";
      environmentFile = config.age.secrets."nexus/restic-env".path;
      passwordFile = config.age.secrets."nexus/restic-password".path;
      paths = [
        "/diskpool/matteo"
      ];
      timerConfig = {
        OnCalendar = "daily";
      };
    };
    debora = {
      initialize = true;
      user = "root";
      repository = "s3:s3.eu-central-003.backblazeb2.com/debora-nexus-backup";
      environmentFile = config.age.secrets."nexus/restic-env".path;
      passwordFile = config.age.secrets."nexus/restic-password".path;
      paths = [
        "/diskpool/debora"
      ];
      timerConfig = {
        OnCalendar = "daily";
      };
    };
    fabrizio = {
      initialize = true;
      user = "root";
      repository = "s3:s3.eu-central-003.backblazeb2.com/fabrizio-nexus-backup";
      environmentFile = config.age.secrets."nexus/restic-env".path;
      passwordFile = config.age.secrets."nexus/restic-password".path;
      paths = [
        "/diskpool/fabrizio"
      ];
      timerConfig = {
        OnCalendar = "daily";
      };
    };
    config = {
      initialize = true;
      user = "root";
      repository = "s3:s3.eu-central-003.backblazeb2.com/config-nexus-backup";
      environmentFile = config.age.secrets."nexus/restic-env".path;
      passwordFile = config.age.secrets."nexus/restic-password".path;
      paths = [
        "/diskpool/configuration"
      ];
      timerConfig = {
        OnCalendar = "daily";
      };
    };
  };
}
