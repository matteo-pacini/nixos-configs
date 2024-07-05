{
  pkgs,
  config,
  lib,
  ...
}:
let
  backupDestination = "/diskpool/configuration";
  affectedServices = [
    "jellyfin"
    "nzbget"
  ];
  backupJob = pkgs.writeShellScriptBin "backupJob2" ''
    set -eo pipefail
    source ${config.age.secrets."nexus/janitor.env".path}

    # Notify on Telegram
    MESSAGE="Nexus will go down for maintenance in 60 seconds..."
    ${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      --data chat_id="$CHANNEL_ID" \
      --data parse_mode="Markdown" \
      --data-urlencode "text=$MESSAGE"

    # Wait
    sleep 60

    # Stop all services
    ${lib.concatMapStringsSep "\n" (service: "systemctl stop ${service}") affectedServices}

    RSYNC_CMD="${pkgs.rsync}/bin/rsync -avh --delete"

    # Jellyfin
    ''${RSYNC_CMD} ${config.services.jellyfin.dataDir} ${backupDestination}/
    # NZBGet
    ''${RSYNC_CMD} /var/lib/nzbget ${backupDestination}/

    # Restart all services
    ${lib.concatMapStringsSep "\n" (service: "systemctl start ${service}") affectedServices}

    # Notify on Telegram
    MESSAGE="Nexus is back online."
    ${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      --data chat_id="$CHANNEL_ID" \
      --data parse_mode="Markdown" \
      --data-urlencode "text=$MESSAGE"

  '';
in
{

  systemd.timers."backup-job" = {
    description = "Backup of configs via RSYNC (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Unit = "backup-job.service";
    };
  };

  systemd.services = {
    "backup-job" = {
      description = "Backup of configs via RSYNC";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe backupJob}";
      };
    };
  };
}
