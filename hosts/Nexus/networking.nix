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
      ++ lib.optionals config.services.nzbhydra2.enable [ 5076 ]
      ++ lib.optionals config.services.nzbget.enable [ 6789 ]
      ++ lib.unique (map (l: l.port) config.services.mosquitto.listeners);

      # Admin web UIs (paperless, zigbee2mqtt, radarr, sonarr): trusted-device
      # VLAN + WorkLaptop only. Guest and IoT VLANs and WAN are blocked.
      # Tailnet bypasses via trustedInterfaces.
      extraInputRules =
        let
          uiPorts = lib.concatMapStringsSep ", " toString [
            config.services.paperless.port
            config.services.zigbee2mqtt.settings.frontend.port
            config.services.radarr.settings.server.port
            config.services.sonarr.settings.server.port
          ];
        in
        ''
          ip saddr { 192.168.10.0/24, 192.168.20.143 } tcp dport { ${uiPorts} } accept
        '';

      # n8n's paperless agent tools call 28981 from inside the container;
      # that traffic arrives via the podman bridge, not a trusted saddr.
      interfaces."podman*".allowedTCPPorts = [ config.services.paperless.port ];

      # Allow HTTP/3 (QUIC) for Caddy
      allowedUDPPorts = [
        443 # HTTP/3 (QUIC)
      ];

      # Log refused packets for debugging
      logRefusedConnections = true;
    };
  };

}
