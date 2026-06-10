{ config, ... }:
{
  imports = [
    ./docker-compose.nix
  ];

  # Hairpin fix: public DNS returns the WAN IP, and the router won't
  # hairpin from Nexus to itself. Pin to loopback so local clients (HA
  # webhook_conversation) reach n8n via Caddy with a valid cert.
  # Same pattern as cache.matteopacini.me in ../attic.nix.
  networking.hosts."127.0.0.1" = [ "n8n.matteopacini.me" ];

  # DB passwords via agenix; compose2nix can't express this (env_file would
  # be resolved at generation time), so it lives here as an override.
  virtualisation.oci-containers.containers."nexus-n8n-n8n".environmentFiles = [
    config.age.secrets."nexus/n8n-env".path
  ];
  virtualisation.oci-containers.containers."nexus-n8n-postgres".environmentFiles = [
    config.age.secrets."nexus/n8n-env".path
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/n8n 0750 1000 1000 -"
    "d /var/lib/postgresql_n8n 0750 999 999 -"
  ];
}
