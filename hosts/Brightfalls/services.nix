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
    openFirewall = true;
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
    ports = [ 1788 ];
  };

  # Allow passwordless SSH from local subnet
  users.users.matteo.openssh.authorizedKeys.keys = [
    # Work Laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH0nEXegOpQunZOaVcw03ZE/jcWKeUcNx2UUhiZC6CXO matteo.pacini@work-laptop.guest.internal"
    # NightSprings (MacBook Pro M1 Max)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQiM93t9mXjpqdtY12ohNAELZNg1SOdE47bWNRb4HC0 matteo@NightSprings"
  ];

  services.fstrim.enable = lib.mkIf (!isVM) true;

  # https://discourse.nixos.org/t/connected-to-mullvadvpn-but-no-internet-connection/35803/8?u=lion
  services.resolved.enable = true;
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

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
