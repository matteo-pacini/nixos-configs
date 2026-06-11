{
  pkgs,
  config,
  lib,
  ...
}:
let
  envFile = config.age.secrets."nexus/janitor.env".path;
  claudeEnvFile = config.age.secrets."nexus/claude.env".path;
  runtimeDeps = [
    pkgs.bash
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.systemd
    pkgs.claude-code
    pkgs.telegram-notify
  ];
  alertMention = "@matteopacini";
  # End-to-end test run: same script, throwaway state dir (fresh cursor picks
  # up the last 6h; the real timer's cursor is untouched). Sends to the real
  # channel. Needs sudo to read the agenix secrets. Pass "alert" to force the
  # mention path (tests ping-through-mute).
  journalRecapTest = pkgs.writeShellScriptBin "journal-recap-test" ''
    set -euo pipefail
    if [[ "''${1:-}" == "alert" ]]; then
      export FORCE_ALERT=1
    fi
    export TELEGRAM_ENV_FILE=${envFile}
    export CLAUDE_ENV_FILE=${claudeEnvFile}
    export ALERT_MENTION=${alertMention}
    STATE_DIRECTORY=$(${pkgs.coreutils}/bin/mktemp -d)
    export STATE_DIRECTORY
    export HOME=$STATE_DIRECTORY
    export PATH=${lib.makeBinPath runtimeDeps}:$PATH
    trap '${pkgs.coreutils}/bin/rm -rf "$STATE_DIRECTORY"' EXIT
    ${pkgs.bash}/bin/bash ${./journal-recap.sh}
    echo "journal-recap test run complete - check Telegram"
  '';
in
{
  environment.systemPackages = [ journalRecapTest ];

  systemd.services.journal-recap = {
    description = "Claude digest of journal errors to Telegram";
    path = runtimeDeps;
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "journal-recap";
      TimeoutStartSec = "15min"; # oneshot runtime cap (claude hang guard)

      # Unprivileged: secrets are loaded by systemd (as root) and exposed
      # read-only via the credentials directory (%d); journal access comes
      # from the systemd-journal group instead of running as root.
      DynamicUser = true;
      SupplementaryGroups = [ "systemd-journal" ];
      LoadCredential = [
        "janitor.env:${envFile}"
        "claude.env:${claudeEnvFile}"
      ];

      # %S = /var/lib, %d = credentials directory
      Environment = [
        "HOME=%S/journal-recap" # keep claude's config/cache in the state dir
        "TELEGRAM_ENV_FILE=%d/janitor.env"
        "CLAUDE_ENV_FILE=%d/claude.env"
        "ALERT_MENTION=${alertMention}"
      ];
      ExecStart = "${pkgs.bash}/bin/bash ${./journal-recap.sh}";

      # Hardening. Notes:
      # - io_uring_* must be allowed explicitly: claude is a Bun binary and
      #   Bun uses io_uring on Linux; @system-service does not include it.
      # - No PrivateUsers/ProcSubset: PrivateUsers breaks the
      #   systemd-journal group mapping; ProcSubset=pid hides /proc/meminfo
      #   from the JS runtime.
      # - No MemoryDenyWriteExecute: Bun JIT needs W^X.
      CapabilityBoundingSet = "";
      LockPersonality = true;
      MemoryMax = "2G";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "io_uring_setup"
        "io_uring_enter"
        "io_uring_register"
      ];
      UMask = "0077";
    };
  };

  systemd.timers.journal-recap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "0/6:00:00"; # every 6 hours
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };
}
