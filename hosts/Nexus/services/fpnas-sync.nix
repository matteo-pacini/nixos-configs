{ pkgs, config, ... }:
let
  destination = "/diskpool/fabrizio";
  envFile = config.age.secrets."nexus/janitor.env".path;
  keyFile = config.age.secrets."nexus/fpnas-sync-key".path;
  host = "fpnas3.tailadca8a.ts.net";
  port = "2812";

  # Mirror of fpnas (the source of truth). Runs as fabrizio, so new
  # files are owned by fabrizio:users and take their mode from the default ACL
  # on the destination (--no-perms), which grants matteo access.
  # --max-delete caps a mass deletion on the NAS from mirroring overnight;
  # past it rsync exits 25 and the unit fails.
  syncScript = pkgs.writeShellScript "fpnas-sync" ''
    set -euo pipefail
    exec ${pkgs.rsync}/bin/rsync -rlt --no-perms --delete --max-delete=200 \
      --exclude '#recycle/' \
      --exclude '@eaDir/' \
      --exclude '.DS_Store' \
      --exclude 'desktop.ini' \
      --exclude 'Thumbs.db' \
      --filter 'P /nexus-only/' \
      --stats \
      -e '${pkgs.openssh}/bin/ssh -p ${port} -i ${keyFile} -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes' \
      'fabrizio@${host}:/volume1/legacy/' ${destination}/
  '';
in
{
  programs.ssh.knownHosts.fpnas = {
    hostNames = [ "[${host}]:${port}" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEd0ygb6UctKe+idqt0d1r8NRw1HrF1/GVpY6Ez7pkh5";
  };

  systemd.timers.fpnas-sync = {
    description = "Nightly pull of fpnas";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };

  systemd.services = {
    # Ordered before backup-job so SnapRAID parity (backup-job) and restic
    # (06:00) see the new files the same night. backup-job does not require
    # it: fpnas being offline must not hold back the rest of the backup.
    fpnas-sync = {
      description = "Pull fpnas into ${destination}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "backup-job.service" ];
      onFailure = [ "fpnas-sync-failed.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "fabrizio";
        Group = "users";
        ExecStart = syncScript;
        # 24: files vanished on the NAS mid-run
        SuccessExitStatus = [ 24 ];
        # Ends before the 03:00 backup-job; the first full pull is done by hand
        TimeoutStartSec = "50min";
        Nice = 10;
        IOSchedulingClass = "idle";
        ProtectSystem = "strict";
        ReadWritePaths = [ destination ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    fpnas-sync-failed = {
      description = "Report a failed fpnas-sync";
      serviceConfig.Type = "oneshot";
      environment.TELEGRAM_ENV_FILE = envFile;
      script = ''
        ${pkgs.telegram-notify}/bin/telegram-notify "fpnas-sync failed (exit 25 = --max-delete cap hit). See: journalctl -u fpnas-sync"
      '';
    };
  };
}
