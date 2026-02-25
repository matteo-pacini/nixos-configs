{
  pkgs,
  config,
  lib,
  ...
}:
let
  backupDestination = "/diskpool/configuration";
  envFile = config.age.secrets."nexus/janitor.env".path;
  resticEnvFile = config.age.secrets."nexus/restic-env".path;
  resticPasswordFile = config.age.secrets."nexus/restic-password".path;
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
    "nexus-n8n"
  ];
  fullComposeTargetName = shortName: "podman-compose-${shortName}-root.target";

  # ── Restic shared configuration ──────────────────────────────────────

  b2Endpoint = "s3:s3.eu-central-003.backblazeb2.com";

  b2ExtraOptions = [ "s3.connections=10" ];

  b2ExtraBackupArgs = [
    "--pack-size 32"
    "--exclude-caches"
  ];

  personalExcludes = [
    ".cache"
    "cache/"
    "Cache/"
    ".thumbnails"
    "__pycache__/"
    "node_modules/"
    ".Trash"
    ".local/share/Trash"
    "*.tmp"
    "*~"
    "*.swp"
  ];

  configExcludes = [
    "/diskpool/configuration/nextcloud/data/*/files"
    "*.log"
    "cache/"
  ];

  personalRetention = [
    "--keep-daily 7"
    "--keep-weekly 5"
    "--keep-monthly 12"
    "--keep-yearly 5"
  ];

  configRetention = [
    "--keep-daily 14"
    "--keep-weekly 4"
    "--keep-monthly 12"
    "--keep-yearly 2"
  ];

  # ── Wrapper script for interactive restic queries ────────────────────

  restic-b2 = pkgs.writeShellScriptBin "restic-b2" ''
    set -euo pipefail

    REPOS="matteo debora fabrizio config"

    if [[ $# -lt 2 ]]; then
      echo "Usage: restic-b2 <repo> <restic command...>"
      echo "Available repos: $REPOS"
      exit 1
    fi

    REPO_NAME="$1"
    shift

    case "$REPO_NAME" in
      matteo)    REPO_URL="${b2Endpoint}/matteo-nexus-backup" ;;
      debora)    REPO_URL="${b2Endpoint}/debora-nexus-backup" ;;
      fabrizio)  REPO_URL="${b2Endpoint}/fabrizio-nexus-backup" ;;
      config)    REPO_URL="${b2Endpoint}/config-nexus-backup" ;;
      *)
        echo "Unknown repo: $REPO_NAME"
        echo "Available repos: $REPOS"
        exit 1
        ;;
    esac

    set -a
    source "${resticEnvFile}"
    set +a

    export RESTIC_REPOSITORY="$REPO_URL"
    export RESTIC_PASSWORD_FILE="${resticPasswordFile}"

    exec ${pkgs.restic}/bin/restic "$@"
  '';

  # ── Local backup jobs (rsync + SnapRAID) ─────────────────────────────

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
  environment.systemPackages = [ restic-b2 ];

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

    # Ensure restic B2 backups run after the local backup pipeline
    "restic-backups-config".after = [ "backup-job.service" ];
    "restic-backups-matteo".after = [ "backup-job.service" ];
    "restic-backups-debora".after = [ "backup-job.service" ];
    "restic-backups-fabrizio".after = [ "backup-job.service" ];
  };

  services.restic.backups = {
    config = {
      initialize = true;
      user = "root";
      repository = "${b2Endpoint}/config-nexus-backup";
      environmentFile = resticEnvFile;
      passwordFile = resticPasswordFile;
      paths = [
        "/diskpool/configuration"
      ];
      exclude = configExcludes;
      pruneOpts = configRetention;
      runCheck = true;
      checkOpts = [ "--read-data-subset=2%" ];
      extraOptions = b2ExtraOptions;
      extraBackupArgs = b2ExtraBackupArgs;

      timerConfig = {
        OnCalendar = "*-*-* 04:30:00";
        Persistent = true;
      };
    };

    matteo = {
      initialize = true;
      user = "root";
      repository = "${b2Endpoint}/matteo-nexus-backup";
      environmentFile = resticEnvFile;
      passwordFile = resticPasswordFile;
      paths = [
        "/diskpool/nextcloud/data/matteo"
      ];
      exclude = personalExcludes;
      pruneOpts = personalRetention;
      runCheck = true;
      checkOpts = [ "--read-data-subset=2%" ];
      extraOptions = b2ExtraOptions;
      extraBackupArgs = b2ExtraBackupArgs;
      timerConfig = {
        OnCalendar = "*-*-* 05:00:00";
        Persistent = true;
      };
    };

    debora = {
      initialize = true;
      user = "root";
      repository = "${b2Endpoint}/debora-nexus-backup";
      environmentFile = resticEnvFile;
      passwordFile = resticPasswordFile;
      paths = [
        "/diskpool/nextcloud/data/Debora Cristiano"
      ];
      exclude = personalExcludes;
      pruneOpts = personalRetention;
      runCheck = true;
      checkOpts = [ "--read-data-subset=2%" ];
      extraOptions = b2ExtraOptions;
      extraBackupArgs = b2ExtraBackupArgs;
      timerConfig = {
        OnCalendar = "*-*-* 05:30:00";
        Persistent = true;
      };
    };

    fabrizio = {
      initialize = true;
      user = "root";
      repository = "${b2Endpoint}/fabrizio-nexus-backup";
      environmentFile = resticEnvFile;
      passwordFile = resticPasswordFile;
      paths = [
        "/diskpool/fabrizio"
      ];
      exclude = personalExcludes;
      pruneOpts = personalRetention;
      runCheck = true;
      checkOpts = [ "--read-data-subset=2%" ];
      extraOptions = b2ExtraOptions;
      extraBackupArgs = b2ExtraBackupArgs;
      timerConfig = {
        OnCalendar = "*-*-* 06:00:00";
        Persistent = true;
      };
    };
  };
}
