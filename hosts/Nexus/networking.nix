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

    # Use modern nftables backend instead of legacy iptables
    nftables.enable = true;

    # Enable firewall (required for fail2ban to function)
    firewall = {
      enable = true;

      # Allow HTTP/HTTPS for Caddy (ACME certificate validation and web services)
      allowedTCPPorts = [
        80 # HTTP (ACME challenges, redirects to HTTPS)
        443 # HTTPS (Caddy reverse proxy for all services)
      ]
      ++ config.services.openssh.ports
      ++ [
        config.services.paperless.port
        victoriaMetricsPort
        config.services.zigbee2mqtt.settings.frontend.port
        config.services.grafana.settings.server.http_port
      ]
      ++ lib.optionals config.services.nzbhydra2.enable [ 5076 ]
      ++ lib.optionals config.services.nzbget.enable [ 6789 ];

      # Allow HTTP/3 (QUIC) for Caddy
      allowedUDPPorts = [
        443 # HTTP/3 (QUIC)
      ];

      # Log refused packets for debugging
      logRefusedConnections = true;
    };
  };

}
