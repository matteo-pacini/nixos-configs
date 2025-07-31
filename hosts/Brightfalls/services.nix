{
  pkgs,
  lib,
  config,
  ...
}:
let
  mqtt2brightfalls = pkgs.writeShellScriptBin "mqtt2brightfalls" ''
    set -o pipefail

    export PATH=${pkgs.mosquitto}/bin:$PATH

    MQTT_HOST="nexus.home.internal"
    MQTT_TOPIC="pc/brightfalls"
    MQTT_USER="brightfalls"
    MQTT_PASSWORD_FILE=''${MQTT_PASSWORD_FILE: -"/tmp/password"}

    BRIDGE_USER=matteo
    BRIDGE_UID=$(id -u "$BRIDGE_USER")
    FIFO=/run/user/$BRIDGE_UID/mqtt2brightfalls.fifo

    # Read password from file
    if [[ -f "$MQTT_PASSWORD_FILE" ]]; then
        MQTT_PASSWORD=$(cat "$MQTT_PASSWORD_FILE")
    else
        echo "Warning: Password file not found at $MQTT_PASSWORD_FILE"
        MQTT_PASSWORD=""
    fi

    echo "Starting MQTT Brightfalls script..."

    if [[ ! -p $FIFO ]]; then
        echo "Creating FIFO at $FIFO"
        mkdir -p "$(dirname "$FIFO")"
        mkfifo "$FIFO"
        chown "$BRIDGE_USER:users" "$FIFO"
        chmod 600 "$FIFO"
    fi

    mosquitto_sub -h "$MQTT_HOST" -v -t "$MQTT_TOPIC/#" -u "$MQTT_USER" -P "$MQTT_PASSWORD" | while read -r message; do
        
        topic=$(echo "$message" | cut -d ' ' -f 1)
        payload=$(echo "$message" | cut -d ' ' -f 2-)
        
        echo "Received $topic: ''${payload}"

        case "$topic" in
            "$MQTT_TOPIC/shutdown")
                echo "Shutting down system..."
                systemctl poweroff
                ;;
            *)
                echo "Writing to userland: $topic $payload"
                printf '%s %s\n' "$topic" "$payload" > "$FIFO"
                ;;
        esac

    done 
  '';
in
{
  services.fstrim.enable = true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

  # Fix service to activate swap at login screen
  systemd.services.fix-swap = {
    description = "Fix Swap Service";

    # Run after the graphical login screen appears
    wantedBy = [ "graphical.target" ];
    after = [ "graphical.target" ];

    # Run only once at startup
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # The actual command to activate the swap using systemctl
    script = ''
      # Check if swap service is already active
      if ! systemctl is-active dev-mapper-swap.swap &>/dev/null; then
        # Try to start the swap service
        systemctl start dev-mapper-swap.swap || true
      fi
    '';
  };

  services.fwupd.enable = true;

  systemd.services.mqtt2brightfalls = {
    description = "MQTT to Brightfalls bridge service";
    wantedBy = [ "graphical.target" ];
    after = [
      "graphical.target"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10";
      User = "root";
    };

    environment = {
      MQTT_PASSWORD_FILE = config.age.secrets."nexus/mosquitto-brightfalls-password".path;
    };

    script = lib.getExe mqtt2brightfalls;
  };

}
