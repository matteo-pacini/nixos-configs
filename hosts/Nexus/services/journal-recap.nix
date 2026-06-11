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
    pkgs.systemd
    pkgs.claude-code
    pkgs.telegram-notify
  ];
  # End-to-end test run: same script, throwaway state dir (fresh cursor picks
  # up the last 6h; the real timer's cursor is untouched). Sends to the real
  # channel. Needs sudo to read the agenix secrets.
  journalRecapTest = pkgs.writeShellScriptBin "journal-recap-test" ''
    set -euo pipefail
    export TELEGRAM_ENV_FILE=${envFile}
    export CLAUDE_ENV_FILE=${claudeEnvFile}
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
      # Keep claude's config/cache out of /root
      Environment = [
        "HOME=%S/journal-recap"
        "TELEGRAM_ENV_FILE=${envFile}"
        "CLAUDE_ENV_FILE=${claudeEnvFile}"
      ];
      ExecStart = "${pkgs.bash}/bin/bash ${./journal-recap.sh}";
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
