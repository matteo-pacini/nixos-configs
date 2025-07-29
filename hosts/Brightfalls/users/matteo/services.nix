{ pkgs, lib, ... }:
let
  mqtt2brightfallsUserland = pkgs.writeShellScriptBin "mqtt2brightfalls-user" ''
    set -euo pipefail

    FIFO="$XDG_RUNTIME_DIR/mqtt2brightfalls.fifo"

    while [[ ! -p "$FIFO" ]]; do
      echo "Waiting for FIFO $FIFO …"
      sleep 2
    done

    echo "MQTT user dispatcher started (PID $$)"

    while read -r topic payload < "$FIFO"; do
      case "$topic" in
        pc/brightfalls/corectrl)
            [[ -n "$payload" ]] && {
              echo "corectrl: applying profile \"$payload\""
              corectrl --activate-manual-profile "$payload"
            }
            ;;
        *)  # everything else: just print
            echo "Unhandled topic received: \"$topic\" payload: \"$payload\""
            ;;
      esac
    done
  '';
in
{
  systemd.user.services."mqtt2brightfalls-user" = {
    Unit = {
      Description = "mqtt2brightfalls user dispatcher";
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = lib.getExe mqtt2brightfallsUserland;
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

}
