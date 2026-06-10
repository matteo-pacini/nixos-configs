{ config, ... }:
{
  users.users."sonarr" = {
    extraGroups = [
      "media"
      "downloads"
    ];
  };

  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = false; # tailnet + trusted-device rule in ../networking.nix
  };

  # Sonarr requires PostgreSQL to be running
  systemd.services.sonarr = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    serviceConfig = {
      # Allow changing ownership of imported files from download clients
      AmbientCapabilities = [
        "CAP_CHOWN"
        "CAP_FOWNER"
      ];
      CapabilityBoundingSet = [
        "CAP_CHOWN"
        "CAP_FOWNER"
      ];
    };
  };
}
