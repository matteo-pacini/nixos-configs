{ config, ... }:
{
  # The upstream module defaults to DynamicUser, whose UID is recycled
  # across restarts and so can't safely own storage on /diskpool.
  # Defining the user statically makes systemd use it instead
  # (systemd.exec(5), DynamicUser=), and enables Postgres peer auth.
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = { };

  systemd.tmpfiles.rules = [
    "d /diskpool/attic 0750 atticd atticd"
  ];

  # Nexus resolves cache.matteopacini.me via public DNS to the WAN IP,
  # which the router won't hairpin — pin it to loopback instead
  # (Caddy listens on *:443). LAN clients get the LAN IP via the
  # router's split DNS.
  networking.hosts."127.0.0.1" = [ "cache.matteopacini.me" ];

  # Substituter + auth for pulling from the private cache
  custom.nix-core.atticCache = {
    enable = true;
    netrcFile = config.age.secrets."nexus/attic-netrc".path;
  };

  # Token generation:
  #   sudo atticd-atticadm make-token --sub matteo --validity 2y \
  #     --pull '*' --push '*' --create-cache '*'
  services.atticd = {
    enable = true;

    # Contains ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
    environmentFile = config.age.secrets."nexus/attic-env".path;

    settings = {
      listen = "127.0.0.1:8080"; # Exposed via Caddy only
      api-endpoint = "https://cache.matteopacini.me/";

      database.url = "postgresql:///atticd?host=/run/postgresql";

      storage = {
        type = "local";
        path = "/diskpool/attic";
      };

      # Large chunks: fewer files on the mergerfs pool.
      # (Module default is 16-64KB chunks, tuned for dedup.)
      chunking = {
        nar-size-threshold = 1048576; # 1MB - don't chunk small packages
        min-size = 65536; # 64KB min
        avg-size = 262144; # 256KB target
        max-size = 1048576; # 1MB max
      };

      compression.type = "zstd";

      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "3 months";
      };
    };
  };
}
