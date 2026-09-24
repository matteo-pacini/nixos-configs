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

  # DB password via agenix; compose2nix can't express this (env_file would
  # be resolved at generation time), so it lives here as an override.
  virtualisation.oci-containers.containers."nexus-n8n-n8n".environmentFiles = [
    config.age.secrets."nexus/n8n-env".path
  ];

  # n8n reaches the host PostgreSQL through its unix socket, bind-mounted into
  # the container, rather than over the podman bridge: postgres starts before
  # the bridge exists, so it could not bind 10.89.0.1 at boot. The socket is
  # reachable by any uid, so the role needs a password rather than peer auth.
  services.postgresql.authentication = ''
    local n8n n8n scram-sha-256
  '';

  # ensureUsers can't set passwords. Sync the role's password from the same
  # agenix file the container reads, so the two can't drift.
  systemd.services.n8n-postgres-password = {
    description = "Set the n8n PostgreSQL role password from agenix";
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      LoadCredential = "n8n-env:${config.age.secrets."nexus/n8n-env".path}";
    };
    path = [ config.services.postgresql.package ];
    # psql backticks read the password inside psql, keeping it out of argv.
    script = ''
      # An empty value would clear the password instead of failing.
      grep -q '^DB_POSTGRESDB_PASSWORD=.' "$CREDENTIALS_DIRECTORY/n8n-env"
      psql -v ON_ERROR_STOP=1 -d postgres <<'EOF'
      \set pw `sed -n 's/^DB_POSTGRESDB_PASSWORD=//p' "$CREDENTIALS_DIRECTORY/n8n-env"`
      ALTER ROLE n8n PASSWORD :'pw';
      EOF
    '';
  };

  # Requires= also propagates restarts: postgres recreates /run/postgresql
  # when it restarts, which would leave the container's bind mount stale.
  systemd.services."podman-nexus-n8n-n8n" = {
    after = [ "n8n-postgres-password.service" ];
    requires = [
      "postgresql.service"
      "n8n-postgres-password.service"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/n8n 0750 1000 1000 -"
  ];
}
