{ lib, ... }:
{
  networking.hostName = "Nexus";

  networking = {
    useDHCP = false;
    useNetworkd = true;
    interfaces.eno1.useDHCP = true;

    # Enable firewall (required for fail2ban to function)
    firewall = {
      enable = true;

      # Allow HTTP/HTTPS for nginx (ACME certificate validation and web services)
      allowedTCPPorts = [
        80 # HTTP (ACME challenges, redirects to HTTPS)
        443 # HTTPS (nginx reverse proxy for all services)
        1788 # SSH (custom port)
      ];

      # Allow DNS queries (required for Home Assistant integrations)
      allowedUDPPorts = [
        53 # DNS
      ];

      # Log refused packets for debugging
      logRefusedConnections = true;

      # Ensure outbound connections are allowed (should be default, but explicit is better)
      checkReversePath = false;
    };
  };

}
