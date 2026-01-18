{ pkgs, config, ... }:
let
  dataDir = config.services.radarr.dataDir;

  migrateRadarrToPostgres = pkgs.writeShellScriptBin "migrate-radarr-to-postgres" ''
    set -euo pipefail

    RADARR_DB="${dataDir}/radarr.db"

    echo "=== Radarr SQLite to PostgreSQL Migration ==="
    echo ""

    # Check if service is running - abort if so
    if systemctl is-active --quiet radarr; then
      echo "ERROR: Radarr service is running. Please stop it first:"
      echo "  sudo systemctl stop radarr"
      exit 1
    fi

    # Check if SQLite database exists
    if [[ ! -f "$RADARR_DB" ]]; then
      echo "ERROR: SQLite database not found at $RADARR_DB"
      exit 1
    fi

    echo "Step 1: Clearing default data from PostgreSQL tables..."
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "QualityProfiles";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "QualityDefinitions";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "DelayProfiles";'
    sudo -u postgres psql -d "radarr-main" -c 'DELETE FROM "Metadata";'

    echo "Step 2: Migrating data with pgloader..."
    # Clean up pgloader temp directory to avoid permission issues
    rm -rf /tmp/pgloader
    sudo -u radarr ${pkgs.pgloader}/bin/pgloader \
      --with "quote identifiers" \
      --with "data only" \
      "$RADARR_DB" \
      "postgresql:///radarr-main?host=/run/postgresql"

    echo ""
    echo "=== Migration Complete ==="
    echo ""
    echo "Make sure your config.xml contains these PostgreSQL settings:"
    echo ""
    echo "  <PostgresUser>radarr</PostgresUser>"
    echo "  <PostgresHost>/run/postgresql</PostgresHost>"
    echo "  <PostgresPort>5432</PostgresPort>"
    echo "  <PostgresMainDb>radarr-main</PostgresMainDb>"
    echo "  <PostgresLogDb>radarr-log</PostgresLogDb>"
    echo ""
    echo "You can now start Radarr and verify it works:"
    echo "  sudo systemctl start radarr"
    echo ""
    echo "If everything works, you can optionally remove the old SQLite database:"
    echo "  rm ${dataDir}/radarr.db"
    echo "  rm ${dataDir}/logs.db"
  '';
in
{
  environment.systemPackages = [ migrateRadarrToPostgres ];

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
  };
}
