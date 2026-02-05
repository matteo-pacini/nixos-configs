{ config, ... }:
{
  users.users."radarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true; # Direct port access (7878)
  };

  # Radarr requires PostgreSQL to be running
  systemd.services.radarr = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    serviceConfig = {
      # Allow changing ownership of imported files from download clients
      AmbientCapabilities = [ "CAP_CHOWN" "CAP_FOWNER" ];
      CapabilityBoundingSet = [ "CAP_CHOWN" "CAP_FOWNER" ];
    };
  };
}
