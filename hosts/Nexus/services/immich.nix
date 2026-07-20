{ ... }:
{
  # Media library lives on the mergerfs pool. The module only adjusts
  # perms on the default /var/lib/immich; a non-default mediaLocation
  # must be created by us (module docs). Owned by the module's static
  # immich user (isSystemUser, not DynamicUser) so the UID is stable
  # for pool ownership.
  systemd.tmpfiles.rules = [
    "d /diskpool/immich 0700 immich immich -"
  ];

  services.immich = {
    enable = true;

    host = "127.0.0.1"; # Exposed via Caddy only
    port = 2283;
    openFirewall = false;

    mediaLocation = "/diskpool/immich";

    machine-learning.enable = true;

    # Reuse the existing Postgres singleton over the unix socket
    # (peer auth, no password). database.enable augments that instance
    # in place — it adds the immich DB + role and the pgvector/vectorchord
    # extensions, it does not spawn a second server.
    database = {
      enable = true;
      createDB = true;
      host = "/run/postgresql";
      name = "immich";
      user = "immich";
    };

    # Dedicated immich redis on its own unix socket (no collision).
    redis.enable = true;
  };
}
