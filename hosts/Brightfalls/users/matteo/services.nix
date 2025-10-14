{
  pkgs,
  lib,
  isVM,
  ...
}:
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
        pc/brightfalls/launch_lact)
          # Check if lact process is already running
          if ! pgrep -f "lact gui" > /dev/null; then
            echo "Launching lact"
            nohup setsid lact gui >/dev/null 2>&1 </dev/null &
          else
            echo "lact is already running"
          fi
          ;;
        pc/brightfalls/launch_steam_bigpicture)
          xdg-open steam://open/gamepadui
          ;;
        *)  
          echo "Unhandled topic received: \"$topic\" payload: \"$payload\""
          ;;
      esac
    done
  '';
in
{
  systemd.user.services."mqtt2brightfalls-user" = lib.mkIf (!isVM) {
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
