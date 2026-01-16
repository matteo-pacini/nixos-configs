{
  pkgs,
  lib,
  isVM,
  ...
}:
let
  mqtt2brightfalls = pkgs.writeShellScriptBin "mqtt2brightfalls" ''
    set -o pipefail

    export PATH=${pkgs.mosquitto}/bin:$PATH

    MQTT_HOST="nexus.home.internal"
    MQTT_TOPIC="pc/brightfalls"

    BRIDGE_USER=matteo
    BRIDGE_UID=$(id -u "$BRIDGE_USER")
    FIFO=/run/user/$BRIDGE_UID/mqtt2brightfalls.fifo

    echo "Starting MQTT Brightfalls script..."

    if [[ ! -p $FIFO ]]; then
        echo "Creating FIFO at $FIFO"
        mkdir -p "$(dirname "$FIFO")"
        mkfifo "$FIFO"
        chown "$BRIDGE_USER:users" "$FIFO"
        chmod 600 "$FIFO"
    fi

    mosquitto_sub -h "$MQTT_HOST" -v -t "$MQTT_TOPIC/#" | while read -r message; do

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
  # SSH server with passwordless access on local subnet for debugging
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Allow passwordless SSH from local subnet
  users.users.matteo.openssh.authorizedKeys.keys = [
    # NightSprings (MacBook)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILn8qGjRSufdOKPFFbzrxBI+D0PeSVq8MGygdQNaTqQX m@matteopacini.me"
  ];

  services.fstrim.enable = lib.mkIf (!isVM) true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

  # Fix service to activate swap at login screen
  systemd.services.fix-swap = lib.mkIf (!isVM) {
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

  services.fwupd.enable = lib.mkIf (!isVM) true;

  systemd.services.mqtt2brightfalls = lib.mkIf (!isVM) {
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

    script = lib.getExe mqtt2brightfalls;
  };

}
