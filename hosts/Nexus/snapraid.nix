{
  lib,
  pkgs,
  config,
  ...
}:
let
  # disk1 drained 2026-05-27 — failing SMART self-tests; see hardware-extra.nix
  # diskNumbers = lib.range 0 9;
  diskNumbers = lib.filter (n: n != 1) (lib.range 0 9);
  envFile = config.age.secrets."nexus/janitor.env".path;
in
{
  services.snapraid = {
    enable = true;
    dataDisks = lib.listToAttrs (
      map (n: {
        name = "d${toString n}";
        value = "/mnt/disk${toString n}";
      }) diskNumbers
    );
    contentFiles = map (n: "/mnt/disk${toString n}/snapraid.content") diskNumbers;
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
      "/mnt/parity2/snapraid.2-parity"
    ];
    exclude = [
      "*.unrecoverable"
      "/tmp/"
      "/lost+found/"
      # Immich regenerable caches: constantly rewritten (thumbnail/transcode
      # jobs) so they churn parity under a live sync, and are rebuilt on demand
      # anyway. Also omitted from the immich restic repo for the same reason.
      "/immich/thumbs/"
      "/immich/encoded-video/"
    ];
    touchBeforeSync = true;
    scrub = {
      interval = "Sun *-*-* 06:00:00";
      plan = 12;
      olderThan = 10;
    };
  };

  systemd.services = {
    "snapraid-scrub".serviceConfig = {
      IOSchedulingClass = "idle";
      RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      ExecStartPre = "${pkgs.telegram-notify}/bin/telegram-notify '🔍 SnapRAID scrub starting...'";
      ExecStartPost = "${pkgs.telegram-notify}/bin/telegram-notify '✅ SnapRAID scrub completed.'";
      Environment = "TELEGRAM_ENV_FILE=${envFile}";
    };
    "snapraid-sync" = {
      wantedBy = lib.mkForce [ ];
      startAt = lib.mkForce [ ];
    };
  };

}
