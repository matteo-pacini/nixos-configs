{ config, lib, ... }:
let
  # Extract port from VictoriaMetrics listenAddress (format: "0.0.0.0:8428")
  victoriaMetricsPort = lib.toInt (
    lib.last (lib.splitString ":" config.services.victoriametrics.listenAddress)
  );
in
{
  networking.hostName = "Nexus";

  networking = {
    useDHCP = false;
    useNetworkd = true;
    interfaces.eno1.useDHCP = true;

    nameservers = [
      "1.1.1.1" # Cloudflare DNS (primary)
      "8.8.8.8" # Google DNS (secondary)
    ];

    # Enable firewall (required for fail2ban to function)
    firewall = {
      enable = true;

      # Allow HTTP/HTTPS for nginx (ACME certificate validation and web services)
      allowedTCPPorts = [
        80 # HTTP (ACME challenges, redirects to HTTPS)
        443 # HTTPS (nginx reverse proxy for all services)
      ]
      ++ config.services.openssh.ports
      ++ [
        config.services.paperless.port
        victoriaMetricsPort
        config.services.zigbee2mqtt.settings.frontend.port
        config.services.grafana.settings.server.http_port
      ];

      # Log refused packets for debugging
      logRefusedConnections = true;
    };
  };

}
