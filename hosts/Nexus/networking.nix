{ config, lib, ... }:
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
    nftables = {
      enable = true;
      # Flush ruleset on each reload to ensure clean state
      flushRuleset = true;
    };

    # Enable firewall (required for fail2ban to function)
    firewall = {
      enable = true;

      # Trust Tailscale interface — all traffic from the tailnet bypasses firewall rules.
      # Access control is handled by Tailscale ACLs instead.
      trustedInterfaces = [ "tailscale0" ];

      # Allow HTTP/HTTPS for Caddy (ACME certificate validation and web services)
      allowedTCPPorts = [
        80 # HTTP (ACME challenges, redirects to HTTPS)
        443 # HTTPS (Caddy reverse proxy for all services)
      ]
      ++ config.services.openssh.ports
      ++ [
        config.services.paperless.port
        config.services.zigbee2mqtt.settings.frontend.port
      ]
      ++ lib.optionals config.services.nzbhydra2.enable [ 5076 ]
      ++ lib.optionals config.services.nzbget.enable [ 6789 ]
      ++ lib.unique (map (l: l.port) config.services.mosquitto.listeners);

      # Allow HTTP/3 (QUIC) for Caddy
      allowedUDPPorts = [
        443 # HTTP/3 (QUIC)
      ];

      # Log refused packets for debugging
      logRefusedConnections = true;
    };
  };

}
