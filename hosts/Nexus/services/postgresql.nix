{ pkgs, ... }:
let
  setupArrDatabases = pkgs.writeShellScriptBin "setup-arr-databases" ''
    set -euo pipefail

    echo "Setting up Radarr/Sonarr PostgreSQL database ownership..."

    # Set ownership for Radarr databases
    sudo -u postgres psql -c 'ALTER DATABASE "radarr-main" OWNER TO radarr;'
    sudo -u postgres psql -c 'ALTER DATABASE "radarr-log" OWNER TO radarr;'
    echo "✓ Radarr databases ownership set"

    # Set ownership for Sonarr databases
    sudo -u postgres psql -c 'ALTER DATABASE "sonarr-main" OWNER TO sonarr;'
    sudo -u postgres psql -c 'ALTER DATABASE "sonarr-log" OWNER TO sonarr;'
    echo "✓ Sonarr databases ownership set"

    echo ""
    echo "Done! You can verify with:"
    echo "  sudo -u postgres psql -c '\\l'"
  '';
in
{
  environment.systemPackages = [ setupArrDatabases ];

  services.postgresql = {
    enable = true;
    ensureDatabases = [
      "hass"
      "grafana"
      "nextcloud"
      # Radarr databases (main + log)
      "radarr-main"
      "radarr-log"
      # Sonarr databases (main + log)
      "sonarr-main"
      "sonarr-log"
    ];
    ensureUsers = [
      {
        name = "hass";
        ensureDBOwnership = true;
      }
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
      {
        name = "nextcloud";
        ensureDBOwnership = true;
      }
      # Radarr user (ownership set via script, db names don't match username)
      {
        name = "radarr";
      }
      # Sonarr user (ownership set via script, db names don't match username)
      {
        name = "sonarr";
      }
    ];
  };

  services.postgresqlBackup = {
    enable = true;
    startAt = "*-*-* 02:30:00";
  };
}
